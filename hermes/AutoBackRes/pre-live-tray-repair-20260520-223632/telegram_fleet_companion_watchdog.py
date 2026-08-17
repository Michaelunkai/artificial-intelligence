#!/usr/bin/env python3
import datetime as dt
import json
import os
import signal
import subprocess
import time
from pathlib import Path

USER_NAME = os.environ.get("HERMES_WSL_USER", "ubuntu")
HOME_DIR = Path(f"/home/{USER_NAME}")
TRAY_DIR = Path("/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes")
RESUME_SH = TRAY_DIR / "resume.sh"
LOG_FILE = HOME_DIR / ".hermes" / "logs" / "telegram-companion-watchdog.log"
MAX_HEARTBEAT_AGE = int(os.environ.get("HERMES_COMPANION_POLLING_STALE_SECONDS", "180"))
INTERVAL = int(os.environ.get("HERMES_COMPANION_INTERVAL_SECONDS", "30"))
COOLDOWN = int(os.environ.get("HERMES_COMPANION_RESTART_COOLDOWN_SECONDS", "120"))
ALLOW_RESTART = os.environ.get("HERMES_COMPANION_ALLOW_RESTART", "0").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}


def log(msg: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().isoformat(timespec="seconds")
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"[{stamp}] {msg}\n")


def discover_homes():
    homes = [HOME_DIR / ".hermes"]
    homes.extend(sorted(HOME_DIR.glob(".hermes-*")))
    out = []
    seen = set()
    for h in homes:
        if str(h) in seen:
            continue
        seen.add(str(h))
        if not (h / "config.yaml").exists() or not (h / ".env").exists():
            continue
        try:
            if "TELEGRAM_BOT_TOKEN=" not in (h / ".env").read_text(encoding="utf-8", errors="ignore"):
                continue
        except Exception:
            continue
        out.append(h)
    return out


def session_for_home(h: Path) -> str:
    return "hermes-gateway" if h.name == ".hermes" else "hermes-" + h.name.removeprefix(".hermes-")


def gateway_pids_for_home(h: Path):
    pids = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv = [x.decode("utf-8", "ignore") for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
            if not any(a.endswith("/hermes") for a in argv) or argv[-2:] != ["gateway", "run"]:
                continue
            env = {}
            for item in (proc / "environ").read_bytes().split(b"\0"):
                if b"=" in item:
                    k, v = item.split(b"=", 1)
                    env[k.decode("utf-8", "ignore")] = v.decode("utf-8", "ignore")
            if (env.get("HERMES_HOME") or str(HOME_DIR / ".hermes")) == str(h):
                pids.append(int(proc.name))
        except Exception:
            continue
    return sorted(pids)


def heartbeat_age_seconds(h: Path):
    try:
        data = json.loads((h / "gateway_state.json").read_text(encoding="utf-8"))
        telegram = (data.get("platforms") or {}).get("telegram", {})
        active = int(data.get("active_agents") or 0)
        if telegram.get("mode") != "polling" or telegram.get("polling_running") is not True:
            return 10**9, active, "polling_not_running"
        raw = telegram.get("polling_heartbeat_at")
        if not raw:
            return 10**9, active, "heartbeat_missing"
        t = dt.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=dt.timezone.utc)
        return int((dt.datetime.now(dt.timezone.utc) - t).total_seconds()), active, "ok"
    except Exception as exc:
        return 10**9, 0, f"state_error:{exc}"


def exact_restart_home(h: Path, reason: str) -> bool:
    session = session_for_home(h)
    pids = gateway_pids_for_home(h)
    if not ALLOW_RESTART:
        log(
            f"RESTART_SUPPRESSED home={h} session={session} pids={pids} "
            f"reason={reason} set_HERMES_COMPANION_ALLOW_RESTART=1_to_enable"
        )
        return False
    log(f"RESTART_HOME_BEGIN home={h} session={session} pids={pids} reason={reason}")
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except Exception as exc:
            log(f"TERM_FAIL pid={pid} home={h} error={exc}")
    deadline = time.time() + 20
    while time.time() < deadline and gateway_pids_for_home(h):
        time.sleep(0.5)
    for pid in gateway_pids_for_home(h):
        try:
            os.kill(pid, signal.SIGKILL)
            log(f"KILL_STALE pid={pid} home={h}")
        except Exception as exc:
            log(f"KILL_FAIL pid={pid} home={h} error={exc}")
    subprocess.run(["tmux", "kill-session", "-t", f"={session}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if RESUME_SH.exists():
        res = subprocess.run(["bash", str(RESUME_SH)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        tail = " | ".join(res.stdout.splitlines()[-12:])
        log(f"RESUME_AFTER_RESTART rc={res.returncode} home={h} tail={tail}")
    else:
        log(f"RESUME_SCRIPT_MISSING path={RESUME_SH}")
    return True


def main():
    last_restart = {}
    log("WATCHDOG_STARTED")
    while True:
        try:
            changed = False
            for h in discover_homes():
                pids = gateway_pids_for_home(h)
                if len(pids) == 0:
                    if time.time() - last_restart.get(str(h), 0) >= COOLDOWN:
                        log(f"MISSING_GATEWAY home={h}")
                        subprocess.run(["bash", str(RESUME_SH)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
                        last_restart[str(h)] = time.time()
                        changed = True
                    continue
                if len(pids) > 1:
                    log(f"DUPLICATE_GATEWAYS home={h} pids={pids} action=defer_to_resume_guard")
                    continue
                age, active, reason = heartbeat_age_seconds(h)
                if age > MAX_HEARTBEAT_AGE:
                    if active > 0:
                        log(f"STALE_POLLING_ACTIVE_WORK home={h} age={age} active={active} action=preserve")
                    elif time.time() - last_restart.get(str(h), 0) >= COOLDOWN:
                        restarted = exact_restart_home(h, f"polling_heartbeat_stale:{age}:{reason}")
                        last_restart[str(h)] = time.time()
                        changed = changed or restarted
            if changed:
                subprocess.run(["bash", str(RESUME_SH)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        except Exception as exc:
            log(f"WATCHDOG_LOOP_ERROR {type(exc).__name__}: {exc}")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
