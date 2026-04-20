"""
Nuke F:\\backup\\claudecode — DELETE ALL FIRST, then exit.

Strategy:
  1. Delete ALL contents of claudecode/ using robocopy /MIR (handles locks, long paths)
  2. Also clean up any stale __nuke_*__ dirs from previous failed runs
  3. Only exits after everything is fully deleted — synchronous, no background tricks
  4. Backup script can safely run after this completes
"""

import subprocess
import sys
import time
from pathlib import Path

BACKUP_ROOT = Path(r"F:\backup\claudecode")
NUKE_BASE = Path(r"F:\backup")
EMPTY_DIR = Path(r"F:\backup\__empty__")


def main() -> None:
    print(f"\nNuking {BACKUP_ROOT} ...")

    # Step 0: Clean up any stale __nuke_*__ dirs from previous failed runs
    stale = sorted(NUKE_BASE.glob("__nuke_*__"))
    if stale:
        print(f"  [0] Cleaning {len(stale)} stale __nuke__ dirs ...", flush=True)
        _purge_dirs(stale)

    if not BACKUP_ROOT.exists():
        print("  Nothing to nuke — directory doesn't exist.")
        BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
        print("  Created empty backup root. Ready.\n")
        return

    entries = list(BACKUP_ROOT.iterdir())
    if not entries:
        print("  Already empty. Ready.\n")
        return

    count = len(entries)
    start = time.perf_counter()

    # Step 1: Wipe all contents using robocopy /MIR (robust against locks, long paths)
    print(f"  [1/2] Deleting {count} items with robocopy /MIR /MT:128 ...", flush=True)
    EMPTY_DIR.mkdir(exist_ok=True)
    try:
        result = subprocess.run(
            [
                "robocopy", str(EMPTY_DIR), str(BACKUP_ROOT),
                "/MIR", "/NFL", "/NDL", "/NJH", "/NJS",
                "/nc", "/ns", "/np", "/R:1", "/W:1", "/MT:128",
            ],
            capture_output=True,
            text=True,
            timeout=600,
        )
        # robocopy exit codes 0-7 are success/info, 8+ are errors
        if result.returncode >= 8:
            print(f"  WARNING: robocopy returned {result.returncode}")
            if result.stderr.strip():
                print(f"  stderr: {result.stderr.strip()[:200]}")
    except subprocess.TimeoutExpired:
        print("  WARNING: robocopy timed out after 10 minutes")
    finally:
        if EMPTY_DIR.exists():
            try:
                EMPTY_DIR.rmdir()
            except OSError:
                pass

    # Step 2: Verify deletion
    remaining = list(BACKUP_ROOT.iterdir())
    elapsed = time.perf_counter() - start

    if not remaining:
        print(f"  [2/2] Verified: all {count} items deleted ({elapsed:.1f}s)")
        print(f"\n  DONE. Backup root is empty and ready.\n")
    else:
        print(f"  [2/2] WARNING: {len(remaining)} items still remain after {elapsed:.1f}s")
        for r in remaining[:10]:
            print(f"    - {r.name}")
        if len(remaining) > 10:
            print(f"    ... and {len(remaining) - 10} more")
        print(f"\n  Partial cleanup. Some files may be locked by another process.\n")


def _purge_dirs(dirs: list[Path]) -> None:
    """Synchronously delete a list of directories using robocopy /MIR."""
    EMPTY_DIR.mkdir(exist_ok=True)
    try:
        for d in dirs:
            if d.is_dir():
                print(f"    Purging {d.name} ...", end=" ", flush=True)
                t = time.perf_counter()
                subprocess.run(
                    [
                        "robocopy", str(EMPTY_DIR), str(d),
                        "/MIR", "/NFL", "/NDL", "/NJH", "/NJS",
                        "/nc", "/ns", "/np", "/R:1", "/W:1", "/MT:128",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=300,
                )
                try:
                    d.rmdir()
                    print(f"OK ({(time.perf_counter() - t):.1f}s)")
                except OSError:
                    print(f"rmdir failed ({(time.perf_counter() - t):.1f}s)")
    finally:
        if EMPTY_DIR.exists():
            try:
                EMPTY_DIR.rmdir()
            except OSError:
                pass


if __name__ == "__main__":
    main()
