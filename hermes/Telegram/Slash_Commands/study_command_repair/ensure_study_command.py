#!/usr/bin/env python3
"""Install/repair the Hermes Telegram /study quick command across clone bots.

This script updates the active shared Hermes config with a prompt-type /study
command and refreshes Telegram BotCommand scopes for all local Telegram bot
homes without printing bot tokens.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML  # type: ignore
except Exception:  # pragma: no cover - fallback for non-Hermes Python
    YAML = None  # type: ignore

PROMPT = '''You are executing the Hermes Telegram `/study` custom command. Treat everything after `/study` as the user's concrete script/app/task/request.

Goal: create the requested script/app/files inside the most suitable location under `F:\\study` (WSL `/mnt/f/study`) and finish by outputting the full path to the primary script/app entry file.

Required workflow:
1. If the text after `/study` does not contain a concrete script/app/task/request, ask only for the missing request.
2. Inspect `/mnt/f/study` before choosing a destination. Find the most semantically suitable existing branch for this specific request (for example by domain, platform, language, tool, or project). Do not rely on memory alone.
3. The final destination must be at least six directory layers deep under `F:\\study`. Count layers after `study`; if the best existing branch is shallower than six layers, create fitting subfolders until it is at least six layers deep.
4. Before creating files, create one new folder with a short, descriptive, task-specific name inside that chosen deep branch. Do all creation inside that folder.
5. If any files for this `/study` request were already created elsewhere during the current run, create the fitting destination folder and move every created artifact into it, with no exceptions, before finishing.
6. Implement the requested script/app/task fully. Inspect existing related files before editing; make minimal correct changes; avoid touching unrelated files.
7. Verify the result with appropriate checks for the created artifact (syntax check, unit test, dry run, help output, file existence, or other task-specific verification). If a browser/web UI is needed, use the real Windows Chrome Profile 2 on monitor 2 and never a cloned/sandbox profile.
8. Final reply must include the exact Windows path and WSL path to the primary script/app entry file, plus concise verification performed. If completion is blocked, report the exact blocker and do not claim success.
'''

STUDY_COMMAND = {
    "type": "prompt",
    "description": "Create scripts/apps under the best deep F-study path",
    "prompt": PROMPT,
}

DEFAULT_SCOPES = [
    ("default", {"type": "default"}),
    ("all_private_chats", {"type": "all_private_chats"}),
    ("chat:716239770", {"type": "chat", "chat_id": 716239770}),
]


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for raw in path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def candidate_homes() -> list[Path]:
    homes: list[Path] = []
    for p in [Path.home() / ".hermes", *sorted(Path.home().glob(".hermes-*"))]:
        if p.is_dir() and (p / ".env").exists() and (p / "config.yaml").exists():
            homes.append(p)
    return homes


def update_config(config_path: Path) -> None:
    if YAML is None:
        import yaml  # type: ignore
        data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
        data.setdefault("quick_commands", {})["study"] = STUDY_COMMAND
        config_path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")
        return
    yaml = YAML()
    yaml.preserve_quotes = True
    with config_path.open("r", encoding="utf-8") as fh:
        data = yaml.load(fh) or {}
    data.setdefault("quick_commands", {})["study"] = STUDY_COMMAND
    with config_path.open("w", encoding="utf-8") as fh:
        yaml.dump(data, fh)


def get_menu_commands(home: Path) -> list[dict[str, str]]:
    os.environ["HERMES_HOME"] = str(home)
    from hermes_cli.commands import telegram_menu_commands  # type: ignore

    raw = telegram_menu_commands()[0]
    seen: set[str] = set()
    commands: list[dict[str, str]] = []
    for name, desc in raw:
        name = str(name)[:32]
        if not name or name in seen:
            continue
        seen.add(name)
        commands.append({"command": name, "description": (str(desc or name))[:256]})
    if not any(c["command"] == "study" for c in commands):
        commands.append({"command": "study", "description": STUDY_COMMAND["description"]})
    # Telegram hard cap is 100. Preserve /study if trimming is needed.
    if len(commands) > 100:
        study = [c for c in commands if c["command"] == "study"]
        others = [c for c in commands if c["command"] != "study"][: 100 - len(study)]
        commands = others + study
    return commands


def telegram_call(token: str, method: str, payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/{method}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def refresh_home(home: Path, commands: list[dict[str, str]]) -> dict[str, Any]:
    env = load_env(home / ".env")
    token = env.get("TELEGRAM_BOT_TOKEN")
    if not token:
        return {"home": str(home), "skipped": "missing TELEGRAM_BOT_TOKEN"}
    me = telegram_call(token, "getMe", {})["result"]
    scope_results = []
    for label, scope in DEFAULT_SCOPES:
        set_result = telegram_call(token, "setMyCommands", {"commands": commands, "scope": scope})
        if not set_result.get("ok"):
            raise RuntimeError(f"setMyCommands failed for {home} {label}: {set_result}")
        verify = telegram_call(token, "getMyCommands", {"scope": scope}).get("result", [])
        has_study = any(c.get("command") == "study" for c in verify)
        if not has_study:
            raise RuntimeError(f"/study missing after refresh for {home} {label}")
        scope_results.append({"scope": label, "count": len(verify), "study": True})
    return {"home": str(home), "bot": me.get("username"), "scopes": scope_results}


def main() -> int:
    homes = candidate_homes()
    if not homes:
        print("ERROR: no Hermes Telegram homes found", file=sys.stderr)
        return 2
    # Config is shared by this clone fleet; use the first real config path and update all
    # distinct config paths in case a future clone has a private config.
    configs = sorted({h.joinpath("config.yaml").resolve() for h in homes})
    for cfg in configs:
        backup = cfg.with_name(cfg.name + ".bak-before-study-repair")
        if not backup.exists():
            backup.write_bytes(cfg.read_bytes())
        update_config(cfg)
    commands = get_menu_commands(homes[0])
    results = [refresh_home(home, commands) for home in homes]
    print(json.dumps({"updated_configs": [str(c) for c in configs], "command_count": len(commands), "study_in_config": True, "menu_refresh": results}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
