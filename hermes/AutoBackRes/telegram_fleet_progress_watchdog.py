#!/usr/bin/env python3
"""Low-noise Hermes Telegram progress sidecar.

This process is intentionally outside the Hermes gateway. It observes local
checkpoint files and updates a single silent progress message per active
Telegram mission. It never calls a model/provider API and never changes mission
processes, checkpoints, or gateway state.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

MODE = "low_noise_edit_zero_token_v1"
USER_NAME = os.environ.get("HERMES_WSL_USER", "ubuntu")
HOME_DIR = Path(f"/home/{USER_NAME}")
ROOT_HOME = HOME_DIR / ".hermes"
LOG_FILE = ROOT_HOME / "logs" / "telegram-progress-watchdog.log"
STATE_FILE = ROOT_HOME / ".runtime" / "telegram-progress-watchdog-state.json"
REQUIRED_HOME_NAMES = [
    ".hermes",
    ".hermes-michahermes5bot",
    ".hermes-michaopenclawbot",
    ".hermes-mmichael_moltbot_bot",
    ".hermes-mmmoltbot_bot",
]

POLL_ACTIVE_SECONDS = max(1, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_POLL_SECONDS", "2")))
POLL_IDLE_SECONDS = max(POLL_ACTIVE_SECONDS, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_IDLE_POLL_SECONDS", "10")))
HEARTBEAT_SECONDS = max(30, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_EVERY_SECONDS", "60")))
MIN_EDIT_SECONDS = max(5, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_MIN_EDIT_SECONDS", "8")))
STALE_RUNNING_SECONDS = max(3600, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_STALE_RUNNING_SECONDS", "86400")))
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("HERMES_PROGRESS_WATCHDOG_REQUEST_TIMEOUT_SECONDS", "8"))


def log(msg: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().isoformat(timespec="seconds")
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"[{stamp}] {msg}\n")


def clean(text: Any, limit: int = 240) -> str:
    value = "" if text is None else str(text)
    value = value.replace("`", "").strip()
    value = re.sub(r"\s+", " ", value)
    value = re.sub(r"\b\d{8,12}:[A-Za-z0-9_-]{20,}\b", "[redacted-telegram-token]", value)
    value = re.sub(r"(?i)\b(api[_-]?key|token|secret|password)\s*=\s*\S+", r"\1=[redacted]", value)
    value = re.sub(r"(?i)bearer\s+[A-Za-z0-9._-]+", "bearer [redacted]", value)
    if len(value) > limit:
        return value[: limit - 3].rstrip() + "..."
    return value


def env_value(path: Path, key: str) -> str:
    try:
        for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            name, value = line.split("=", 1)
            if name.strip() == key:
                value = value.strip()
                if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                    value = value[1:-1]
                return value
    except Exception:
        return ""
    return ""


def discover_homes() -> tuple[list[Path], list[str]]:
    homes: list[Path] = []
    issues: list[str] = []
    for name in REQUIRED_HOME_NAMES:
        home = HOME_DIR / name
        try:
            if not home.exists():
                issues.append(f"missing:{home}")
                continue
            if not (home / ".env").exists():
                issues.append(f"env-missing:{home}")
                continue
            if not env_value(home / ".env", "TELEGRAM_BOT_TOKEN"):
                issues.append(f"token-missing:{home}")
                continue
            homes.append(home)
        except OSError as exc:
            issues.append(f"unreadable:{home}:{type(exc).__name__}")
    return homes, issues


def read_json(path: Path, default: Any) -> Any:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data
    except Exception:
        return default


def save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    try:
        tmp.chmod(0o600)
    except OSError:
        pass
    tmp.replace(STATE_FILE)


def bot_api(token: str, method: str, params: dict[str, Any]) -> dict[str, Any]:
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{token}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def fmt_elapsed(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m {seconds % 60:02d}s"
    return f"{seconds // 3600}h {(seconds % 3600) // 60:02d}m"


def active_checkpoints(home: Path) -> list[tuple[Path, dict[str, Any]]]:
    checkpoint_dir = home / ".runtime" / "session-checkpoints"
    if not checkpoint_dir.exists():
        return []
    now = time.time()
    rows: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(checkpoint_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        data = read_json(path, {})
        if not isinstance(data, dict):
            continue
        if data.get("status") != "running":
            continue
        source = data.get("source") or {}
        if source.get("platform") != "telegram" or not source.get("chat_id"):
            continue
        last = float(data.get("last_update_epoch") or path.stat().st_mtime)
        if now - last > STALE_RUNNING_SECONDS:
            continue
        rows.append((path, data))
    return rows


def checkpoint_key(home: Path, path: Path, data: dict[str, Any]) -> str:
    return f"{home}:{data.get('session_key') or path.stem}"


def task_label(data: dict[str, Any]) -> str:
    text = clean(data.get("last_user_message_preview") or data.get("last_user_message") or "Telegram mission", 180)
    text = re.sub(r"^\[Replying to:.*?\]\s*", "", text, flags=re.I)
    if text.startswith("[System note:") or "Durable Hermes recovery checkpoint" in text:
        return "resuming the current Telegram mission"
    return text or "Telegram mission"


def process_lookup(home: Path) -> dict[str, dict[str, Any]]:
    rows = read_json(home / "processes.json", [])
    if not isinstance(rows, list):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if isinstance(row, dict) and row.get("session_id"):
            out[str(row["session_id"])] = row
    return out


def proc_alive(pid: Any) -> bool:
    try:
        return bool(pid) and Path("/proc").joinpath(str(int(pid))).exists()
    except Exception:
        return False


def summarize_command(command: str, tool: str) -> str:
    lower = command.lower()
    if tool == "process":
        proc_id = re.search(r"\bproc_[A-Za-z0-9]+\b", command)
        return f"monitoring background process {proc_id.group(0)}" if proc_id else "monitoring a background process"
    if tool in {"read_file", "write_file", "patch"}:
        parts = re.findall(r"[/\\][^ '\"|]+", command)
        if parts:
            return f"{tool.replace('_', ' ')} {Path(parts[-1]).name}"
        return tool.replace("_", " ")
    if "powershell" in lower or lower.endswith(".ps1"):
        scripts = re.findall(r"[\w./:\\-]+\.ps1", command, flags=re.I)
        if scripts:
            return f"running PowerShell script {Path(scripts[-1]).name}"
        return "running PowerShell verification"
    if "curl " in lower or "invoke-webrequest" in lower or "download" in lower:
        return "downloading and verifying required files"
    if "python" in lower or lower.endswith(".py"):
        scripts = re.findall(r"[\w./:\\-]+\.py", command, flags=re.I)
        if scripts:
            return f"running Python helper {Path(scripts[-1]).name}"
        return "running a Python helper"
    if "npm " in lower or "pnpm " in lower or "node " in lower:
        return "running a Node.js tool"
    if "rg " in lower or "grep " in lower:
        return "searching local files"
    if "tmux" in lower:
        return "checking Hermes session state"
    label = clean(tool.replace("_", " "), 80)
    return f"running {label}" if label else "working"


def action_detail(home: Path, data: dict[str, Any]) -> tuple[str, str]:
    tool = clean(data.get("current_tool") or "", 80)
    preview = clean(data.get("current_tool_preview") or data.get("tool_args_preview") or "", 900)
    phase = clean(data.get("phase") or "", 80).replace("_", " ")
    if tool == "process":
        proc_id_match = re.search(r"\bproc_[A-Za-z0-9]+\b", preview)
        if proc_id_match:
            proc_id = proc_id_match.group(0)
            proc = process_lookup(home).get(proc_id, {})
            pid = proc.get("pid")
            status = "running" if proc_alive(pid) else "not visible"
            elapsed = ""
            try:
                elapsed = fmt_elapsed(time.time() - float(proc.get("started_at")))
            except Exception:
                pass
            label = f"monitoring background process {proc_id}"
            detail = f"pid {pid} {status}" if pid else status
            if elapsed:
                detail += f" for {elapsed}"
            return label, detail
    label = summarize_command(preview, tool)
    detail = f"phase {phase}" if phase else "checkpoint is live"
    return label, detail


def progress_signature(home: Path, data: dict[str, Any]) -> str:
    label, detail = action_detail(home, data)
    return "|".join([
        clean(data.get("session_key") or "", 120),
        clean(data.get("current_activity") or "", 120),
        label,
        detail,
        clean(data.get("phase") or "", 80),
    ])


def format_progress(home: Path, data: dict[str, Any]) -> str:
    now = time.time()
    started = float(data.get("started_epoch") or data.get("last_update_epoch") or now)
    updated = float(data.get("last_update_epoch") or now)
    label, detail = action_detail(home, data)
    lines = [
        f"Working on: {task_label(data)}",
        f"Elapsed: {fmt_elapsed(now - started)}",
        f"Now: {label}",
        f"Status: {detail}; checkpoint updated {fmt_elapsed(now - updated)} ago",
        f"Next update: this message will refresh on meaningful changes or after {HEARTBEAT_SECONDS}s.",
    ]
    return "\n".join(clean(line, 700) for line in lines)[:3500]


def next_due_after(previous: float, now: float) -> float:
    due = previous + HEARTBEAT_SECONDS if previous > 0 else now + HEARTBEAT_SECONDS
    while due <= now:
        due += HEARTBEAT_SECONDS
    return due


def send_message(token: str, chat_id: str, thread_id: str | None, text: str) -> int | None:
    params: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "disable_notification": "true",
        "disable_web_page_preview": "true",
    }
    if thread_id:
        try:
            params["message_thread_id"] = int(thread_id)
        except Exception:
            pass
    payload = bot_api(token, "sendMessage", params)
    if not payload.get("ok"):
        return None
    message_id = (payload.get("result") or {}).get("message_id")
    return int(message_id) if message_id else None


def edit_message(token: str, chat_id: str, message_id: int, text: str) -> bool:
    params = {
        "chat_id": chat_id,
        "message_id": str(message_id),
        "text": text,
        "disable_web_page_preview": "true",
    }
    try:
        return bool(bot_api(token, "editMessageText", params).get("ok"))
    except Exception as exc:
        log(f"PROGRESS_EDIT_FAILED message_id={message_id} error={type(exc).__name__}:{exc}")
        return False


def mark_inactive(state: dict[str, Any], active_keys: set[str], now: float) -> bool:
    changed = False
    for key, value in list(state.items()):
        if key.startswith("_") or not isinstance(value, dict):
            continue
        if key in active_keys:
            continue
        if value.get("active") is not False:
            value["active"] = False
            value["inactive_since_epoch"] = now
            value["inactive_since"] = dt.datetime.now(dt.timezone.utc).isoformat()
            value["mode"] = value.get("mode") or MODE
            state[key] = value
            changed = True
    return changed


def run_once(state: dict[str, Any], dry_run: bool = False) -> tuple[dict[str, Any], dict[str, int | list[str] | str]]:
    now = time.time()
    homes, issues = discover_homes()
    stats: dict[str, int | list[str] | str] = {
        "mode": MODE,
        "homes": len(homes),
        "required_homes": len(REQUIRED_HOME_NAMES),
        "active": 0,
        "due": 0,
        "sent": 0,
        "edited": 0,
        "would_send": 0,
        "would_edit": 0,
        "failed": 0,
        "telegram_calls": 0,
        "dry_run": int(dry_run),
        "issues": issues,
    }
    active_keys: set[str] = set()
    changed = False

    for home in homes:
        token = env_value(home / ".env", "TELEGRAM_BOT_TOKEN")
        for path, data in active_checkpoints(home):
            stats["active"] = int(stats["active"]) + 1
            source = data.get("source") or {}
            chat_id = str(source.get("chat_id") or "")
            thread_id = str(source.get("thread_id") or "") or None
            if not chat_id or not token:
                stats["failed"] = int(stats["failed"]) + 1
                continue

            key = checkpoint_key(home, path, data)
            active_keys.add(key)
            item = state.get(key) if isinstance(state.get(key), dict) else {}
            assert isinstance(item, dict)
            text = format_progress(home, data)
            sig = progress_signature(home, data)
            message_id = int(item.get("last_message_id") or item.get("message_id") or 0)
            last_sent = float(item.get("last_sent_epoch") or 0)
            old_mode = item.get("mode") != MODE
            sig_changed = sig != item.get("last_detail_signature")
            due = old_mode or not message_id or sig_changed or now >= float(item.get("next_due_epoch") or 0)
            if message_id and sig_changed and now - last_sent < MIN_EDIT_SECONDS and not old_mode:
                due = False

            if not due:
                continue

            stats["due"] = int(stats["due"]) + 1
            if dry_run:
                if message_id:
                    stats["would_edit"] = int(stats["would_edit"]) + 1
                else:
                    stats["would_send"] = int(stats["would_send"]) + 1
                continue

            delivered_message_id = message_id
            if message_id and edit_message(token, chat_id, message_id, text):
                stats["edited"] = int(stats["edited"]) + 1
                stats["telegram_calls"] = int(stats["telegram_calls"]) + 1
                action = "edited"
            else:
                delivered_message_id = send_message(token, chat_id, thread_id, text)
                stats["telegram_calls"] = int(stats["telegram_calls"]) + 1
                if delivered_message_id:
                    stats["sent"] = int(stats["sent"]) + 1
                    action = "sent"
                else:
                    stats["failed"] = int(stats["failed"]) + 1
                    log(f"PROGRESS_LOW_NOISE_FAIL home={home} session={data.get('session_key') or path.stem}")
                    continue

            state[key] = {
                **item,
                "mode": MODE,
                "active": True,
                "home": str(home),
                "session_key": data.get("session_key") or path.stem,
                "chat_id": chat_id,
                "last_message_id": delivered_message_id,
                "last_sent_epoch": now,
                "last_sent_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "next_due_epoch": next_due_after(float(item.get("next_due_epoch") or 0), now),
                "last_text": text,
                "last_detail_signature": sig,
                "cadence_seconds": HEARTBEAT_SECONDS,
                "edit_count": int(item.get("edit_count") or 0) + (1 if action == "edited" else 0),
                "replacement_message_count": int(item.get("replacement_message_count") or 0) + (1 if action == "sent" and message_id else 0),
            }
            changed = True
            log(f"PROGRESS_LOW_NOISE_{action.upper()} home={home} session={data.get('session_key') or path.stem} chat={chat_id} message_id={delivered_message_id} next_due={int(state[key]['next_due_epoch'])}")

    if mark_inactive(state, active_keys, now):
        changed = True
    state["_watchdog_runtime"] = {
        "mode": MODE,
        "updated_epoch": now,
        "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "required_homes": REQUIRED_HOME_NAMES,
        "observed_homes": [str(h) for h in homes],
        "last_stats": stats,
    }
    changed = True
    if changed and not dry_run:
        save_state(state)
    return state, stats


def self_test() -> None:
    synthetic = {
        "status": "running",
        "session_key": "agent:main:telegram:dm:123",
        "started_epoch": time.time() - 125,
        "last_update_epoch": time.time() - 2,
        "current_activity": "Running tool terminal",
        "current_tool": "terminal",
        "current_tool_preview": "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\Temp\\huge_secret_script.ps1 token=1234567890:abcdefghijklmnopqrstuvwxyz",
        "source": {"platform": "telegram", "chat_id": "123"},
        "last_user_message_preview": "[Replying to: noisy old text] continue the task",
        "phase": "tool_started",
    }
    text = format_progress(ROOT_HOME, synthetic)
    forbidden = [
        "I will keep " + "sending",
        "Still " + "running",
        "[x] " + "Running tool",
        "Current " + "step:",
        "abcdefghijklmnopqrstuvwxyz",
    ]
    failures = [item for item in forbidden if item in text]
    if failures:
        raise SystemExit("self-test failed: forbidden output " + ",".join(failures))
    if "PowerShell" not in text:
        raise SystemExit("self-test failed: command was not summarized")
    print(json.dumps({"self_test": "ok", "mode": MODE, "sample": text}, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description="Low-noise Hermes Telegram progress sidecar.")
    parser.add_argument("--once", action="store_true", help="run one scan then exit")
    parser.add_argument("--dry-run", action="store_true", help="avoid Telegram writes and report would-send/would-edit stats")
    parser.add_argument("--self-test", action="store_true", help="run formatter safety checks")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    state = read_json(STATE_FILE, {})
    if not isinstance(state, dict):
        state = {}
    if not args.once:
        log(f"PROGRESS_WATCHDOG_STARTED mode={MODE} cadence={HEARTBEAT_SECONDS}s poll_active={POLL_ACTIVE_SECONDS}s")
    while True:
        state, stats = run_once(state, dry_run=args.dry_run)
        if args.once:
            print(json.dumps(stats, sort_keys=True))
            return
        sleep_for = POLL_ACTIVE_SECONDS if int(stats.get("active") or 0) else POLL_IDLE_SECONDS
        time.sleep(sleep_for)


if __name__ == "__main__":
    main()
