"""
FASTEST folder purge using robocopy mirror trick
Robocopy /MIR with empty source = fastest Windows delete
"""
import subprocess
import os
import time
import tempfile
import sys

def empty_folder(folder_path):
    if not os.path.exists(folder_path):
        print(f"Folder doesn't exist: {folder_path}", flush=True)
        return False
    
    print(f"Emptying: {folder_path}", flush=True)
    start = time.time()
    
    items = os.listdir(folder_path)
    if not items:
        print("Folder already empty!", flush=True)
        return True
    
    print(f"Found {len(items)} items", flush=True)
    
    # Create empty temp folder
    empty_dir = os.path.join(tempfile.gettempdir(), 'empty_purge_temp')
    os.makedirs(empty_dir, exist_ok=True)
    
    # For each subfolder, run robocopy /MIR in parallel
    processes = []
    for item in items:
        item_path = os.path.join(folder_path, item)
        if os.path.isdir(item_path):
            # Robocopy mirror empty folder = delete all contents
            p = subprocess.Popen(
                f'robocopy "{empty_dir}" "{item_path}" /MIR /NFL /NDL /NJH /NJS /NC /NS /NP',
                shell=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            processes.append((p, item_path, 'dir'))
        else:
            p = subprocess.Popen(
                f'del /f /q "{item_path}"',
                shell=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            processes.append((p, item_path, 'file'))
    
    print(f"Launched {len(processes)} parallel robocopy processes", flush=True)
    
    # Wait for all
    for p, path, ptype in processes:
        p.wait()
        # For directories, remove the now-empty folder
        if ptype == 'dir' and os.path.exists(path):
            try:
                os.rmdir(path)
            except:
                subprocess.run(f'rd /q "{path}"', shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Cleanup temp
    try:
        os.rmdir(empty_dir)
    except:
        pass
    
    elapsed = time.time() - start
    
    # Verify
    remaining = os.listdir(folder_path)
    if remaining:
        print(f"WARNING: {len(remaining)} items remain after {elapsed:.2f}s", flush=True)
        return False
    else:
        print(f"DONE - Emptied in {elapsed:.2f} seconds", flush=True)
        return True

if __name__ == "__main__":
    target = r"F:\backup\claudecode"
    success = empty_folder(target)
    sys.exit(0 if success else 1)
