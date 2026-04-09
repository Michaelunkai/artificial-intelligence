"""Tool executor - 9 async tools for the oll90 agent"""
import asyncio
import os
import re
import subprocess
import uuid
import tempfile
import time
import glob as glob_mod
import html
from pathlib import Path
from typing import Optional

from config import TOOL_TIMEOUT_SECONDS, MAX_OUTPUT_CHARS
from models import ToolResult


def _get_temp_dir() -> str:
    """Get temp directory, preferring C:\\Temp for Windows."""
    t = "C:\\Temp"
    if os.path.isdir(t):
        return t
    return tempfile.gettempdir()


def _run_powershell_sync(command: str) -> ToolResult:
    """Synchronous PowerShell execution via temp .ps1 file (runs in thread)."""
    start = time.time()
    temp_dir = _get_temp_dir()
    script_path = os.path.join(temp_dir, f"oll90_{uuid.uuid4().hex[:8]}.ps1")

    try:
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(command)

        proc = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-File", script_path],
            capture_output=True, timeout=TOOL_TIMEOUT_SECONDS,
            creationflags=0x08000000  # CREATE_NO_WINDOW
        )

        stdout = proc.stdout.decode('utf-8', errors='replace') if proc.stdout else ""
        stderr = proc.stderr.decode('utf-8', errors='replace') if proc.stderr else ""

        if len(stdout) > MAX_OUTPUT_CHARS:
            stdout = stdout[:MAX_OUTPUT_CHARS] + f"\n... [TRUNCATED at {MAX_OUTPUT_CHARS} chars]"

        return ToolResult(
            output=stdout, stderr=stderr,
            success=(proc.returncode == 0 or not stderr.strip()),
            duration_ms=int((time.time() - start) * 1000)
        )
    except subprocess.TimeoutExpired:
        return ToolResult(
            output="[ERROR] Command timed out after {0}s".format(TOOL_TIMEOUT_SECONDS),
            stderr="Timeout", success=False,
            duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(
            output="", stderr=str(e), success=False,
            duration_ms=int((time.time() - start) * 1000)
        )
    finally:
        try:
            os.unlink(script_path)
        except OSError:
            pass


async def run_powershell(command: str) -> ToolResult:
    """Execute a PowerShell command via temp .ps1 file (thread-safe for any event loop)."""
    return await asyncio.to_thread(_run_powershell_sync, command)


def _run_cmd_sync(command: str) -> ToolResult:
    """Synchronous CMD execution (runs in thread)."""
    start = time.time()
    try:
        proc = subprocess.run(
            ["cmd.exe", "/c", command],
            capture_output=True, timeout=TOOL_TIMEOUT_SECONDS,
            creationflags=0x08000000
        )

        stdout = proc.stdout.decode('utf-8', errors='replace') if proc.stdout else ""
        stderr = proc.stderr.decode('utf-8', errors='replace') if proc.stderr else ""

        if len(stdout) > MAX_OUTPUT_CHARS:
            stdout = stdout[:MAX_OUTPUT_CHARS] + f"\n... [TRUNCATED]"

        return ToolResult(
            output=stdout, stderr=stderr,
            success=(proc.returncode == 0),
            duration_ms=int((time.time() - start) * 1000)
        )
    except subprocess.TimeoutExpired:
        return ToolResult(
            output="[ERROR] Command timed out after {0}s".format(TOOL_TIMEOUT_SECONDS),
            stderr="Timeout", success=False,
            duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def run_cmd(command: str) -> ToolResult:
    """Execute a CMD.exe command (thread-safe for any event loop)."""
    return await asyncio.to_thread(_run_cmd_sync, command)


async def write_file(path: str, content: str) -> ToolResult:
    """Write content to an absolute path with UTF-8 no BOM."""
    start = time.time()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(content)
        size = os.path.getsize(path)
        return ToolResult(
            output=f"File written: {path} ({size} bytes)",
            success=True,
            duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def read_file(path: str) -> ToolResult:
    """Read file content by absolute path."""
    start = time.time()
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        if len(content) > MAX_OUTPUT_CHARS:
            content = content[:MAX_OUTPUT_CHARS] + f"\n... [TRUNCATED at {MAX_OUTPUT_CHARS} chars]"
        return ToolResult(
            output=content, success=True,
            duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def edit_file(path: str, old_text: str, new_text: str) -> ToolResult:
    """Edit a file by replacing exact text."""
    start = time.time()
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        count = content.count(old_text)
        if count == 0:
            return ToolResult(
                output="", stderr="old_text not found in file",
                success=False, duration_ms=int((time.time() - start) * 1000)
            )
        if count > 1:
            return ToolResult(
                output="", stderr=f"old_text found {count} times (must be unique)",
                success=False, duration_ms=int((time.time() - start) * 1000)
            )

        new_content = content.replace(old_text, new_text, 1)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(new_content)

        return ToolResult(
            output=f"Edited {path}: replaced {len(old_text)} chars with {len(new_text)} chars",
            success=True, duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def list_directory(path: str, recursive: bool = False, pattern: str = "*") -> ToolResult:
    """List files and directories with sizes and dates."""
    start = time.time()
    try:
        p = Path(path)
        if not p.is_dir():
            return ToolResult(output="", stderr=f"Not a directory: {path}",
                              success=False, duration_ms=int((time.time() - start) * 1000))

        items = list(p.rglob(pattern) if recursive else p.glob(pattern))
        items = items[:500]  # Limit

        lines = []
        for item in sorted(items):
            try:
                stat = item.stat()
                kind = "D" if item.is_dir() else "F"
                size = stat.st_size if item.is_file() else 0
                # Format size
                if size > 1_073_741_824:
                    size_str = f"{size / 1_073_741_824:.1f} GB"
                elif size > 1_048_576:
                    size_str = f"{size / 1_048_576:.1f} MB"
                elif size > 1024:
                    size_str = f"{size / 1024:.1f} KB"
                else:
                    size_str = f"{size} B"

                from datetime import datetime
                mtime = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")
                lines.append(f"[{kind}] {size_str:>10s}  {mtime}  {item.name}")
            except (PermissionError, OSError):
                lines.append(f"[?]            ????-??-?? ??:??  {item.name}")

        output = f"Directory: {path}\n{len(lines)} items\n\n" + "\n".join(lines)
        return ToolResult(output=output, success=True,
                          duration_ms=int((time.time() - start) * 1000))
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def search_files(path: str, pattern: str, file_glob: str = "*.*") -> ToolResult:
    """Search file contents for a regex pattern."""
    start = time.time()
    try:
        p = Path(path)
        if not p.is_dir():
            return ToolResult(output="", stderr=f"Not a directory: {path}",
                              success=False, duration_ms=int((time.time() - start) * 1000))

        compiled = re.compile(pattern, re.IGNORECASE)
        matches = []
        files_searched = 0
        max_results = 50

        for file_path in p.rglob(file_glob):
            if not file_path.is_file():
                continue
            if file_path.stat().st_size > 1_048_576:  # Skip files > 1MB
                continue
            files_searched += 1

            try:
                with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                    for line_num, line in enumerate(f, 1):
                        if compiled.search(line):
                            matches.append(f"{file_path}:{line_num}: {line.rstrip()[:200]}")
                            if len(matches) >= max_results:
                                break
            except (PermissionError, OSError):
                continue

            if len(matches) >= max_results:
                break

        header = f"Searched {files_searched} files in {path}\n{len(matches)} matches for /{pattern}/\n\n"
        output = header + "\n".join(matches)
        return ToolResult(output=output, success=True,
                          duration_ms=int((time.time() - start) * 1000))
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


async def get_system_info() -> ToolResult:
    """Snapshot of CPU, RAM, GPU, disks, and OS info via PowerShell."""
    cmd = (
        "$os = Get-CimInstance Win32_OperatingSystem; "
        "$cpu = Get-CimInstance Win32_Processor; "
        "$gpu = try { nvidia-smi --query-gpu=name,memory.total,memory.used,temperature.gpu,utilization.gpu --format=csv,noheader 2>$null } catch { 'N/A' }; "
        "$disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | "
        "  Select-Object DeviceID,@{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB,1)}},@{N='TotalGB';E={[math]::Round($_.Size/1GB,1)}}; "
        "$ram_total = [math]::Round($os.TotalVisibleMemorySize/1MB, 1); "
        "$ram_free  = [math]::Round($os.FreePhysicalMemory/1MB, 1); "
        "Write-Output ('OS: ' + $os.Caption + ' Build ' + $os.BuildNumber); "
        "Write-Output ('CPU: ' + $cpu.Name + ' (' + $cpu.NumberOfLogicalProcessors + ' threads)'); "
        "Write-Output ('RAM: ' + ($ram_total - $ram_free) + ' GB used / ' + $ram_total + ' GB total'); "
        "Write-Output ('GPU: ' + $gpu); "
        "Write-Output ('Disks: ' + ($disks | ForEach-Object { $_.DeviceID + ' ' + $_.FreeGB + 'GB free / ' + $_.TotalGB + 'GB' } | Out-String).Trim())"
    )
    return await run_powershell(cmd)


async def web_fetch(url: str) -> ToolResult:
    """HTTP GET a URL and return text with HTML tags stripped (max 10K chars)."""
    start = time.time()
    try:
        import httpx
        async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:
            resp = await client.get(url, headers={"User-Agent": "oll90-agent/1.0"})
        text = resp.text
        # Strip HTML tags
        text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<script[^>]*>.*?</script>', '', text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<[^>]+>', '', text)
        text = html.unescape(text)
        text = re.sub(r'\n{3,}', '\n\n', text).strip()
        if len(text) > 10000:
            text = text[:10000] + "\n... [TRUNCATED at 10000 chars]"
        return ToolResult(
            output=f"URL: {url}\nStatus: {resp.status_code}\n\n{text}",
            success=(resp.status_code < 400),
            duration_ms=int((time.time() - start) * 1000)
        )
    except Exception as e:
        return ToolResult(output="", stderr=str(e), success=False,
                          duration_ms=int((time.time() - start) * 1000))


# Tool dispatch map
TOOL_MAP = {
    "run_powershell": run_powershell,
    "run_cmd": run_cmd,
    "write_file": write_file,
    "read_file": read_file,
    "edit_file": edit_file,
    "list_directory": list_directory,
    "search_files": search_files,
    "get_system_info": get_system_info,
    "web_fetch": web_fetch,
}


async def execute_tool(name: str, args: dict) -> ToolResult:
    """Dispatch a tool call by name."""
    func = TOOL_MAP.get(name)
    if not func:
        return ToolResult(output="", stderr=f"Unknown tool: {name}", success=False)

    try:
        return await func(**args)
    except TypeError as e:
        return ToolResult(output="", stderr=f"Invalid arguments for {name}: {e}", success=False)
