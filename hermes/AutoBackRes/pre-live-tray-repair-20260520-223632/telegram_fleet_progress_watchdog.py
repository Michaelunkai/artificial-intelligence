#!/usr/bin/env python3
"""Hermes Telegram fleet progress watchdog.

Sidecar progress layer for already-running gateway sessions. It does not stop or
restart gateways. It watches each bot home's durable session checkpoint and sends
fresh, human-readable Telegram progress messages for every active Telegram
session: one immediately when work is first observed, then one fresh message every
60 seconds until the checkpoint stops running.
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

USER_NAME = os.environ.get("HERMES_WSL_USER", "ubuntu")
HOME_DIR = Path(f"/home/{USER_NAME}")
LOG_FILE = HOME_DIR / ".hermes" / "logs" / "telegram-progress-watchdog.log"
STATE_FILE = HOME_DIR / ".hermes" / ".runtime" / "telegram-progress-watchdog-state.json"
POLL_SECONDS = max(1, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_POLL_SECONDS", "5")))
PROGRESS_SECONDS = max(10, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_EVERY_SECONDS", os.environ.get("HERMES_PROGRESS_WATCHDOG_MAX_UPDATE_SECONDS", "60"))))
STALE_RUNNING_SECONDS = max(3600, int(os.environ.get("HERMES_PROGRESS_WATCHDOG_STALE_RUNNING_SECONDS", "86400")))
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("HERMES_PROGRESS_WATCHDOG_REQUEST_TIMEOUT_SECONDS", "8"))


def log(msg: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().isoformat(timespec="seconds")
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"[{stamp}] {msg}\n")


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


def discover_homes() -> list[Path]:
    homes = [HOME_DIR / ".hermes"] + sorted(HOME_DIR.glob(".hermes-*"))
    out: list[Path] = []
    seen: set[str] = set()
    for h in homes:
        if str(h) in seen:
            continue
        seen.add(str(h))
        if not (h / "config.yaml").exists() or not (h / ".env").exists():
            continue
        if env_value(h / ".env", "TELEGRAM_BOT_TOKEN"):
            out.append(h)
    return out


def load_state() -> dict[str, Any]:
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    try:
        tmp.chmod(0o600)
    except OSError:
        pass
    tmp.replace(STATE_FILE)


def bot_api(token: str, method: str, params: dict[str, Any], timeout: float = REQUEST_TIMEOUT_SECONDS) -> dict[str, Any]:
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{token}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def fmt_elapsed(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m {seconds % 60:02d}s"
    return f"{seconds // 3600}h {(seconds % 3600) // 60:02d}m"


def clean(text: Any, limit: int = 900) -> str:
    s = "" if text is None else str(text)
    s = re.sub(r"\s+", " ", s).strip()
    # Redact secrets/tokens just in case a command preview contains one.
    s = re.sub(r"\b\d{8,12}:[A-Za-z0-9_-]{20,}\b", "[redacted-token]", s)
    s = re.sub(r"(?i)(api[_-]?key|token|secret|password)=\S+", r"\1=[redacted]", s)
    return s if len(s) <= limit else s[: limit - 3] + "..."


def active_checkpoints(home: Path) -> list[tuple[Path, dict[str, Any]]]:
    d = home / ".runtime" / "session-checkpoints"
    if not d.exists():
        return []
    out: list[tuple[Path, dict[str, Any]]] = []
    now = time.time()
    for p in sorted(d.glob("*.json"), key=lambda x: x.stat().st_mtime, reverse=True):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("status") != "running":
            continue
        src = data.get("source") or {}
        if src.get("platform") != "telegram" or not src.get("chat_id"):
            continue
        last = float(data.get("last_update_epoch") or p.stat().st_mtime)
        if now - last > STALE_RUNNING_SECONDS:
            continue
        out.append((p, data))
    return out


def progress_detail_signature(data: dict[str, Any]) -> str:
    parts = [
        clean(data.get("current_activity") or data.get("phase") or "Working", 420),
        clean(data.get("current_tool") or "", 80),
        clean(data.get("current_tool_preview") or data.get("tool_args_preview") or "", 700),
        clean(data.get("last_user_message_preview") or "", 220),
    ]
    return "\n".join(parts)


def format_progress(home: Path, data: dict[str, Any]) -> str:
    started = float(data.get("started_epoch") or data.get("last_update_epoch") or time.time())
    elapsed = fmt_elapsed(time.time() - started)
    activity = clean(data.get("current_activity") or data.get("phase") or "Working", 420)
    tool = clean(data.get("current_tool") or "", 80)
    preview = clean(data.get("current_tool_preview") or data.get("tool_args_preview") or "", 700)
    user = clean(data.get("last_user_message_preview") or "", 220)
    lines = [
        f"[x] {activity}",
        f"Still running: {elapsed}. Next progress update in 60 seconds.",
    ]
    if tool:
        if preview:
            lines.append(f"Current step: {tool}: {preview}")
        else:
            lines.append(f"Current step: {tool}")
    elif user:
        lines.append(f"Request: {user}")
    lines.append("I will keep sending these progress messages every 60 seconds until this finishes.")
    # Keep concise and English-only; this sidecar is user-facing status, not scratchpad.
    return "\n".join(lines)[:3500]


def checkpoint_key(home: Path, path: Path, data: dict[str, Any]) -> str:
    session_key = data.get("session_key") or path.stem
    return f"{home}:{session_key}"


def is_due(item: dict[str, Any], now: float) -> bool:
    # Migration from older edit-based state: force one fresh send immediately.
    if not item or not item.get("fresh_message_count"):
        return True
    return now >= float(item.get("next_due_epoch") or 0)


def next_due_after(item: dict[str, Any], now: float) -> float:
    previous_due = float(item.get("next_due_epoch") or 0)
    if previous_due <= 0:
        return now + PROGRESS_SECONDS
    # Keep the cadence anchored to 60-second slots, but if the process was asleep
    # or Telegram was slow, never schedule another message in the past.
    due = previous_due + PROGRESS_SECONDS
    while due <= now:
        due += PROGRESS_SECONDS
    return due


def run_once(state: dict[str, Any], dry_run: bool = False) -> tuple[dict[str, Any], dict[str, int]]:
    now = time.time()
    active_keys: set[str] = set()
    stats = {"homes": 0, "active": 0, "due": 0, "sent": 0, "failed": 0, "dry_run": int(dry_run)}
    changed_state = False
    for home in discover_homes():
        stats["homes"] += 1
        token = env_value(home / ".env", "TELEGRAM_BOT_TOKEN")
        if not token:
            continue
        for path, data in active_checkpoints(home):
            stats["active"] += 1
            src = data.get("source") or {}
            chat_id = str(src.get("chat_id") or "")
            thread_id = str(src.get("thread_id") or "") or None
            key = checkpoint_key(home, path, data)
            active_keys.add(key)
            item = state.get(key) or {}
            if not is_due(item, now):
                continue
            stats["due"] += 1
            text = format_progress(home, data)
            detail_sig = progress_detail_signature(data)
            params: dict[str, Any] = {"chat_id": chat_id, "text": text, "disable_notification": "true"}
            if thread_id:
                try:
                    params["message_thread_id"] = int(thread_id)
                except Exception:
                    pass
            try:
                if dry_run:
                    message_id = int(item.get("last_message_id") or 0) + 1
                    ok = True
                else:
                    res = bot_api(token, "sendMessage", params)
                    ok = bool(res.get("ok"))
                    message_id = (res.get("result") or {}).get("message_id") if ok else None
                if ok:
                    state[key] = {
                        "home": str(home),
                        "session_key": data.get("session_key") or path.stem,
                        "chat_id": chat_id,
                        "last_message_id": message_id,
                        "last_sent_epoch": now,
                        "next_due_epoch": next_due_after(item, now),
                        "last_text": text,
                        "last_detail_signature": detail_sig,
                        "fresh_message_count": int(item.get("fresh_message_count") or 0) + 1,
                        "cadence_seconds": PROGRESS_SECONDS,
                    }
                    stats["sent"] += 1
                    changed_state = True
                    log(f"PROGRESS_FRESH_MESSAGE_OK home={home} session={data.get('session_key') or path.stem} chat={chat_id} message_id={message_id} next_due={int(state[key]['next_due_epoch'])} cadence={PROGRESS_SECONDS}s dry_run={dry_run}")
                else:
                    stats["failed"] += 1
                    log(f"PROGRESS_FRESH_MESSAGE_FAIL home={home} session={data.get('session_key') or path.stem} chat={chat_id} result_not_ok")
            except Exception as exc:
                stats["failed"] += 1
                # Retry on the next poll instead of waiting a full minute after a failed send.
                item["next_due_epoch"] = now + min(10, PROGRESS_SECONDS)
                state[key] = item
                changed_state = True
                log(f"PROGRESS_FRESH_MESSAGE_FAIL home={home} session={data.get('session_key') or path.stem} error={type(exc).__name__}:{exc}")
    # Do not delete old Telegram messages; forget completed/inactive sessions after a while.
    for key in list(state.keys()):
        if key not in active_keys and now - float(state[key].get("last_sent_epoch") or 0) > 3600:
            state.pop(key, None)
            changed_state = True
    if changed_state and not dry_run:
        save_state(state)
    return state, stats


def main() -> None:
    parser = argparse.ArgumentParser(description="Send fresh Telegram progress messages every 60 seconds for active Hermes fleet work.")
    parser.add_argument("--once", action="store_true", help="run one scan then exit")
    parser.add_argument("--dry-run", action="store_true", help="do not call Telegram; print JSON stats")
    args = parser.parse_args()

    log(f"PROGRESS_WATCHDOG_STARTED mode=fresh_messages cadence={PROGRESS_SECONDS}s poll={POLL_SECONDS}s")
    state = load_state()
    while True:
        try:
            state, stats = run_once(state, dry_run=args.dry_run)
            if args.once:
                print(json.dumps(stats, sort_keys=True))
                return
        except Exception as exc:
            log(f"PROGRESS_WATCHDOG_LOOP_ERROR {type(exc).__name__}: {exc}")
            if args.once:
                raise
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
