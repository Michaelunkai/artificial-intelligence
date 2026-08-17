import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import inspect
import json
import os
import tempfile
import threading
import time
from pathlib import Path

agent_path = os.sys.argv[1]
agent_source = Path(agent_path).read_text(encoding="utf-8")
loader = SourceFileLoader("nature_acceptance", agent_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
nature = importlib.util.module_from_spec(spec)
loader.exec_module(nature)

assert nature.merge_stream_fragment("", "read_") == "read_"
assert nature.merge_stream_fragment("read_", "file") == "read_file"
assert nature.merge_stream_fragment("abc", "abc") == "abcabc"
assert nature.merge_stream_fragment("abc", "c") == "abcc"
assert nature.merge_stream_fragment("old", "new", snapshot=True) == "new"
assert nature.merge_tool_name_fragment("run_", "run_command") == "run_command"
assert nature.merge_tool_name_fragment("read_file", "read_file") == "read_file"
stream_body = nature._prepare_stream_body({"model": "local"})
assert stream_body["return_progress"] is True
assert stream_body["sse_ping_interval"] == 1
assert stream_body["parse_tool_calls"] is True
assert stream_body["parallel_tool_calls"] is False

class FakeResponse:
    def __init__(self, lines):
        self.lines = lines
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        return False
    def __iter__(self):
        for blob in self.lines:
            for line in blob.splitlines(keepends=True):
                yield line

def sse_event(payload):
    return ("data: " + json.dumps(payload) + "\n\n").encode("utf-8")

original_urlopen = nature.urllib.request.urlopen
try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        sse_event({"prompt_progress": {
            "total": 100, "cache": 25, "processed": 50, "time_ms": 12,
        }}),
        sse_event({"choices": [{"delta": {
            "content": "abc",
            "tool_calls": [{
                "index": 0, "id": "call-1",
                "function": {
                    "name": "run_",
                    "arguments": '{"command":"printf ',
                },
            }],
        }}]}),
        sse_event({"choices": [{"delta": {
            "content": "abc",
            "tool_calls": [{
                "index": 0, "id": "call-1",
                "function": {
                    "name": "run_command",
                    "arguments": 'ready"}',
                },
            }],
        }}]}),
        sse_event({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}),
        b"data: [DONE]\n\n",
    ])
    streamed = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
        "tools": [nature.TOOL_CATALOG["run_command"]],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
streamed_message = streamed["choices"][0]["message"]
assert streamed_message["content"] == "abcabc", streamed_message
assert streamed_message["tool_calls"][0]["id"] == "call-1", streamed_message
assert (
    streamed_message["tool_calls"][0]["function"]["name"] == "run_command"
), streamed_message
assert json.loads(
    streamed_message["tool_calls"][0]["function"]["arguments"]
) == {"command": "printf ready"}

try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        b"data: {malformed-json}\n\n",
    ])
    malformed_stream = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
assert "Malformed SSE JSON" in malformed_stream["error"], malformed_stream

try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        sse_event({"choices": [{
            "delta": {"content": "partial"},
            "finish_reason": "stop",
        }]}),
    ])
    incomplete_stream = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
assert "required [DONE] marker" in incomplete_stream["error"], incomplete_stream

malformed_arguments = (
    '{"path":"/tmp/app.py","content":"prefix\\n'
    'uninstall_string = winreg.QueryValueEx(root, "UninstallString")[0]\\n'
    '# Extract path\\nNEW_TAIL'
)
malformed_view = nature._decode_partial_json_field(
    malformed_arguments, "content"
)
assert "NEW_TAIL" in malformed_view["text"], malformed_view
assert malformed_view["status"] == "ambiguous_quote", malformed_view
assert malformed_view["raw_length"] == len(malformed_arguments)
invalid_escape = nature._decode_partial_json_field(
    '{"content":"keep' + chr(92) + 'qtail', "content"
)
assert "\\q" in invalid_escape["text"], invalid_escape
assert invalid_escape["status"] == "invalid_escape", invalid_escape
partial_unicode = nature._decode_partial_json_field(
    '{"content":"value ' + chr(92) + 'u12', "content"
)
assert partial_unicode["status"] == "partial_unicode", partial_unicode
surrogate_pair = nature._decode_partial_json_field(
    '{"content":"' + chr(92) + 'uD83D' + chr(92) + 'uDE00"}', "content"
)
assert surrogate_pair["text"] == "\U0001F600", surrogate_pair
lone_surrogate = nature._decode_partial_json_field(
    '{"content":"' + chr(92) + 'uDEAD', "content"
)
assert lone_surrogate["text"] == "\\uDEAD", lone_surrogate
assert lone_surrogate["status"] == "unpaired_surrogate", lone_surrogate
telemetry = nature.ModelTelemetry(1, 1, 1)
telemetry.update({
    "tool_calls": [{"index": 0, "function": {"name": "read_file"}}],
})
telemetry.update({
    "tool_calls": [{"index": 0, "function": {"name": "read_file"}}],
})
assert telemetry.tool_names[0] == "read_file", telemetry.tool_names
tool_status = telemetry.report(1)
assert tool_status[0] == "model-tool:0:read_file", tool_status
assert "selecting the exact file to read" in tool_status[1].lower(), tool_status
assert "read fileread file" not in tool_status[1]
reasoning_telemetry = nature.ModelTelemetry(2, 1, 1)
reasoning_telemetry.connected = True
reasoning_telemetry.update({
    "reasoning_content": (
        "I will inspect /mnt/f/Downloads/c first, then build the installed-app "
        "inventory scanner."
    )
})
reasoning_status = reasoning_telemetry.report(1)
assert reasoning_status[0].startswith("model-planning:"), reasoning_status
assert "next concrete action" in reasoning_status[1], reasoning_status
assert "88 reasoning characters" in reasoning_status[1], reasoning_status
assert "/mnt/f/Downloads/c" not in reasoning_status[1], reasoning_status
reasoning_telemetry.update({
    "reasoning_content": " Next I will create app.py with the GUI entry point."
})
reasoning_status_second = reasoning_telemetry.report(2)
assert reasoning_status_second[0] == reasoning_status[0]
assert "reasoning characters" in reasoning_status_second[1]
assert reasoning_status_second[1] != reasoning_status[1]
reasoning_telemetry.last_event_at = time.monotonic() - 13
quiet_reasoning_status = reasoning_telemetry.report(13)
assert quiet_reasoning_status[0].startswith("model-planning:"), quiet_reasoning_status
assert quiet_reasoning_status[1] != reasoning_status_second[1], quiet_reasoning_status
assert "in 13 seconds" in quiet_reasoning_status[1], quiet_reasoning_status
assert "app.py with the GUI entry point" not in quiet_reasoning_status[1]
write_telemetry = nature.ModelTelemetry(2, 1, 1)
write_telemetry.connected = True
write_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {
            "name": "write_file",
            "arguments": (
                '{"path":"/mnt/f/Downloads/c/app.py","content":'
                '"import tkinter as tk\\nclass InstalledAppScanner:'
            ),
        },
    }],
})
write_status = write_telemetry.report(3)
assert "/mnt/f/Downloads/c/app.py" in write_status[1], write_status
assert "import: import tkinter as tk" in write_status[1], write_status
assert "InstalledAppScanner" not in write_status[1], write_status
assert "building /mnt/f/Downloads/c/app.py now" in write_status[1], write_status
assert "characters generated" in write_status[1], write_status
assert "InstalledAppScanner class" in nature._describe_generated_text(
    "import tkinter as tk\nclass InstalledAppScanner:",
    final=True,
)
write_quiet_status = write_telemetry.report(4)
assert write_quiet_status[1] == write_status[1], write_quiet_status
assert "/mnt/f/Downloads/c/app.py" in write_quiet_status[1], write_quiet_status
write_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {"arguments": (
            '\\nuninstall_string = root.QueryValue("UninstallString")\\n'
            'NEW_STREAM_TAIL'
        )},
    }],
})
malformed_write_status = write_telemetry.report(5)
assert "generating its first file content now" in malformed_write_status[1], malformed_write_status
assert malformed_write_status[1] != write_status[1]
command_telemetry = nature.ModelTelemetry(2, 1, 1)
command_telemetry.connected = True
command_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {
            "name": "run_command",
            "arguments": (
                '{"command":"python -m pytest '
                '/mnt/f/Downloads/c/tests/test_inventory.py'
            ),
        },
    }],
})
command_status = command_telemetry.report(5)
assert "request characters have arrived" in command_status[1], command_status
assert "pytest" not in command_status[1], command_status
complete_command_status = nature._tool_progress_description(
    "run_command",
    '{"command":"python -m pytest /mnt/f/Downloads/c/tests/test_inventory.py"}',
    72,
    5,
    False,
)
assert "pytest" in complete_command_status, complete_command_status
assert "test_inventory.py" in complete_command_status, complete_command_status
live_capture = io.StringIO()
captured_progress = nature.LiveProgress(
    stream=live_capture,
    interactive=False,
)
captured_progress.start(
    (
        "controlled-quiet-stream",
        "The controlled stream is open and waiting for its first protocol event.",
    ),
    reporter=lambda elapsed: (
        "controlled-quiet-stream",
        "The controlled stream is open and waiting for its first protocol event.",
    ),
)
time.sleep(2.15)
captured_progress.stop()
live_lines = [line for line in live_capture.getvalue().splitlines() if "[WORKING]" in line]
assert len(live_lines) == 1, live_lines
original_heartbeat = nature.LIVE_LOG_HEARTBEAT_SECONDS
original_refresh = nature.LIVE_REFRESH_SECONDS
try:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = 0.15
    nature.LIVE_REFRESH_SECONDS = 0.02
    heartbeat_capture = io.StringIO()
    heartbeat_progress = nature.LiveProgress(
        stream=heartbeat_capture,
        interactive=False,
    )
    heartbeat_progress.start((
        "accelerated-silence-test",
        "The test operation is waiting for its first measurable result.",
    ))
    time.sleep(0.55)
    heartbeat_progress.stop()
    heartbeat_lines = [
        line for line in heartbeat_capture.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(heartbeat_lines) >= 3, heartbeat_lines
    assert len(heartbeat_lines) == len(set(heartbeat_lines)), heartbeat_lines
    assert any("Observation 1 covered seconds" in line for line in heartbeat_lines)
    assert all(
        "no new output, completion signal, or failure" in line
        for line in heartbeat_lines[1:]
    ), heartbeat_lines
finally:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = original_heartbeat
    nature.LIVE_REFRESH_SECONDS = original_refresh
tty_capture = io.StringIO()
tty_capture.isatty = lambda: True
tty_progress = nature.LiveProgress(stream=tty_capture)
tty_state = {
    "key": "controlled-quiet-stream",
    "message": "The controlled stream has started.",
}
tty_progress.start(
    (tty_state["key"], tty_state["message"]),
    reporter=lambda elapsed: (tty_state["key"], tty_state["message"]),
)
tty_progress.refresh()
tty_progress.refresh()
tty_state["message"] = "One new verified result arrived."
tty_progress.refresh()
tty_state["message"] = "The controlled stream has started."
tty_progress.refresh()
tty_progress.stop()
tty_output = tty_capture.getvalue()
assert tty_output.count("\n") == 0, repr(tty_output)
assert tty_output.count("[WORKING]") == 2, repr(tty_output)
assert tty_output.count("\r\033[2K") == 3, repr(tty_output)
assert tty_output.endswith("\r\033[2K"), repr(tty_output)
nature.LiveProgress.begin_job()
next_job_capture = io.StringIO()
next_job_capture.isatty = lambda: True
next_job_progress = nature.LiveProgress(stream=next_job_capture)
next_job_progress.start((
    "controlled-quiet-stream",
    "The controlled stream has started.",
))
next_job_progress.stop()
assert next_job_capture.getvalue().count("[WORKING]") == 1
live_progress_source = agent_source[
    agent_source.index("class LiveProgress:"):
    agent_source.index("\nLIVE = LiveProgress()")
]
assert "_commit_transient" not in live_progress_source
assert '"/dev/tty"' in live_progress_source
assert nature.LIVE_LOG_HEARTBEAT_SECONDS <= 8.0
installer_prefix = Path(agent_path).parent.parent.parent
assert "LIVE_LOG_HEARTBEAT_SECONDS = min(" in agent_source
history_bindings = nature.build_prompt_key_bindings()
history_keys = " ".join(
    str(key) for binding in history_bindings.bindings for key in binding.keys
)
assert "Up" in history_keys and "Down" in history_keys, history_keys
files_hint = nature.plan_hint(
    "scan and list the top 50 biggest heaviest files all over my c drive ranked by size"
)
assert "50 largest files on drive C" in files_hint[0], files_hint
assert "win-tools files C 50" in files_hint[1], files_hint
assert nature.direct_largest_files_request(
    "Output the top 100 heaviest files in C-drive, ranked downwards."
) == ("C", 100)
assert nature.direct_largest_files_request(
    "Scan and list. In here the top of 100 files in my C drive ranked "
    "from heaviest downwards."
) == ("C", 100)
assert nature.normalize_windows_drive("air") == "R"
assert nature.normalize_windows_drive("R:") == "R"
assert nature.normalize_windows_drive("nonsense") is None
assert nature.extract_windows_drive(
    "List all the folders in my air drive"
) == "R"
assert nature.direct_drive_listing_request(
    "List all the folders in my air drive"
) == "R"
assert nature.direct_drive_listing_request(
    "Delete folders in my R drive"
) is None
assert nature.intercept_command(
    "win-tools dir air",
    "List all the folders in my air drive",
) == "win-tools dir R:"
assert nature.intercept_command(
    "win-tools dir air FOLDERS",
    "List all the folders in my air drive",
) == "win-tools dir R: FOLDERS"
assert nature.intercept_command(
    "win-tools disk air",
    "Show free space on my air drive",
) == "win-tools disk R"
drive_hint = nature.plan_hint("List all the folders in my air drive")
assert "drive R" in drive_hint[0], drive_hint
assert "win-tools dir R FOLDERS" in drive_hint[1], drive_hint
exact_file_request = (
    "Create /tmp/nature-final-progress-proof.txt containing exactly "
    "FINAL_PROGRESS_OK, read it back, verify the exact content, then report "
    "the verified full path and content."
)
assert nature.direct_exact_file_request(exact_file_request) == (
    "/tmp/nature-final-progress-proof.txt",
    "FINAL_PROGRESS_OK",
)
assert nature.direct_exact_file_request(
    'Write the file at "/tmp/exact phrase.txt" with the content exactly '
    '"two words", then read and verify it.'
) == ("/tmp/exact phrase.txt", "two words")
assert nature.direct_exact_file_request(
    "Build a project that can create files containing exactly what users type."
) is None
read_only_request = (
    "Read /proc/sys/kernel/osrelease using tools, verify the result, "
    "and do not change any files."
)
assert not nature.objective_requires_action(read_only_request), read_only_request
assert nature.objective_requires_verification(read_only_request), read_only_request
assert not nature.objective_requires_action(
    "Verify the value without modifying files."
)
assert nature.objective_requires_action(
    "Fix the parser without changing its public API."
)
assert nature.objective_requires_action(
    "Do not stop until you fix the parser."
)
read_only_state = nature.TaskState(read_only_request)
assert not read_only_state.requires_action
assert read_only_state.requires_verification
assert read_only_state.completion_gaps("[TASK_COMPLETE]") == [
    "no successful verification action has been recorded"
]
read_only_state.sequence = 1
read_only_state.last_verification_sequence = 1
assert read_only_state.completion_gaps("[TASK_COMPLETE]") == []
verification_pressure_state = nature.TaskState(
    "Create and verify a complete project in /tmp/pressure-project"
)
verification_pressure_state.mutations = (
    nature.MAX_MUTATIONS_WITHOUT_VERIFICATION
)
assert verification_pressure_state.verification_due()
assert nature._is_verification_call({
    "type": "command",
    "cmd": "python3 /tmp/pressure-project/run_tests.py",
})
for verification_command in (
    "pylint /tmp/project/main.py",
    "ruff check /tmp/project",
    "mypy /tmp/project",
    "flake8 /tmp/project",
    "pyright /tmp/project",
    "php -l /tmp/project/index.php",
    "ruby -c /tmp/project/app.rb",
    "luac -p /tmp/project/app.lua",
    "javac /tmp/project/Main.java",
    "clang -fsyntax-only /tmp/project/main.c",
):
    assert nature._is_verification_call({
        "type": "command",
        "cmd": verification_command,
    }), verification_command
assert not nature._is_verification_call({
    "type": "command",
    "cmd": "mkdir -p /tmp/pressure-project/extra",
})
windows_path_command = (
    r"mkdir -p F:\Downloads\c\AppList && "
    r"cd F:\Downloads\c\AppList && chmod +x F:\Downloads\c\AppList\main.py"
)
assert nature.normalize_windows_paths_in_bash(windows_path_command) == (
    "mkdir -p /mnt/f/Downloads/c/AppList && "
    "cd /mnt/f/Downloads/c/AppList && chmod +x /mnt/f/Downloads/c/AppList/main.py"
)
assert nature.normalize_windows_paths_in_bash(
    r'powershell.exe -Command "Get-Item F:\Downloads\c\AppList"'
) == r'powershell.exe -Command "Get-Item F:\Downloads\c\AppList"'
requested_app_objective = (
    r"Create and verify the Windows application in F:\Downloads\c\AppList."
)
hallucinated_mirror = "/mnt/c/Users/micha/F_Downloads/c/AppList"
aligned_command = nature.align_call_to_requested_targets({
    "type": "command",
    "cmd": (
        f"cd {hallucinated_mirror} && "
        "dotnet build AppList/AppList.csproj"
    ),
}, requested_app_objective)
assert hallucinated_mirror not in aligned_command["cmd"], aligned_command
assert "/mnt/f/Downloads/c/AppList" in aligned_command["cmd"], aligned_command
assert "intent_repaired" in aligned_command, aligned_command
aligned_write = nature.align_call_to_requested_targets({
    "type": "write",
    "path": f"{hallucinated_mirror}/AppList/MainWindow.xaml",
    "content": "<Window />",
}, requested_app_objective)
assert aligned_write["path"] == (
    "/mnt/f/Downloads/c/AppList/AppList/MainWindow.xaml"
), aligned_write
assert nature.missing_command_recovery("dotnet") == (
    "dotnet-sdk-10.0", "dotnet --info"
)
assert nature.missing_command_recovery("cargo") == (
    "rustup", "cargo --version"
)
for command_name, tool_name in (
    ("zig", "zig"),
    ("deno", "deno"),
    ("bun", "bun"),
    ("julia", "julia"),
    ("swift", "swift"),
    ("dart", "dart"),
    ("flutter", "flutter"),
):
    package, verification = nature.missing_command_recovery(command_name)
    assert package == f"mise:{tool_name}", (command_name, package)
    assert command_name in verification, (command_name, verification)
assert nature.missing_command_recovery("unknown-tool") is None
assert nature.is_foreground_gui_command(
    "python3 /mnt/f/Downloads/c/AppList/main.py"
)
assert not nature.is_foreground_gui_command(
    "python3 -m py_compile /mnt/f/Downloads/c/AppList/main.py"
)
for verification_script in (
    "python3 /mnt/f/Downloads/c/test_app.py",
    "python3 /mnt/f/Downloads/c/final_check.py",
    "python3 /mnt/f/Downloads/c/check_inventory.py",
    "python3 /mnt/f/Downloads/c/inventory_test.py",
):
    assert not nature.is_foreground_gui_command(
        verification_script
    ), verification_script
assert nature.harden_local_tool_launchers("win-tools boot") == (
    '/bin/bash "$HOME/.local/bin/win-tools" boot'
)
assert nature.harden_local_tool_launchers(
    'win-tools scan C 50 && win-tools startup'
) == (
    '/bin/bash "$HOME/.local/bin/win-tools" scan C 50 && '
    '/bin/bash "$HOME/.local/bin/win-tools" startup'
)
python_compile_narration = nature.narrate({
    "type": "command",
    "cmd": "python3 -m py_compile /tmp/project/main.py",
})
python_test_narration = nature.narrate({
    "type": "command",
    "cmd": "python3 -m unittest discover -s /tmp/project/tests -v",
})
assert python_compile_narration != python_test_narration
assert "syntax" in python_compile_narration.lower()
assert "test" in python_test_narration.lower()
dotnet_narration = nature.narrate({
    "type": "command",
    "cmd": "dotnet build /tmp/project/App.csproj",
})
assert "building" in dotnet_narration.lower()
assert "app.csproj" in dotnet_narration.lower()
mkdir_narration = nature.narrate({
    "type": "command",
    "cmd": "mkdir -p /tmp/project/src",
})
assert "creating" in mkdir_narration.lower()
assert "/tmp/project/src" in mkdir_narration
assert 0 < nature.CMD_STALL_TIMEOUT <= 90
agent_turn_source = inspect.getsource(nature.agent_turn)
active_turn_source = inspect.getsource(nature._agent_turn_active)
assert "while True" in agent_turn_source
assert "_agent_turn_active" in agent_turn_source
assert "ensure_model_server_until_ready" in active_turn_source
assert "except SystemExit:" in active_turn_source
assert active_turn_source.index("except SystemExit:") < active_turn_source.index(
    "except BaseException as exc:"
)
assert "local model server failed to start. The task checkpoint is" not in (
    active_turn_source
)
assert "ensure_initial_server_until_ready" in inspect.getsource(
    nature.interactive_mode
)
assert "ensure_initial_server_until_ready" in inspect.getsource(
    nature.single_shot_mode
)
verification_pressure_state.observe_tool(
    {"type": "read", "path": "/tmp/pressure-project/check.txt"},
    "verified bytes",
)
assert not verification_pressure_state.verification_due()
assert (
    verification_pressure_state.verified_mutation_count
    == verification_pressure_state.mutations
)
partial_answer_progress = nature._describe_generated_text("**Final")
assert "7 characters generated" in partial_answer_progress
assert "**Final" not in partial_answer_progress
complete_answer_progress = nature._describe_generated_text(
    "Both files were read and verified.\n| File"
)
assert "Both files were read and verified" in complete_answer_progress
assert "| File" not in complete_answer_progress
table_answer_progress = nature._describe_generated_text(
    "| Check passed? | Yes |\n"
)
assert "Check passed?: Yes" in table_answer_progress
assert nature._plain_generated_line("[TASK_COMPLETE]") == ""
partial_command_progress = nature._tool_progress_description(
    "run_command",
    '{"command":"cat /proc/sys',
    24,
    1.0,
    False,
)
assert "request characters have arrived" in partial_command_progress
assert "cat /proc/sys" not in partial_command_progress
exact_file_answer = nature.deterministic_exact_file_answer(
    "/tmp/nature-final-progress-proof.txt",
    "FINAL_PROGRESS_OK",
)
assert "FINAL_PROGRESS_OK" in exact_file_answer
assert "18 bytes" not in exact_file_answer
assert "[TASK_COMPLETE]" not in exact_file_answer
largest_answer = nature.deterministic_largest_files_answer(
    "C:\\small.bin|10|0 GB\nC:\\large.bin|100|0.001 GB\n"
    "SUMMARY|files|ranked=2|directories=3|files=4",
    "C",
    100,
)
assert largest_answer.index("C:\\large.bin") < largest_answer.index("C:\\small.bin")
assert "100 bytes" in largest_answer
assert nature.intercept_command(
    "win-tools scan C",
    "scan and list the top 50 biggest heaviest files all over my c drive ranked by size",
) == "win-tools files C 50"
assert "largest files" in nature.narrate({"type": "command", "cmd": "win-tools files C 50"}).lower()
assert "files were measured" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools files C 50"},
    "C:\\sample.bin|1048576|0.001 GB",
).lower()
power_shell_parameter_error = (
    "Get-ChildItem : A parameter cannot be found that matches parameter name "
    "'Directory'.\nCategoryInfo : InvalidArgument\n"
    "FullyQualifiedErrorId : NamedParameterNotFound"
)
assert nature._tool_failed(power_shell_parameter_error)
assert "failed" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools dir R"},
    power_shell_parameter_error,
).lower()
drive_answer = nature.deterministic_drive_listing_answer(
    "Top-level folders on R (NAME|LASTWRITE):\n"
    "FOLDER|Projects|8/16/2026 1:00:00 PM\n"
    "FOLDER|Study|8/16/2026 2:00:00 PM\n"
    "FILE|note.txt|0.1\n"
    "SUMMARY|dir|drive=R|folders=2|files=1",
    "R",
)
assert "Projects" in drive_answer and "Study" in drive_answer
assert "note.txt" not in drive_answer
assert "every top-level folder" in nature.narrate({
    "type": "command",
    "cmd": "win-tools dir C FOLDERS",
}).lower()
assert "2 verified top-level folders" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools dir C FOLDERS"},
    "FOLDER|Projects|now\nFOLDER|Study|now\n"
    "SUMMARY|dir|drive=C|folders=2|mode=folders-only",
).lower()
assert nature.response_delegates_action_to_user(
    "Would you like me to execute these commands?"
)
handoff_state = nature.TaskState("List the folders on drive R")
handoff_gaps = handoff_state.completion_gaps(
    "Would you like me to execute these commands?\n[TASK_COMPLETE]"
)
assert (
    "the response asks the user to perform work that the agent must execute"
    in handoff_gaps
), handoff_gaps
write_summary = nature.interpret_result(
    {"type": "write", "path": "/tmp/unique-result.txt"},
    "[File written atomically: /tmp/unique-result.txt (686 characters, 9 ms)]",
)
assert "/tmp/unique-result.txt" in write_summary, write_summary
assert "686 characters" in write_summary, write_summary
assert "9 ms" in write_summary, write_summary
assert "confirming it is in place" not in write_summary.lower(), write_summary
read_summary = nature.interpret_result(
    {"type": "read", "path": "/tmp/unique-result.txt"},
    "first line\nsecond line\n",
)
assert "/tmp/unique-result.txt" in read_summary, read_summary
assert "2 non-empty line" in read_summary, read_summary
assert "22 characters" in read_summary, read_summary
filename_hint = nature.plan_hint(
    "find and output the full path to freebuff exe specifically"
)
assert "freebuff.exe" in filename_hint[0].lower(), filename_hint
assert "win-tools search ALL freebuff.exe FIRST" in filename_hint[1], filename_hint
fixture_request = (
    "find and output the full path to "
    "nature-progress-fixture-6f4a2c9e.exe specifically on F drive"
)
assert not nature.objective_requires_action(fixture_request), fixture_request
assert nature.is_direct_windows_filename_request(fixture_request), fixture_request
fixture_hint = nature.plan_hint(fixture_request)
assert "win-tools search F nature-progress-fixture-6f4a2c9e.exe FIRST" in fixture_hint[1]
assert nature.intercept_command(
    "win-tools search F nature-progress-fixture-6f4a2c9e.exe",
    fixture_request,
) == "win-tools search F nature-progress-fixture-6f4a2c9e.exe FIRST"
assert nature.objective_requires_action(
    "fix the program that searches for nature-progress-fixture-6f4a2c9e.exe"
)
assert not nature.is_direct_windows_filename_request(
    "fix the program that searches for nature-progress-fixture-6f4a2c9e.exe"
)
assert nature.intercept_command(
    'find /mnt/c /mnt/d /mnt/e /mnt/f -name "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    'find /mnt/c -name "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically on C drive",
) == "win-tools search C freebuff.exe FIRST"
assert nature.intercept_command(
    'find /mnt/c /mnt/d /mnt/e /mnt/f -iname "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    "win-tools search ALL freebuff.exe FIRST",
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    "win-tools search ALL 'Program Files & Tools.exe' ALL",
    "find every matching filename",
) == "win-tools search ALL 'Program Files & Tools.exe' ALL"
assert nature.deterministic_filename_answer(
    "MATCH|C:\\Tools\\Freebuff.exe|188772104\n"
    "SUMMARY|search|mode=FIRST|matches=1|reported=1",
    "freebuff.exe",
) == "The full path is:\nC:\\Tools\\Freebuff.exe"
assert nature.deterministic_filename_answer(
    "SUMMARY|search|mode=FIRST|matches=0|reported=0",
    "missing.exe",
) == "No exact Windows filename match was found for missing.exe in the scanned scope."
progress_event = nature.parse_live_progress_line(
    r"LLAMA_PROGRESS|search|scanning|C:|37|1284|0|C:\Windows\System32"
)
assert progress_event and progress_event[0].startswith("tool-progress:search:scanning:C:")
assert "1,284 files" in progress_event[1], progress_event
assert "C:\\Windows\\System32" in progress_event[1], progress_event
progress_match = nature.parse_live_progress_line(
    r"LLAMA_PROGRESS|search|match|C:|38|1301|1|C:\Tools\freebuff.exe"
)
assert progress_match, progress_match
assert "c:\\tools\\freebuff.exe" in progress_match[1].lower(), progress_match
assert "1,301 files, 38 folders checked" in progress_match[1], progress_match
marker_state = nature.TaskState("answer this read-only question")
marker_gaps = marker_state.completion_gaps("The verified answer is ready.", "stop")
assert marker_gaps == ["the final completion marker is missing"], marker_gaps
assert nature.accept_marker_only_completion(
    marker_state,
    "The verified answer is ready.",
    marker_gaps,
) == []
assert marker_state.events[-1]["kind"] == "completion-marker-repaired"
rejection_state = nature.TaskState("Create and verify /tmp/rejection-fixture")
rejection_gaps = ["no successful modifying action has been recorded"]
first_repeat, first_status = nature.register_completion_rejection(
    rejection_state, rejection_gaps
)
second_repeat, second_status = nature.register_completion_rejection(
    rejection_state, rejection_gaps
)
assert first_repeat == 1 and second_repeat == 2
assert first_status != second_status
assert "No-action recovery 1" in first_status
assert "No-action recovery 2" in second_status
rejection_payload = rejection_state.to_dict()
restored_rejection = nature.TaskState(
    rejection_state.objective,
    restored=rejection_payload,
)
third_repeat, third_status = nature.register_completion_rejection(
    restored_rejection, rejection_gaps
)
assert third_repeat == 3
assert "No-action recovery 3" in third_status
active_turn_source = inspect.getsource(nature._agent_turn_active)
assert "Completion was rejected:" not in active_turn_source
assert "wait_with_progress(" in active_turn_source
assert "recover_model_server(force=True)" in active_turn_source
code, streamed_result, streamed_error = nature.run_live_process(
    "printf 'LLAMA_PROGRESS|search|scanning|C:|1|2|0|C:\\\\fixture\\n'; printf 'MATCH|C:\\\\fixture\\\\freebuff.exe|12\\n'",
    shell=True,
    timeout=10,
    env=os.environ.copy(),
    label="Running command: structured progress fixture",
)
assert code == 0 and not streamed_error, streamed_error
assert "LLAMA_PROGRESS" not in streamed_result, streamed_result
assert "MATCH|C:\\fixture\\freebuff.exe|12" in streamed_result, streamed_result
checkpoint_notice = nature.pending_task_notice({
    "task_id": "task-preserved",
    "objective": "finish the preserved verification task",
})
assert "task-preserved" in checkpoint_notice, checkpoint_notice
assert "llama --resume" in checkpoint_notice, checkpoint_notice
assert "before starting different work" in checkpoint_notice, checkpoint_notice
assert nature.MODEL_ACTION_TIMEOUT > 0
assert nature.MODEL_STREAM_IDLE_TIMEOUT > 0
assert nature.FOCUSED_ACTION_MAX_TOKENS >= 4096
chime_path = nature._ensure_completion_chime()
chime_bytes = chime_path.read_bytes()
assert chime_bytes[:4] == b"RIFF" and chime_bytes[8:12] == b"WAVE"
assert len(chime_bytes) > 50000, len(chime_bytes)
chime_command = nature._completion_chime_command(chime_path)
assert Path(chime_command[0]).name == "powershell.exe", chime_command
assert "-EncodedCommand" in chime_command, chime_command
chime_calls = []
original_play_completion_chime = nature.play_completion_chime
nature.play_completion_chime = (
    lambda wait=False: chime_calls.append(wait) or True
)
try:
    with nature.completion_chime_after_job():
        with nature.completion_chime_after_job():
            pass
finally:
    nature.play_completion_chime = original_play_completion_chime
assert chime_calls == [False], chime_calls
loop_state = nature.TaskState("inspect a stable fixture")
loop_call = {"type": "command", "cmd": "printf stable"}
loop_fingerprint = nature._call_fingerprint(
    loop_call, loop_state.objective
)
loop_state.fingerprints[loop_fingerprint] = {
    "output_hash": "fixture",
    "repeats": 2,
    "sequence": 1,
}
assert loop_state.identical_result_repeats(
    loop_call, loop_state.objective
) == 2
native_read_a = {
    "type": "read",
    "path": "/tmp/repeated-read.txt",
    "tool_call_id": "call-first",
}
native_read_b = {
    "type": "read",
    "path": "/tmp/repeated-read.txt",
    "tool_call_id": "call-second",
}
assert nature._call_fingerprint(native_read_a) == nature._call_fingerprint(
    native_read_b
)
native_loop_state = nature.TaskState("read one exact file")
missing_result = "[File not found: /tmp/repeated-read.txt]"
native_loop_state.observe_tool(native_read_a, missing_result)
native_loop_state.observe_tool(native_read_b, missing_result)
assert native_loop_state.identical_result_repeats(native_read_a) == 2
assert nature._tool_failed(
    "[VERIFICATION REQUIRED: run a readback before another write.]"
)
missing_add_prefix = nature.normalize_unified_diff_hunks(
    "--- /dev/null\n+++ b/new.py\n"
    "@@ -0,0 +1 @@\n"
    "print('ready')\n"
)
assert "\n+print('ready')\n" in missing_add_prefix, missing_add_prefix
missing_context_prefix = nature.normalize_unified_diff_hunks(
    "--- a/sample.py\n+++ b/sample.py\n"
    "@@ -1,2 +1,2 @@\n"
    "alpha\n"
    "beta\n"
)
assert "\n alpha\n beta\n" in missing_context_prefix, missing_context_prefix
gpu_command = ["llama-server", "--model", "/tmp/model.gguf", "--n-gpu-layers", "999"]
assert "--n-gpu-layers" not in nature._set_gpu_layers(gpu_command, None)
cpu_command = nature._set_gpu_layers(gpu_command, 0)
assert cpu_command[cpu_command.index("--n-gpu-layers") + 1] == "0"
assert nature._gpu_layer_value(gpu_command) == "999"
assert nature._gpu_layer_value(cpu_command) == "0"
malformed_read_error = (
    "HTTPError: HTTP 500: Failed to parse tool call arguments as JSON; "
    "last read: '\\\"cat /tmp/project/server.py 2>/dev/null || echo "
    "\\\"NOT FOUND\\\"}'"
)
assert nature.recover_malformed_read_call(malformed_read_error) == {
    "type": "read",
    "path": "/tmp/project/server.py",
}
assert nature.recover_malformed_read_call(
    "Failed to parse tool call arguments as JSON; last read: 'rm -rf /tmp/project'"
) is None
assert nature.recover_malformed_read_call(
    "Failed to parse tool call arguments as JSON; last read: 'cat relative.txt'"
) is None
assert not nature._command_edits_project_files(
    'find / -name "FlowForge" -type d 2>/dev/null | head -10'
)
assert not nature._command_edits_project_files(
    'python3 -m pytest tests -v > /tmp/nature-tests.log 2>&1'
)
assert not nature._is_mutating_call({
    "type": "command",
    "cmd": 'python3 -m pytest tests -v > /tmp/nature-tests.log 2>&1',
})
assert nature._command_edits_project_files(
    'python3 -m pytest tests -v > project-test-output.log 2>&1'
)
assert nature._is_mutating_call({
    "type": "command",
    "cmd": 'cd nested && printf done > result.txt',
})
bounded_find = nature.intercept_command(
    'find / -name "FlowForge" -type d 2>/dev/null | head -10'
)
assert bounded_find.startswith('find . -maxdepth 5 -name "FlowForge"'), bounded_find
restored_find = nature.TaskState("find project", restored={
    "inflight": {
        "type": "command",
        "mutating": True,
        "description": (
            'find / -name "FlowForge" -type d 2>/dev/null | head -10'
        ),
    },
})
assert restored_find.pending_reconciliation is None
assert restored_find.action_was_interrupted({
    "type": "command",
    "cmd": 'find / -name "FlowForge" -type d 2>/dev/null | head -10',
})
restored_stuck_gui = nature.TaskState("build a Windows application", restored={
    "inflight": {
        "fingerprint": nature._call_fingerprint({
            "type": "command",
            "cmd": (
                "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
                "python3 /mnt/f/Downloads/c/AppList/main.py"
            ),
        }, "build a Windows application"),
        "type": "command",
        "mutating": False,
        "description": (
            "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
            "python3 /mnt/f/Downloads/c/AppList/main.py"
        ),
    },
})
stuck_gui_call = {
    "type": "command",
    "cmd": (
        "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
        "python3 /mnt/f/Downloads/c/AppList/main.py"
    ),
}
assert restored_stuck_gui.action_was_interrupted(
    stuck_gui_call, "build a Windows application"
)
assert "Xvfb" in restored_stuck_gui.interrupted_action_reason(
    stuck_gui_call, "build a Windows application"
)
serialized_stuck_gui = restored_stuck_gui.to_dict()
reloaded_stuck_gui = nature.TaskState(
    "build a Windows application", restored=serialized_stuck_gui
)
assert reloaded_stuck_gui.action_was_interrupted(
    stuck_gui_call, "build a Windows application"
)
assert f"Current working directory: {Path.cwd()}." in restored_find.context_summary()
sanitized = nature.sanitize_native_tool_history([
    {
        "role": "assistant",
        "content": "Keep this useful explanation.",
        "tool_calls": [{
            "id": "broken-call",
            "type": "function",
            "function": {
                "name": "run_command",
                "arguments": '{"command":"unterminated',
            },
        }],
    },
    {
        "role": "tool",
        "tool_call_id": "broken-call",
        "content": "[ERROR: malformed call]",
    },
])
assert len(sanitized) == 1, sanitized
assert sanitized[0]["role"] == "assistant", sanitized
assert "Keep this useful explanation." in sanitized[0]["content"], sanitized
assert "[INVALID TOOL CALL PRESERVED AS DATA]" in sanitized[0]["content"], sanitized
assert "broken-call" in sanitized[0]["content"], sanitized
assert "tool_calls" not in sanitized[0], sanitized

routed = {
    item["function"]["name"]
    for item in nature.select_tools(
        r"Build and test a Python website in F:\demo, then open it in Chrome"
    )
}
assert {
    "run_command", "run_python", "read_file", "write_file",
    "append_file", "apply_patch", "win_tools", "browse",
}.issubset(routed), routed

malformed_native = nature.tool_calls_to_calls([{
    "id": "bad-json",
    "function": {
        "name": "win_tools",
        "arguments": '{"action":"search"',
    },
}])[0]
assert malformed_native["type"] == "invalid", malformed_native
assert "rejected before execution" in malformed_native["error"], malformed_native
assert nature.execute_tool_call(malformed_native).startswith("[ERROR:")
python_command_alias = nature.tool_calls_to_calls([{
    "id": "python-command",
    "function": {
        "name": "python",
        "arguments": '{"command":"printf ready"}',
    },
}])[0]
assert python_command_alias["type"] == "command", python_command_alias
assert python_command_alias["cmd"] == "printf ready", python_command_alias
quoted_search = nature.tool_calls_to_calls([{
    "id": "quoted-search",
    "function": {
        "name": "win_tools",
        "arguments": json.dumps({
            "action": "search",
            "drive": "ALL",
            "args": ["Program Files & Tools.exe"],
        }),
    },
}])[0]
assert quoted_search["cmd"] == (
    "win-tools search ALL 'Program Files & Tools.exe'"
), quoted_search
dict_arguments = nature.tool_calls_to_calls([{
    "id": "dict-arguments",
    "function": {
        "name": "run_command",
        "arguments": {"command": "printf dict-ok"},
    },
}])[0]
assert dict_arguments["type"] == "command", dict_arguments
mcp_schema = nature.TOOL_CATALOG["mcp_call"]["function"]["parameters"]
assert (
    mcp_schema["properties"]["arguments"]["additionalProperties"] is True
), mcp_schema

retry_source = {
    "model": "local",
    "messages": [{"role": "user", "content": "build it"}],
    "tools": nature.TOOLS_SPEC,
    "temperature": 0.6,
    "cache_prompt": True,
}
oversized_retry = nature._build_retry_body(
    retry_source,
    retry_source["messages"],
    "oversized_write: 13000 decoded characters",
    1,
)
retry_tool_names = {
    tool["function"]["name"] for tool in oversized_retry["tools"]
}
assert "write_file" not in retry_tool_names
assert "append_file" not in retry_tool_names
assert {
    "run_command", "run_python", "apply_patch", "read_file",
}.issubset(retry_tool_names), retry_tool_names
assert oversized_retry["cache_prompt"] is False
assert oversized_retry["temperature"] == 0.1
assert oversized_retry["reasoning_effort"] == "none"

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    anchored_test = root / "tests" / "test_atlasflow.py"
    anchored_test.parent.mkdir()
    anchored_test.write_text("pass\n", encoding="utf-8")
    old_cwd = Path.cwd()
    try:
        os.chdir(root)
        anchored_find = nature.intercept_command(
            'find /mnt/c/Users -name "test_atlasflow.py" 2>/dev/null | head -5',
            "Fix the project tests/test_atlasflow.py and run every test.",
        )
    finally:
        os.chdir(old_cwd)
    assert anchored_find == (
        "find . -maxdepth 8 -type f "
        "-path './tests/test_atlasflow.py' -print"
    ), anchored_find

    oversized_parent = root / "must-not-exist-parent"
    oversized = oversized_parent / "must-not-exist.txt"
    result = nature.execute_tool_call({
        "type": "write",
        "path": str(oversized),
        "content": "x" * (nature.MAX_WHOLE_FILE_CHARS + 1),
    })
    assert "safe per-call limit" in result
    assert not oversized.exists()
    assert not oversized_parent.exists()

    history_path = root / "history"
    from prompt_toolkit.history import FileHistory
    FileHistory(str(history_path)).append_string("persistent prompt one")
    loaded = list(FileHistory(str(history_path)).load_history_strings())
    assert "persistent prompt one" in loaded
    key_text = " ".join(
        str(key)
        for binding in nature.build_prompt_key_bindings().bindings
        for key in binding.keys
    )
    assert "Up" in key_text and "Down" in key_text, key_text

    from prompt_toolkit import PromptSession
    from prompt_toolkit.input.defaults import create_pipe_input
    from prompt_toolkit.output import DummyOutput
    FileHistory(str(history_path)).append_string("persistent prompt two")
    with create_pipe_input() as pipe_input:
        prompt = PromptSession(
            history=FileHistory(str(history_path)),
            input=pipe_input,
            output=DummyOutput(),
            key_bindings=nature.build_prompt_key_bindings(),
            enable_history_search=False,
        )
        def press_history_keys():
            for keys in ("\x1b[A", "\x1b[A", "\x1b[B", "\r"):
                time.sleep(0.1)
                pipe_input.send_text(keys)
        threading.Thread(target=press_history_keys, daemon=True).start()
        assert prompt.prompt() == "persistent prompt two"

    sample = root / "sample.txt"
    sample.write_text("old\n")
    patch = (
        "diff --git a/sample.txt b/sample.txt\n"
        "--- a/sample.txt\n+++ b/sample.txt\n"
        "@@ -1 +1 @@\n-old\n+new\n"
    )
    try:
        os.chdir(root)
        patch_result = nature.execute_tool_call({"type": "patch", "patch": patch})
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in patch_result.lower(), patch_result
    assert sample.read_text() == "new\n"

    nested_project = root / "Project" / "AtlasFlow"
    nested_project.mkdir(parents=True)
    nested_api = nested_project / "api.py"
    nested_api.write_text("before\n", encoding="utf-8")
    nested_patch = (
        "diff --git a/AtlasFlow/api.py b/AtlasFlow/api.py\n"
        "--- a/AtlasFlow/api.py\n+++ b/AtlasFlow/api.py\n"
        "@@ -1 +1 @@\n-before\n+after\n"
    )
    try:
        os.chdir(root)
        rebased_result = nature.execute_tool_call({
            "type": "patch", "patch": nested_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in rebased_result.lower(), rebased_result
    assert nested_api.read_text(encoding="utf-8") == "after\n"

    malformed_context = root / "malformed_context.py"
    malformed_context.write_text(
        "def first():\n    return 1\n\ndef second():\n    return 2\n",
        encoding="utf-8",
    )
    malformed_patch = (
        "--- a/malformed_context.py\n+++ b/malformed_context.py\n"
        "@@ -1,2 +1,3 @@\n"
        "def first():\n"
        "    return 1\n"
        "+    # verified\n"
        "@@ -4,2 +5,2 @@\n"
        "def second():\n"
        "-    return 2\n"
        "+    return 3\n"
    )
    try:
        os.chdir(root)
        malformed_result = nature.execute_tool_call({
            "type": "patch", "patch": malformed_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in malformed_result.lower(), malformed_result
    assert "# verified" in malformed_context.read_text(encoding="utf-8")
    assert "return 3" in malformed_context.read_text(encoding="utf-8")

    stale = root / "stale.txt"
    stale.write_text("alpha\nunique old line\nomega\n", encoding="utf-8")
    stale_patch = (
        "--- a/stale.txt\n+++ b/stale.txt\n"
        "@@ -50,3 +50,3 @@\n"
        " context that is intentionally stale\n"
        "-unique old line\n"
        "+unique new line\n"
        " another stale context line\n"
    )
    try:
        os.chdir(root)
        stale_result = nature.execute_tool_call({
            "type": "patch", "patch": stale_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert (
        stale_result.startswith("[PATCH APPLIED:")
        or "validated and applied" in stale_result.lower()
    ), stale_result
    assert stale.read_text(encoding="utf-8") == "alpha\nunique new line\nomega\n"

    refresh = root / "refresh.py"
    refresh.write_text("one\ntwo\nthree\n", encoding="utf-8")
    refresh_patch = (
        "--- a/refresh.py\n+++ b/refresh.py\n"
        "@@ -99,1 +99,1 @@\n"
        "-missing stale line\n"
        "+fresh line\n"
    )
    try:
        os.chdir(root)
        refresh_result = nature.execute_tool_call({
            "type": "patch", "patch": refresh_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert refresh_result.startswith("[ERROR: Patch validation failed"), refresh_result
    assert "[FRESH TARGET EVIDENCE: refresh.py (complete file)" in refresh_result
    assert "one\ntwo\nthree" in refresh_result
    assert refresh.read_text(encoding="utf-8") == "one\ntwo\nthree\n"

    direct = root / "direct.txt"
    direct.write_text("before\nunique direct line\nafter\n", encoding="utf-8")
    try:
        os.chdir(root)
        direct_result = nature.apply_unique_single_line_patch(
            "--- a/direct.txt\n+++ b/direct.txt\n"
            "@@ -99,1 +99,1 @@\n"
            "-unique direct line\n"
            "+recovered direct line\n"
        )
    finally:
        os.chdir(old_cwd)
    assert direct_result.startswith("[PATCH APPLIED:"), direct_result
    assert direct.read_text(encoding="utf-8") == (
        "before\nrecovered direct line\nafter\n"
    )

    multi = root / "multi.txt"
    multi.write_text("alpha\none\nmiddle\ntwo\nomega\n", encoding="utf-8")
    try:
        os.chdir(root)
        multi_result = nature.execute_tool_call({
            "type": "patch",
            "patch": (
                "--- a/multi.txt\n+++ b/multi.txt\n"
                "@@ -1,3 +1,3 @@\n"
                " alpha\n-one\n+ONE\n"
                " middle\n"
                "@@ -3,3 +3,3 @@\n"
                " middle\n-two\n+TWO\n"
                " omega\n"
            ),
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in multi_result.lower(), multi_result
    assert multi.read_text(encoding="utf-8") == (
        "alpha\nONE\nmiddle\nTWO\nomega\n"
    )

    atomic_a = root / "atomic-a.txt"
    atomic_b = root / "atomic-b.txt"
    atomic_a.write_text("old-a\n", encoding="utf-8")
    atomic_b.write_text("old-b\n", encoding="utf-8")
    try:
        os.chdir(root)
        atomic_result = nature.execute_tool_call({
            "type": "patch",
            "patch": (
                "--- a/atomic-a.txt\n+++ b/atomic-a.txt\n"
                "@@ -1 +1 @@\n-old-a\n+new-a\n"
                "--- a/atomic-b.txt\n+++ b/atomic-b.txt\n"
                "@@ -1 +1 @@\n-old-b\n+new-b\n"
            ),
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in atomic_result.lower(), atomic_result
    assert atomic_a.read_text(encoding="utf-8") == "new-a\n"
    assert atomic_b.read_text(encoding="utf-8") == "new-b\n"

    unsafe = nature.execute_tool_call({
        "type": "patch",
        "patch": (
            "--- a/../escape.txt\n+++ b/../escape.txt\n"
            "@@ -0,0 +1 @@\n+blocked\n"
        ),
    })
    assert "Unsafe patch path rejected" in unsafe

    pipeline_result = nature.execute_tool_call({
        "type": "command",
        "cmd": "printf 'visible pipeline output\\n'; false | true",
    })
    assert "[EXIT CODE:" in pipeline_result, pipeline_result

    original_run_live_process = nature.run_live_process
    try:
        def raise_process_interrupted(*args, **kwargs):
            raise nature.ProcessInterrupted(
                "The operator interrupted only the running subprocess."
            )
        nature.run_live_process = raise_process_interrupted
        interrupted_result = nature.execute_tool_call({
            "type": "command",
            "cmd": "sleep 999",
        })
    finally:
        nature.run_live_process = original_run_live_process
    assert interrupted_result.startswith("[INTERRUPTED SUBPROCESS:"), interrupted_result
    assert "parent task will continue" in interrupted_result.lower(), interrupted_result
    interrupted_state = nature.TaskState("finish the task")
    interrupted_call = {"type": "command", "cmd": "sleep 999"}
    interrupted_state.observe_tool(
        interrupted_call, interrupted_result, "finish the task"
    )
    assert interrupted_state.action_was_interrupted(
        interrupted_call, "finish the task"
    )

    truncated_test = nature.execute_tool_call({
        "type": "command",
        "cmd": "python3 -m unittest discover -v 2>&1 | tail -20",
    })
    assert "Verification output truncation was rejected" in truncated_test

    unchanged = root / "unchanged.txt"
    unchanged.write_text("same", encoding="utf-8")
    no_change = nature.execute_tool_call({
        "type": "write",
        "path": str(unchanged),
        "content": "same",
    })
    assert no_change.startswith("[NO CHANGE:"), no_change
    state = nature.TaskState("change the unchanged test file")
    success, _ = state.observe_tool(
        {"type": "write", "path": str(unchanged), "content": "same"},
        no_change,
        "change the unchanged test file",
    )
    assert success is False
    assert state.pending_reconciliation is None
    assert not state.requires_reconciliation_before({
        "type": "write", "path": str(unchanged), "content": "different",
    })
    migrated = nature.TaskState("resume safely", restored={
        "pending_reconciliation": {
            "description": (
                "a no-op mutation was rejected because the target already "
                "contained the proposed content"
            ),
        },
    })
    assert migrated.pending_reconciliation is None

    identical_sed = nature.execute_tool_call({
        "type": "command",
        "cmd": "sed -i 's/status: int = 20)/status: int = 20)/' unchanged.txt",
    })
    assert "search and replacement are identical" in identical_sed
    assert unchanged.read_text(encoding="utf-8") == "same"
    repaired_call = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/status: int = 20)/status: int = 20)/' server.py",
        },
        "Change the default status code from 20 to 200.",
    )
    assert "status: int = 200)" in repaired_call["cmd"], repaired_call
    assert repaired_call.get("intent_repaired"), repaired_call
    repaired_instead = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/= 20)/= 20)/g' server.py",
        },
        "I keep typing `20)` instead of `200)`. I will fix it now.",
    )
    assert "s/= 20)/= 200)/g" in repaired_instead["cmd"], repaired_instead
    previous_state = nature.CURRENT_TASK_STATE
    nature.CURRENT_TASK_STATE = nature.TaskState(
        "The current invalid source is exactly: for in range(15): and its "
        "body references i. Change only that line to exactly: "
        "for i in range(15): using one focused patch."
    )
    try:
        repaired_literal = nature.repair_identical_numeric_sed_from_message(
            {
                "type": "command",
                "cmd": (
                    "sed -i 's/for in range(15):/for in range(15):/' "
                    "tests/test_atlasflow.py"
                ),
            },
            "Applying the exact requested edit.",
        )
    finally:
        nature.CURRENT_TASK_STATE = previous_state
    assert "s/for in range(15):/for i in range(15):/" in repaired_literal["cmd"]

    class LoopRepairState:
        objective = (
            "The streamed code dropped the missing loop variable i. "
            "Restore the missing loop variable i before execution."
        )

    nature.CURRENT_TASK_STATE = LoopRepairState()
    repaired_loop = nature.repair_missing_python_loop_variable(
        {
            "type": "python",
            "code": "values = []\nfor in range(3):\n    values.append(i)\n",
        },
        "",
    )
    assert "for i in range(3):" in repaired_loop["code"]
    assert "intent_repaired" in repaired_loop
    untouched_loop = nature.repair_missing_python_loop_variable(
        {"type": "python", "code": "for item in range(3):\n    print(item)\n"},
        "",
    )
    assert untouched_loop["code"] == "for item in range(3):\n    print(item)\n"
    nature.CURRENT_TASK_STATE = None

with tempfile.TemporaryDirectory() as transaction_dir:
    previous_cwd = Path.cwd()
    os.chdir(transaction_dir)
    try:
        guarded_python = Path("guarded.py")
        original_python = "for i in range(2):\n    print(i)\n"
        guarded_python.write_text(original_python)
        rollback_result = nature.execute_tool_call({
            "type": "command",
            "cmd": "sed -i 's/for i in range(2):/for in range(2):/' guarded.py",
        })
        assert rollback_result.startswith("[ROLLED BACK:"), rollback_result
        assert guarded_python.read_text() == original_python
    finally:
        os.chdir(previous_cwd)

with tempfile.TemporaryDirectory() as exact_intent_dir:
    previous_cwd = Path.cwd()
    os.chdir(exact_intent_dir)
    try:
        exact_file = Path("sample.py")
        exact_file.write_text("def build():\n    count)(3):\n        print(i)\n")
        exact_calls = nature.objective_exact_line_patch_calls(
            "Current line 2 is exactly count)(3): but must be "
            "for i in range(3):. The missing loop variable i must be restored."
        )
        assert len(exact_calls) == 1, exact_calls
        exact_result = nature.execute_tool_call(exact_calls[0])
        assert (
            exact_result.startswith("[PATCH APPLIED:")
            or exact_result.startswith("[Patch validated and applied")
        ), exact_result
        assert "    for i in range(3):" in exact_file.read_text()
        quoted_file = Path("quoted.py")
        quoted_file.write_text('    "old payload",\n')
        quoted_calls = nature.objective_exact_line_patch_calls(
            'Current line 1 is exactly "old payload", but must be '
            '"new payload". Make only that repair.'
        )
        assert len(quoted_calls) == 1, quoted_calls
        quoted_result = nature.execute_tool_call(quoted_calls[0])
        assert (
            quoted_result.startswith("[PATCH APPLIED:")
            or quoted_result.startswith("[Patch validated and applied")
        ), quoted_result
        assert quoted_file.read_text() == '    "new payload",\n'
    finally:
        os.chdir(previous_cwd)
    assert repaired_literal.get("intent_repaired"), repaired_literal
    ambiguous_call = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/value=20/value=20/' settings.py",
        },
        "Possible values range from 20 to 200 or from 20 to 201.",
    )
    assert ambiguous_call["cmd"].endswith("value=20/' settings.py")

    captured = io.StringIO()
    progress = nature.LiveProgress(stream=captured, interactive=False)
    observed = {
        "key": "fixture-started",
        "message": "The tester started reading a fixed progress fixture.",
    }
    progress.start(
        (observed["key"], observed["message"]),
        reporter=lambda elapsed: (observed["key"], observed["message"]),
    )
    progress.refresh()
    observed.update({
        "key": "fixture-output",
        "message": "The tester received one new line from the fixture.",
    })
    progress.refresh()
    progress.refresh()
    progress.stop()
    live_lines = [
        line for line in captured.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(live_lines) == 2, live_lines
    live_payloads = [line.split("] ", 1)[-1] for line in live_lines]
    assert len(live_payloads) == len(set(live_payloads)), live_payloads
    static_capture = io.StringIO()
    static_progress = nature.LiveProgress(
        stream=static_capture,
        interactive=False,
    )
    static_progress.start((
        "fixed-observation",
        "The tester is reading one unchanged observed state.",
    ))
    time.sleep(1.1)
    static_progress.stop()
    static_lines = [
        line for line in static_capture.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(static_lines) == 1, static_lines
    assert any("[WORKING]" in line for line in static_lines), static_lines
    plan_capture = io.StringIO()
    with contextlib.redirect_stdout(plan_capture):
        silent_plan = nature.TaskPlan(
            "Find and rank the 100 largest files on C drive."
        )
        silent_plan.done(1, "the live scan completed")
    assert plan_capture.getvalue() == "", repr(plan_capture.getvalue())
    server_wait_source = agent_source[
        agent_source.index("def _wait_ready("):
        agent_source.index("\ndef _strip_perf_flags", agent_source.index("def _wait_ready("))
    ]
    assert "LiveProgress()" in server_wait_source, server_wait_source
    assert "print(rendered" not in server_wait_source, server_wait_source
    assert "server-startup-loading" in server_wait_source, server_wait_source

    original_group_stats = nature._process_group_stats
    nature._process_group_stats = lambda pid: (0.0, 12.0, "")
    original_group_io_stats = nature._process_group_io_stats
    nature._process_group_io_stats = lambda pid: (0, 0)
    try:
        process = nature.ProcessTelemetry("Running command: fixed scan")
        process.pid = 42
        started = process.report(0)
        first_quiet_tick = process.report(3)
        assert first_quiet_tick == started, (started, first_quiet_tick)
        assert first_quiet_tick[0] == started[0], (started, first_quiet_tick)
        assert "has not written output yet" in first_quiet_tick[1].lower(), first_quiet_tick
        process.update("Scanning C: drive\n", "output")
        output_event = process.report(4)
        assert output_event[0].startswith("output:"), output_event
        quiet_output_tick = process.report(5)
        assert quiet_output_tick == output_event, (output_event, quiet_output_tick)
        process.last_output_at = time.monotonic() - 9
        waiting_event = process.report(14)
        assert waiting_event[0].startswith("quiet:"), waiting_event
        process.last_output_at -= 1.1
        waiting_tick = process.report(15)
        assert waiting_tick[0] == waiting_event[0], (waiting_event, waiting_tick)
        assert waiting_tick == waiting_event, (waiting_event, waiting_tick)
        assert "remains alive" not in waiting_tick[1].lower(), waiting_tick
        assert "no measurable output, cpu time, or file i/o" in (
            waiting_tick[1].lower()
        ), waiting_tick
        process.last_output_at -= 10
        escalated_tick = process.report(25)
        assert escalated_tick[0] != waiting_event[0], escalated_tick
        assert "recovery" in escalated_tick[1].lower(), escalated_tick
        process.update("C:\\done.bin|1|0 GB\n", "output")
        resumed_event = process.report(16)
        assert resumed_event[0].startswith("output:"), resumed_event
        assert "output resumed" in resumed_event[1].lower(), resumed_event
        process.update(
            r"LLAMA_PROGRESS|search|scanning|C:|37|1284|0|C:\Windows\System32" + "\n",
            "output",
        )
        checkpoint_event = process.report(17)
        assert checkpoint_event[0].startswith("tool-progress:"), checkpoint_event
        assert checkpoint_event[1].startswith(
            "1,284 files, 37 folders checked"
        ), checkpoint_event
        checkpoint_tick = process.report(18)
        assert checkpoint_tick[0] == checkpoint_event[0], checkpoint_tick
        assert checkpoint_tick[1] == checkpoint_event[1], checkpoint_tick
    finally:
        nature._process_group_stats = original_group_stats
        nature._process_group_io_stats = original_group_io_stats

browser = nature._browser_capability()
assert browser["extension_id"] == "hehggadaopoacecdllhhajmbjkdcmajg"
assert browser["interactive_signed_in_control"] is False
print("NATURE_ACCEPTANCE_OK")
