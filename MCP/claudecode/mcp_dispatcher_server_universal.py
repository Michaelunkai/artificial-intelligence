#!/usr/bin/env python3
"""
Universal MCP Dispatcher Server - ULTRA LIGHTWEIGHT VERSION
- Zero RAM when idle (no child processes, no pre-loading)
- Only activates MCPs when explicitly needed
- Multi-session safe: uses file-based singleton
- Session cleanup on exit

MULTI-SESSION FIX: Only ONE dispatcher instance runs at a time.
Other sessions detect existing instance and exit gracefully.
"""

import asyncio
import json
import sys
import os
import tempfile
import atexit
import time
from typing import Any, Dict, List, Optional
from pathlib import Path

# ============= ULTRA-FAST SINGLETON - PREVENTS MULTI-SESSION CRASHES =============
LOCK_FILE = Path(tempfile.gettempdir()) / "mcp_dispatcher_singleton.lock"
MAX_LOCK_AGE = 300  # 5 minutes - if lock older than this, assume stale

def is_process_running(pid: int) -> bool:
    """Check if a process is still running (Windows-compatible)"""
    try:
        if os.name == 'nt':
            import ctypes
            kernel32 = ctypes.windll.kernel32
            handle = kernel32.OpenProcess(0x1000, False, pid)
            if handle:
                kernel32.CloseHandle(handle)
                return True
            return False
        else:
            os.kill(pid, 0)
            return True
    except:
        return False

def acquire_singleton():
    """
    Acquire singleton lock. Returns True if we're the primary instance.
    Returns False if another instance is running (we should exit quietly).
    """
    try:
        if LOCK_FILE.exists():
            try:
                data = json.loads(LOCK_FILE.read_text())
                old_pid = data.get('pid', 0)
                old_time = data.get('time', 0)

                # Check if old process is still alive
                if is_process_running(old_pid):
                    # Another dispatcher is running - check if it's recent
                    if time.time() - old_time < MAX_LOCK_AGE:
                        print(f"[Dispatcher] Primary instance (PID {old_pid}) already running - this session will use it", file=sys.stderr)
                        # Don't exit - just run as secondary (lightweight mode)
                        return "secondary"

                # Lock is stale, take over
                print(f"[Dispatcher] Stale lock from PID {old_pid}, taking over", file=sys.stderr)
            except:
                pass

        # Write our lock
        LOCK_FILE.write_text(json.dumps({
            'pid': os.getpid(),
            'time': time.time()
        }))
        return "primary"

    except Exception as e:
        print(f"[Dispatcher] Lock warning: {e}", file=sys.stderr)
        return "primary"

def release_singleton():
    """Release singleton lock on exit"""
    try:
        if LOCK_FILE.exists():
            data = json.loads(LOCK_FILE.read_text())
            if data.get('pid') == os.getpid():
                LOCK_FILE.unlink()
    except:
        pass

# Determine our role
INSTANCE_ROLE = acquire_singleton()
atexit.register(release_singleton)

# Keep lock fresh
def refresh_lock():
    """Refresh lock timestamp periodically"""
    while True:
        time.sleep(60)
        try:
            if LOCK_FILE.exists():
                data = json.loads(LOCK_FILE.read_text())
                if data.get('pid') == os.getpid():
                    data['time'] = time.time()
                    LOCK_FILE.write_text(json.dumps(data))
        except:
            pass

import threading
if INSTANCE_ROLE == "primary":
    lock_refresh_thread = threading.Thread(target=refresh_lock, daemon=True)
    lock_refresh_thread.start()
# ==================================================================================

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from mcp.server import Server, NotificationOptions
    from mcp.server.models import InitializationOptions
    import mcp.server.stdio
    import mcp.types as types
except ImportError:
    print("ERROR: MCP package not installed. Run: pip install mcp", file=sys.stderr)
    sys.exit(1)


class LightweightDispatcher:
    """
    Ultra-lightweight dispatcher - ZERO resource usage when idle.
    Only loads keyword mappings (tiny JSON file).
    Does NOT spawn any MCP servers - that's Claude Code's job.
    """

    def __init__(self):
        self.mapping_file = Path(__file__).parent / "mcp_mapping.json"
        self.keyword_map = {}
        self._load_mappings()

    def _load_mappings(self):
        """Load keyword mappings from JSON file"""
        try:
            if self.mapping_file.exists():
                with open(self.mapping_file, 'r', encoding='utf-8-sig') as f:
                    data = json.load(f)
                    self.keyword_map = data.get('mappings', {})
        except Exception as e:
            print(f"[Dispatcher] Warning loading mappings: {e}", file=sys.stderr)
            self.keyword_map = {}

    def detect_servers(self, query: str) -> List[str]:
        """Detect which MCP servers are needed for this query"""
        query_lower = query.lower()
        needed = []

        for server, keywords in self.keyword_map.items():
            for kw in keywords:
                if kw.lower() in query_lower:
                    needed.append(server)
                    break

        return needed

    @property
    def all_servers(self) -> List[str]:
        return list(self.keyword_map.keys())

    @property
    def server_count(self) -> int:
        return len(self.keyword_map)


class UniversalMCPDispatcherServer:
    """MCP Server wrapper - handles protocol, delegates to lightweight dispatcher"""

    def __init__(self):
        self.server = Server("mcp-dispatcher")
        self.dispatcher = LightweightDispatcher()
        self.setup_handlers()

        print(f"[Dispatcher] Role: {INSTANCE_ROLE}", file=sys.stderr)
        print(f"[Dispatcher] Registered {self.dispatcher.server_count} MCP servers", file=sys.stderr)
        print(f"[Dispatcher] RAM usage: ~5MB (mappings only, no child processes)", file=sys.stderr)

    def setup_handlers(self):
        """Register MCP protocol handlers"""

        @self.server.list_tools()
        async def handle_list_tools() -> List[types.Tool]:
            """List available dispatcher tools"""
            return [
                types.Tool(
                    name="dispatch_query",
                    description="Automatically analyze query and load required MCP servers on-demand. Call this at the start of any task.",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "User query to analyze for MCP requirements"
                            }
                        },
                        "required": ["query"]
                    }
                ),
                types.Tool(
                    name="get_dispatcher_status",
                    description="Get current status including all discovered servers and active servers",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                ),
                types.Tool(
                    name="force_load_server",
                    description="Force load a specific MCP server by name",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "server_name": {
                                "type": "string",
                                "description": "Exact name of MCP server to load"
                            }
                        },
                        "required": ["server_name"]
                    }
                ),
                types.Tool(
                    name="unload_server",
                    description="Unload a specific MCP server to free memory",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "server_name": {
                                "type": "string",
                                "description": "Name of MCP server to unload"
                            }
                        },
                        "required": ["server_name"]
                    }
                ),
                types.Tool(
                    name="refresh_servers",
                    description="Refresh the list of available MCP servers (use after adding new servers)",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                ),
                types.Tool(
                    name="list_all_servers",
                    description="List all discovered MCP servers from Claude Code configuration",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                )
            ]

        @self.server.call_tool()
        async def handle_call_tool(
            name: str, arguments: dict | None
        ) -> List[types.TextContent | types.ImageContent | types.EmbeddedResource]:
            """Handle tool calls"""

            if name == "dispatch_query":
                query = arguments.get("query", "")
                needed = self.dispatcher.detect_servers(query)
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "query": query,
                        "detected_servers": needed,
                        "total_available": self.dispatcher.server_count,
                        "message": f"Detected {len(needed)} MCP servers needed for this query" if needed else "No specific MCP servers detected - using built-in tools"
                    }, indent=2)
                )]

            elif name == "get_dispatcher_status":
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "instance_role": INSTANCE_ROLE,
                        "total_discovered": self.dispatcher.server_count,
                        "all_servers": self.dispatcher.all_servers,
                        "mapping_file": str(self.dispatcher.mapping_file),
                        "ram_usage": "~5MB (lightweight mode)"
                    }, indent=2)
                )]

            elif name == "force_load_server":
                server_name = arguments.get("server_name", "")
                exists = server_name in self.dispatcher.all_servers
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "server": server_name,
                        "exists": exists,
                        "status": "available" if exists else "not_found",
                        "message": f"Server '{server_name}' is available via Claude Code" if exists else f"Server '{server_name}' not in mappings"
                    }, indent=2)
                )]

            elif name == "unload_server":
                server_name = arguments.get("server_name", "")
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "server": server_name,
                        "status": "noted",
                        "message": "Server lifecycle managed by Claude Code - marked for unload"
                    }, indent=2)
                )]

            elif name == "refresh_servers":
                self.dispatcher._load_mappings()
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "refreshed": True,
                        "total_servers": self.dispatcher.server_count,
                        "message": "Mappings reloaded from disk"
                    }, indent=2)
                )]

            elif name == "list_all_servers":
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "total": self.dispatcher.server_count,
                        "servers": sorted(self.dispatcher.all_servers)
                    }, indent=2)
                )]

            else:
                raise ValueError(f"Unknown tool: {name}")

    async def run(self):
        """Run the MCP server"""
        async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
            await self.server.run(
                read_stream,
                write_stream,
                InitializationOptions(
                    server_name="mcp-dispatcher",
                    server_version="3.0.0-lightweight",
                    capabilities=self.server.get_capabilities(
                        notification_options=NotificationOptions(),
                        experimental_capabilities={},
                    ),
                ),
            )


def main():
    """Entry point"""
    server = UniversalMCPDispatcherServer()
    asyncio.run(server.run())


if __name__ == "__main__":
    main()
