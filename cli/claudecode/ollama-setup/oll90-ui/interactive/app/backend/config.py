"""oll90 Backend Configuration"""

OLLAMA_URL = "http://127.0.0.1:11434"
OLLAMA_MODEL = "qwen3.5-oll90"
PORT = 8090
HOST = "0.0.0.0"

MAX_TOOL_ITERATIONS = 25
TOOL_TIMEOUT_SECONDS = 60
MAX_OUTPUT_CHARS = 30000

CONTEXT_WINDOW = 131072
COMPACTION_THRESHOLD = 0.85

DB_PATH = "data/sessions.db"

ERROR_PATTERN_WINDOW = 5
MAX_REPEATED_ERRORS = 3

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_powershell",
            "description": "Execute a PowerShell command on Windows 11 Pro. Returns stdout and stderr. Use for ALL system operations: Get-Process, Get-ChildItem, Get-CimInstance, nvidia-smi, Get-NetAdapter, Get-EventLog, registry queries. Chain commands with semicolons (;), NEVER use &&. Use absolute Windows paths (C:\\, F:\\).",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "The PowerShell command to execute"}
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_cmd",
            "description": "Execute a CMD.exe command. Use for: dir, type, tree, batch files, or programs that behave differently under cmd.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "The CMD command to execute"}
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to an absolute Windows path. Creates parent directories automatically. Overwrites existing files. Use UTF-8 encoding without BOM.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute file path (e.g. C:\\Temp\\script.ps1)"},
                    "content": {"type": "string", "description": "Content to write to the file"}
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read file content by absolute path. Returns the full content as a string.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute file path to read"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "edit_file",
            "description": "Edit a file by replacing a specific text block with new text. The old_text must match exactly one location in the file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute file path"},
                    "old_text": {"type": "string", "description": "Exact text to find and replace (must be unique in the file)"},
                    "new_text": {"type": "string", "description": "Replacement text"}
                },
                "required": ["path", "old_text", "new_text"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List files and directories at the specified path with sizes, dates, and types.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute directory path"},
                    "recursive": {"type": "boolean", "description": "If true, list recursively. Default false."},
                    "pattern": {"type": "string", "description": "Glob pattern filter, e.g. *.txt. Default *"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_files",
            "description": "Search file contents for a text pattern (regex). Returns matching lines with file paths and line numbers. Max 50 results.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory to search in"},
                    "pattern": {"type": "string", "description": "Regex pattern to search for"},
                    "file_glob": {"type": "string", "description": "Only search files matching this glob. Default *.*"}
                },
                "required": ["path", "pattern"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_system_info",
            "description": "Snapshot of CPU, RAM, GPU (via nvidia-smi), disks, and OS info. No parameters needed. Use for quick system overview.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "web_fetch",
            "description": "HTTP GET a URL and return text content with HTML tags stripped. Max 10K chars. Use for fetching web pages, APIs, documentation.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "The URL to fetch (must start with http:// or https://)"}
                },
                "required": ["url"]
            }
        }
    }
]
