"""WebSocket endpoint - full agent loop with streaming"""
import asyncio
import json
import time
from datetime import datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from config import OLLAMA_MODEL, OLLAMA_URL, MAX_TOOL_ITERATIONS, TOOLS
from db import db
from engine.ollama_client import stream_chat, OllamaStreamResponse
from engine.tool_executor import execute_tool
from engine.intelligence import AgentIntelligence
from engine.context_manager import ContextManager

router = APIRouter()

# System prompt for the agent
SYSTEM_PROMPT = """You are OLL90, an autonomous AI agent running on Windows 11 Pro with an RTX 5080 16GB GPU.
You execute real PowerShell commands and system operations. NEVER suggest commands for the user to run - DO it yourself using tools.

RULES:
1. Call tools IMMEDIATELY - never explain what you would do, just DO it.
2. Chain PowerShell commands with semicolons (;), NEVER use &&.
3. Use absolute Windows paths (C:\\, F:\\).
4. NEVER prepend .\\ to absolute paths.
5. Query system info with tools - never guess values.
6. Summarize results with actual numbers, paths, and values.
7. If a command fails, try a DIFFERENT approach.
8. Use full cmdlet names (Get-ChildItem not ls, Get-Process not ps).
9. CRITICAL: Never bare $variable in double-quoted strings. Use: 'text ' + $var or "text $($var)".
10. Prefer single-quoted strings for literals.
11. Use try/catch for individual operations, -ErrorAction SilentlyContinue for Get-* cmdlets.
12. Scripts must produce measurable output (counts, sizes, lists).
13. On parse error: identify the exact syntax issue, fix ONLY that, retry.
14. Same error 2x: STOP and change approach completely.
15. Verify file operations with Get-ChildItem or Test-Path.
16. Registry paths use PS drive syntax: HKLM:\\, not HKLM\\.
17. ALWAYS add -ErrorAction SilentlyContinue to Get-Process, Get-Service, Get-NetAdapter, Get-ItemProperty.
18. Present results in TEXT RESPONSE, not in files, unless user says "save to file".
19. Get-CimInstance takes ONE class name only. Query each class separately."""


async def send_event(ws: WebSocket, event: dict):
    """Send a JSON event to the WebSocket client."""
    try:
        await ws.send_json(event)
    except Exception:
        pass


async def handle_user_message(ws: WebSocket, session_id: str, user_text: str):
    """Run the full agent loop for a user message."""
    task_start = time.time()

    # Load conversation history from DB
    db_messages = await db.get_messages(session_id)
    messages = []

    # Add system prompt
    messages.append({"role": "system", "content": SYSTEM_PROMPT})

    # Rebuild from DB
    for m in db_messages:
        msg = {"role": m["role"], "content": m["content"]}
        if m.get("tool_calls_json"):
            try:
                msg["tool_calls"] = json.loads(m["tool_calls_json"])
            except json.JSONDecodeError:
                pass
        messages.append(msg)

    # Add new user message
    messages.append({"role": "user", "content": user_text})
    await db.append_message(session_id, "user", user_text)

    # Create intelligence and context manager for this turn
    intel = AgentIntelligence(user_text)
    ctx_mgr = ContextManager()
    cancel_event = asyncio.Event()

    total_tool_calls = 0
    error_count = 0

    for iteration in range(1, MAX_TOOL_ITERATIONS + 1):
        elapsed = time.time() - task_start
        elapsed_str = f"{int(elapsed // 60):02d}:{int(elapsed % 60):02d}"

        # Send step status
        await send_event(ws, {
            "type": "status",
            "step": iteration,
            "max_steps": MAX_TOOL_ITERATIONS,
            "elapsed": elapsed_str,
            "tokens": ctx_mgr.get_usage_str()
        })

        # Check context compaction
        if ctx_mgr.needs_compaction(messages):
            messages = ctx_mgr.compact(messages)
            await send_event(ws, {"type": "info", "message": "Context compacted to fit window"})

        # Token streaming callbacks
        accumulated_content = []

        async def on_token(content: str, state: str):
            accumulated_content.append(content)
            await send_event(ws, {
                "type": "token",
                "content": content,
                "thinking": state == "thinking"
            })

        async def on_thinking_start():
            await send_event(ws, {"type": "thinking_start"})

        async def on_thinking_end(token_count: int):
            await send_event(ws, {"type": "thinking_end", "token_count": token_count})

        # Call Ollama streaming
        try:
            response = await stream_chat(
                messages=messages,
                tools=TOOLS,
                on_token=on_token,
                on_thinking_start=on_thinking_start,
                on_thinking_end=on_thinking_end,
                cancel_event=cancel_event,
                model=OLLAMA_MODEL,
                url=OLLAMA_URL,
            )
        except Exception as e:
            await send_event(ws, {"type": "error", "message": f"Ollama error: {str(e)}"})
            break

        # Update token stats
        ctx_mgr.update_from_response(response.prompt_eval_count, response.eval_count)

        # Case 1: Tool calls
        if response.tool_calls:
            # Add assistant message with tool calls to history
            assistant_msg = {"role": "assistant", "content": response.content, "tool_calls": response.tool_calls}
            messages.append(assistant_msg)
            await db.append_message(session_id, "assistant", response.content, response.tool_calls)

            for tc in response.tool_calls:
                func = tc.get("function", {})
                tool_name = func.get("name", "unknown")
                tool_args = func.get("arguments", {})
                if isinstance(tool_args, str):
                    try:
                        tool_args = json.loads(tool_args)
                    except json.JSONDecodeError:
                        tool_args = {"command": tool_args}

                intel.turn_tool_calls += 1
                total_tool_calls += 1

                # Send tool call start
                await send_event(ws, {
                    "type": "tool_call_start",
                    "tool": tool_name,
                    "args": tool_args,
                    "call_id": total_tool_calls
                })

                # Check write_file interceptor
                if tool_name == "write_file" and "path" in tool_args and "content" in tool_args:
                    path = intel.sanitize_path(tool_args["path"])
                    tool_args["path"] = path
                    blocked = intel.check_write_interceptor(path, tool_args.get("content", ""))
                    if blocked:
                        await send_event(ws, {
                            "type": "tool_call_result",
                            "tool": tool_name,
                            "result": blocked,
                            "success": False,
                            "blocked": True,
                            "duration_ms": 0,
                            "call_id": total_tool_calls
                        })
                        messages.append({"role": "tool", "content": blocked})
                        await db.append_message(session_id, "tool", blocked)
                        continue

                # Sanitize paths
                if tool_name in ("read_file", "write_file", "edit_file") and "path" in tool_args:
                    tool_args["path"] = intel.sanitize_path(tool_args["path"])

                # Execute tool
                result = await execute_tool(tool_name, tool_args)

                # Process through intelligence
                processed_result, loop_msg = intel.process_tool_result(
                    tool_name, result.output, result.stderr
                )

                hint = intel.analyze_stderr(result.stderr) if result.stderr else None
                if result.stderr and result.stderr.strip():
                    error_count += 1

                # Send tool result
                await send_event(ws, {
                    "type": "tool_call_result",
                    "tool": tool_name,
                    "result": result.output[:2000],  # Preview
                    "stderr": result.stderr[:1000] if result.stderr else "",
                    "success": result.success,
                    "hint": hint,
                    "duration_ms": result.duration_ms,
                    "output_chars": len(result.output),
                    "call_id": total_tool_calls
                })

                # Add tool result to messages
                messages.append({"role": "tool", "content": processed_result})
                await db.append_message(session_id, "tool", processed_result)

                # Handle loop detection
                if loop_msg:
                    await send_event(ws, {
                        "type": "loop_detected",
                        "error_signature": intel.recent_errors[-1] if intel.recent_errors else "",
                        "count": 3
                    })
                    messages.append({"role": "system", "content": loop_msg})
                    await db.append_message(session_id, "system", loop_msg)

            continue  # Next iteration

        # Case 2: Text response (no tool calls)
        full_content = response.content

        # Strip think tags to check for visible content
        import re as _re
        visible_content = _re.sub(r'<think>[\s\S]*?</think>', '', full_content).strip()

        # If tools ran but response has no visible text, re-prompt for summary
        if total_tool_calls > 0 and not visible_content and not getattr(intel, '_summary_reprompted', False):
            intel._summary_reprompted = True
            summary_msg = "[AGENT] You executed tools but provided no text summary. Present the results to the user with actual numbers, paths, and values from the tool output."
            if full_content:
                messages.append({"role": "assistant", "content": full_content})
                await db.append_message(session_id, "assistant", full_content)
            messages.append({"role": "user", "content": summary_msg})
            await db.append_message(session_id, "user", summary_msg)
            await send_event(ws, {"type": "reprompt", "reason": "empty_response", "message": summary_msg})
            continue

        # Add to history
        messages.append({"role": "assistant", "content": full_content})
        await db.append_message(session_id, "assistant", full_content)

        # Check thinking-only
        thinking_msg = intel.check_thinking_only(full_content)
        if thinking_msg:
            messages.append({"role": "user", "content": thinking_msg})
            await db.append_message(session_id, "user", thinking_msg)
            await send_event(ws, {"type": "reprompt", "reason": "thinking_only", "message": thinking_msg})
            continue

        # Check shallow scan
        shallow_msg = intel.check_shallow_scan(intel.turn_tool_calls)
        if shallow_msg:
            messages.append({"role": "user", "content": shallow_msg})
            await db.append_message(session_id, "user", shallow_msg)
            await send_event(ws, {"type": "reprompt", "reason": "shallow_scan", "message": shallow_msg})
            continue

        # Final response - done
        elapsed = time.time() - task_start
        elapsed_str = f"{int(elapsed // 60):02d}:{int(elapsed % 60):02d}"
        await send_event(ws, {
            "type": "done",
            "total_steps": iteration,
            "total_tool_calls": total_tool_calls,
            "had_errors": error_count > 0,
            "error_count": error_count,
            "duration": elapsed_str,
            "tokens_per_sec": round(response.tokens_per_sec, 1)
        })
        break
    else:
        # Max iterations reached
        elapsed = time.time() - task_start
        elapsed_str = f"{int(elapsed // 60):02d}:{int(elapsed % 60):02d}"
        await send_event(ws, {
            "type": "done",
            "total_steps": MAX_TOOL_ITERATIONS,
            "total_tool_calls": total_tool_calls,
            "had_errors": True,
            "error_count": error_count,
            "duration": elapsed_str,
            "warning": f"Reached max iterations ({MAX_TOOL_ITERATIONS})",
            "tokens_per_sec": 0
        })


@router.websocket("/ws/{session_id}")
async def websocket_endpoint(ws: WebSocket, session_id: str):
    await ws.accept()

    # Verify session exists
    session = await db.get_session(session_id)
    if not session:
        await send_event(ws, {"type": "error", "message": f"Session {session_id} not found"})
        await ws.close()
        return

    await send_event(ws, {"type": "connected", "session_id": session_id})

    try:
        while True:
            data = await ws.receive_json()
            msg_type = data.get("type", "")

            if msg_type == "message":
                content = data.get("content", "").strip()
                if content:
                    await handle_user_message(ws, session_id, content)

            elif msg_type == "cancel":
                # TODO: implement cancel via shared event
                await send_event(ws, {"type": "info", "message": "Cancel requested"})

            elif msg_type == "slash_command":
                cmd = data.get("command", "")
                if cmd == "/clear":
                    # Could implement clearing DB messages
                    await send_event(ws, {"type": "info", "message": "Chat cleared"})
                elif cmd == "/history":
                    msgs = await db.get_messages(session_id)
                    await send_event(ws, {
                        "type": "info",
                        "message": f"History: {len(msgs)} messages"
                    })

    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await send_event(ws, {"type": "error", "message": str(e)})
        except Exception:
            pass
