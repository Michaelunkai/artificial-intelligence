#!/usr/bin/env python3
import json
import os
import tempfile
import time
from pathlib import Path


ACTIVE = Path("/root/.local/share/llama-agent/active-task.json")
HISTORY = Path("/root/.local/share/llama-agent/tasks")
BACKUP = Path(
    "/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/"
    "LocalAI/wsl2/.agents/backups"
)
EXPECTED_TASK_ID = "20260813-211118-0b97a3f3"


raw = ACTIVE.read_bytes()
data = json.loads(raw)
if (
    data.get("task_id") != EXPECTED_TASK_ID
    or data.get("status") not in {"running", "recovering", "interrupted"}
):
    raise SystemExit(
        "Refusing to supersede unexpected active task "
        f"{data.get('task_id')!r} with status {data.get('status')!r}."
    )

stamp = time.strftime("%Y%m%d-%H%M%S%z")
BACKUP.mkdir(parents=True, exist_ok=True)
backup_path = BACKUP / (
    f"active-task-{EXPECTED_TASK_ID}.before-supersede-{stamp}.json"
)
backup_path.write_bytes(raw)

data["status"] = "cancelled"
data["cancelled_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
data["cancellation_reason"] = (
    "Superseded by the user-approved corrected request for exactly 100 files."
)

HISTORY.mkdir(parents=True, exist_ok=True)
target = HISTORY / f"{EXPECTED_TASK_ID}.json"
descriptor, temporary_name = tempfile.mkstemp(
    prefix=target.name + ".", dir=str(HISTORY)
)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary_name, target)
finally:
    if os.path.exists(temporary_name):
        os.unlink(temporary_name)

verified = json.loads(target.read_text(encoding="utf-8"))
if (
    verified.get("task_id") != EXPECTED_TASK_ID
    or verified.get("status") != "cancelled"
):
    raise SystemExit("The preserved history record failed verification.")
if ACTIVE.read_bytes() != raw:
    raise SystemExit("The active checkpoint changed during preservation.")

ACTIVE.unlink()
print(f"PRESERVED_BACKUP={backup_path}")
print(f"PRESERVED_HISTORY={target}")
print(f"STATUS={verified['status']}")
print(f"ACTIVE_EXISTS={ACTIVE.exists()}")
