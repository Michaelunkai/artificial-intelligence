"""
Nuke F:\\backup\\claudecode — instant rename + background purge.

Strategy:
  1. Rename claudecode -> __nuke_<timestamp>__ (instant — 5ms, just MFT metadata)
  2. Recreate empty claudecode (instant — ready for new backups NOW)
  3. Fire robocopy /PURGE /MT:128 as a detached background process
  4. Return immediately — user doesn't wait for IO

The backup path is free in <10ms. Actual deletion happens silently in background.
Previous __nuke__ dirs are also cleaned up in the same background sweep.
"""

import subprocess
import os
import sys
import time
from pathlib import Path

BACKUP_ROOT = Path(r"F:\backup\claudecode")
NUKE_BASE = Path(r"F:\backup")
EMPTY_DIR = Path(r"F:\backup\__empty__")


def main() -> None:
    # If called with --purge, we're the background worker
    if len(sys.argv) > 1 and sys.argv[1] == "--purge":
        _background_purge()
        return

    print(f"\nNuking {BACKUP_ROOT} ...")

    if not BACKUP_ROOT.exists():
        print("Nothing to nuke.")
        _launch_background_cleanup()
        return

    entries = list(BACKUP_ROOT.iterdir())
    if not entries:
        print("Already empty.")
        _launch_background_cleanup()
        return

    count = len(entries)
    start = time.perf_counter()

    # Step 1: Atomic rename (instant — just MFT metadata update)
    nuke_name = f"__nuke_{int(time.time())}__"
    nuke_dir = NUKE_BASE / nuke_name
    print(f"  [1/3] Rename -> {nuke_name} ...", end=" ", flush=True)
    t = time.perf_counter()
    BACKUP_ROOT.rename(nuke_dir)
    print(f"({(time.perf_counter() - t) * 1000:.0f}ms)")

    # Step 2: Recreate empty backup root
    print("  [2/3] Recreate empty backup root ...", end=" ", flush=True)
    t = time.perf_counter()
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    print(f"({(time.perf_counter() - t) * 1000:.0f}ms)")

    # Step 3: Launch background purge (detached — doesn't block caller)
    print("  [3/3] Background purge launched (robocopy /MT:128) ...", end=" ", flush=True)
    t = time.perf_counter()
    _launch_background_cleanup()
    print(f"({(time.perf_counter() - t) * 1000:.0f}ms)")

    elapsed = time.perf_counter() - start
    print(f"\n  DONE: {count} items freed in {elapsed * 1000:.0f}ms")
    print(f"  Background cleanup running — disk space reclaimed async.\n")


def _launch_background_cleanup() -> None:
    """Fire detached background process to purge all __nuke_*__ dirs."""
    script = str(Path(__file__).resolve())
    # CREATE_NO_WINDOW + DETACHED_PROCESS = fully background, no console
    CREATE_NO_WINDOW = 0x08000000
    DETACHED_PROCESS = 0x00000008
    subprocess.Popen(
        [sys.executable, script, "--purge"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        creationflags=CREATE_NO_WINDOW | DETACHED_PROCESS,
        close_fds=True,
    )


def _background_purge() -> None:
    """Background worker: find and destroy all __nuke_*__ dirs."""
    nuke_dirs = sorted(NUKE_BASE.glob("__nuke_*__"))
    if not nuke_dirs:
        return

    EMPTY_DIR.mkdir(exist_ok=True)
    try:
        for nd in nuke_dirs:
            if nd.is_dir():
                subprocess.run(
                    [
                        "robocopy", str(EMPTY_DIR), str(nd),
                        "/MIR", "/NFL", "/NDL", "/NJH", "/NJS",
                        "/nc", "/ns", "/np", "/R:0", "/W:0", "/MT:128",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=900,
                )
                try:
                    nd.rmdir()
                except OSError:
                    pass
    finally:
        if EMPTY_DIR.exists():
            try:
                EMPTY_DIR.rmdir()
            except OSError:
                pass


if __name__ == "__main__":
    main()
