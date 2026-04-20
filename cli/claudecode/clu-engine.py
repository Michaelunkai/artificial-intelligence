"""CLU Engine - Claude Code Real-Time Usage & Rate Limits.
Makes a minimal API call using the OAuth token to read rate limit headers.
Also aggregates token usage from local session logs."""
import os, sys, json, time
from collections import defaultdict


def get_token():
    """Get the OAuth token from environment (set by Claude Code)."""
    for var in ('CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_OAUTH_TOKEN'):
        token = os.environ.get(var)
        if token:
            return token
    return None


def fetch_rate_limits(token):
    """Make a minimal API call with Haiku and extract rate limit headers."""
    import urllib.request, urllib.error

    data = json.dumps({
        'model': 'claude-haiku-4-5-20251001',
        'max_tokens': 1024,
        'messages': [{'role': 'user', 'content': 'OK'}],
    }).encode()

    req = urllib.request.Request(
        'https://api.anthropic.com/v1/messages',
        data=data,
        headers={
            'Authorization': f'Bearer {token}',
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
            'anthropic-beta': 'oauth-2025-04-20',
        },
    )

    resp_headers = {}
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        resp_headers = dict(resp.headers)
    except urllib.error.HTTPError as e:
        resp_headers = dict(e.headers)
        if e.code == 401:
            return None, "Authentication failed. Run CLU from inside a Claude Code session."
        if e.code == 429:
            pass  # rate limited but headers still have the data we need
        elif e.code != 200:
            body = ''
            try:
                body = e.read().decode()[:300]
            except Exception:
                pass
            return None, f"API error {e.code}: {body}"
    except Exception as e:
        return None, f"Request failed: {e}"

    return resp_headers, None


def parse_rate_limits(headers):
    """Parse anthropic-ratelimit-unified-* headers."""
    limits = {}

    limit_defs = [
        ('five_hour', '5h', 18000),
        ('seven_day', '7d', 604800),
        ('seven_day_sonnet', 'sonnet', 604800),
        ('seven_day_opus', 'opus', 604800),
        ('overage', 'overage', 0),
    ]

    # Case-insensitive header lookup helper
    h_lower = {h.lower(): v for h, v in headers.items()}

    for limit_name, abbrev, window_secs in limit_defs:
        prefix = f'anthropic-ratelimit-unified-{abbrev}'
        util_val = h_lower.get(f'{prefix}-utilization')
        reset_val = h_lower.get(f'{prefix}-reset')
        status_val = h_lower.get(f'{prefix}-status')

        if util_val is not None or reset_val is not None or status_val is not None:
            entry = {}
            if status_val is not None:
                entry['status'] = status_val
            if util_val is not None:
                entry['utilization'] = float(util_val)
            if reset_val is not None:
                reset_ts = float(reset_val)
                entry['resets_at'] = reset_ts
                diff = reset_ts - time.time()
                if diff > 0:
                    hours = int(diff // 3600)
                    minutes = int((diff % 3600) // 60)
                    if hours >= 24:
                        days = hours // 24
                        hours = hours % 24
                        entry['resets_in'] = f'{days}d {hours}h'
                    elif hours > 0:
                        entry['resets_in'] = f'{hours}h {minutes}m'
                    else:
                        entry['resets_in'] = f'{minutes}m'
                else:
                    entry['resets_in'] = 'now'
            limits[limit_name] = entry

    overall_status = h_lower.get('anthropic-ratelimit-unified-status', 'unknown')
    fallback = h_lower.get('anthropic-ratelimit-unified-fallback-percentage')
    overage_reason = h_lower.get('anthropic-ratelimit-unified-overage-disabled-reason')

    return limits, overall_status, fallback, overage_reason


def get_session_stats():
    """Aggregate token usage from local Claude Code session logs."""
    claude_dir = os.path.join(os.environ.get('USERPROFILE', os.path.expanduser('~')), '.claude')
    projects_dir = os.path.join(claude_dir, 'projects')

    if not os.path.isdir(projects_dir):
        return None

    total_input = 0
    total_output = 0
    total_cache_create = 0
    total_cache_read = 0
    model_usage = defaultdict(lambda: {'input': 0, 'output': 0, 'cache_create': 0, 'cache_read': 0, 'calls': 0})
    session_count = 0
    msg_count = 0

    for root, dirs, files in os.walk(projects_dir):
        for fname in files:
            if not fname.endswith('.jsonl'):
                continue
            session_count += 1
            fpath = os.path.join(root, fname)
            try:
                with open(fpath, 'r', encoding='utf-8') as fh:
                    for line in fh:
                        try:
                            d = json.loads(line)
                            if not isinstance(d, dict):
                                continue
                            msg = d.get('message')
                            if not isinstance(msg, dict):
                                continue
                            usage = msg.get('usage')
                            if not usage:
                                continue
                            msg_count += 1
                            inp = usage.get('input_tokens', 0)
                            out = usage.get('output_tokens', 0)
                            cc = usage.get('cache_creation_input_tokens', 0)
                            cr = usage.get('cache_read_input_tokens', 0)
                            total_input += inp
                            total_output += out
                            total_cache_create += cc
                            total_cache_read += cr
                            model = msg.get('model', 'unknown')
                            model_usage[model]['input'] += inp
                            model_usage[model]['output'] += out
                            model_usage[model]['cache_create'] += cc
                            model_usage[model]['cache_read'] += cr
                            model_usage[model]['calls'] += 1
                        except (json.JSONDecodeError, KeyError):
                            pass
            except (OSError, IOError):
                pass

    def estimate_cost(model_name, u):
        ml = model_name.lower()
        if 'opus' in ml:
            return (u['input'] * 15 + u['output'] * 75 + u['cache_create'] * 18.75 + u['cache_read'] * 1.50) / 1_000_000
        elif 'haiku' in ml:
            return (u['input'] * 0.80 + u['output'] * 4 + u['cache_create'] * 1.00 + u['cache_read'] * 0.08) / 1_000_000
        else:
            return (u['input'] * 3 + u['output'] * 15 + u['cache_create'] * 3.75 + u['cache_read'] * 0.30) / 1_000_000

    models_out = {}
    total_cost = 0.0
    for model, u in model_usage.items():
        cost = estimate_cost(model, u)
        total_cost += cost
        models_out[model] = {
            'calls': u['calls'],
            'input_tokens': u['input'],
            'output_tokens': u['output'],
            'cache_creation_tokens': u['cache_create'],
            'cache_read_tokens': u['cache_read'],
            'estimated_cost_usd': round(cost, 4),
        }

    return {
        'sessions': session_count,
        'api_calls': msg_count,
        'tokens': {
            'input': total_input,
            'output': total_output,
            'cache_creation': total_cache_create,
            'cache_read': total_cache_read,
            'total': total_input + total_output + total_cache_create + total_cache_read,
        },
        'models': models_out,
        'estimated_total_cost_usd': round(total_cost, 4),
    }


def main():
    result = {}
    token = get_token()

    if token:
        headers, err = fetch_rate_limits(token)
        if err:
            result['rate_limit_error'] = err
        elif headers:
            limits, status, fallback, overage_reason = parse_rate_limits(headers)
            result['rate_limits'] = limits
            result['rate_limit_status'] = status
            if fallback:
                result['fallback_percentage'] = float(fallback)
            if overage_reason:
                result['overage_disabled_reason'] = overage_reason
    else:
        result['rate_limit_error'] = 'No OAuth token found. Run CLU from inside a Claude Code session.'

    stats = get_session_stats()
    if stats:
        result['session_stats'] = stats

    print(json.dumps(result))


if __name__ == '__main__':
    main()
