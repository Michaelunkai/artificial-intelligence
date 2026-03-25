#!/usr/bin/env python3
"""
MCP Dispatcher Server - Acts as an MCP server that dynamically loads other MCPs on-demand.
This is the intelligent proxy that Claude Code connects to instead of all MCPs at startup.
"""

import asyncio
import json
import sys
import subprocess
from typing import Any, Dict, List, Optional
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types

# Import the dispatcher
from mcp_dispatcher import MCPDispatcher

class MCPDispatcherServer:
    def __init__(self):
        self.server = Server("mcp-dispatcher")
        self.dispatcher = MCPDispatcher(
            mapping_file="F:/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/MCP/claudecode/mcp_mapping.json",
            idle_timeout=300  # 5 minutes idle timeout
        )

        # Register handlers
        self.setup_handlers()

    def setup_handlers(self):
        """Register MCP protocol handlers"""

        @self.server.list_tools()
        async def handle_list_tools() -> List[types.Tool]:
            """List available dispatcher tools"""
            return [
                types.Tool(
                    name="dispatch_query",
                    description="Analyze user query and dynamically load required MCP servers. Use this before any MCP operation.",
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
                    description="Get current status of the MCP dispatcher including active servers",
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
                                "description": "Name of MCP server to load"
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
                )
            ]

        @self.server.call_tool()
        async def handle_call_tool(
            name: str, arguments: dict | None
        ) -> List[types.TextContent | types.ImageContent | types.EmbeddedResource]:
            """Handle tool calls"""

            if name == "dispatch_query":
                query = arguments.get("query", "")
                result = self.dispatcher.dispatch(query)
                return [types.TextContent(
                    type="text",
                    text=json.dumps(result, indent=2)
                )]

            elif name == "get_dispatcher_status":
                status = self.dispatcher.get_status()
                return [types.TextContent(
                    type="text",
                    text=json.dumps(status, indent=2)
                )]

            elif name == "force_load_server":
                server_name = arguments.get("server_name", "")
                success = self.dispatcher.start_server(server_name)
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "server": server_name,
                        "loaded": success,
                        "status": "success" if success else "failed"
                    }, indent=2)
                )]

            elif name == "unload_server":
                server_name = arguments.get("server_name", "")
                self.dispatcher.stop_server(server_name)
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "server": server_name,
                        "status": "unloaded"
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
                    server_version="1.0.0",
                    capabilities=self.server.get_capabilities(
                        notification_options=NotificationOptions(),
                        experimental_capabilities={},
                    ),
                ),
            )

def main():
    """Entry point"""
    server = MCPDispatcherServer()
    asyncio.run(server.run())

if __name__ == "__main__":
    main()
