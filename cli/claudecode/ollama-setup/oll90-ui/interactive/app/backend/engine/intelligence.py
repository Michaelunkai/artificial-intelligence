"""Intelligence engine - port of oll90 PS agent's 6 intelligence features"""
import re
from typing import Optional


class AgentIntelligence:
    """Per-turn intelligence for STDERR analysis, loop detection, and interceptors."""

    def __init__(self, user_message: str):
        self.user_message = user_message
        self.recent_errors: list[str] = []
        self.error_pattern_window = 5
        self.max_repeated_errors = 3
        self.thinking_reprompted = False
        self.shallow_scan_reprompted = False
        self.turn_tool_calls = 0

    def analyze_stderr(self, stderr: str) -> Optional[str]:
        """Parse STDERR for known error patterns and return an [AGENT HINT]."""
        if not stderr or not stderr.strip():
            return None

        # Parse error location: "At line:X char:Y"
        loc_match = re.search(r'At\s+(?:(.+?):)?(\d+)\s+char:(\d+)', stderr)
        if loc_match:
            line_num = loc_match.group(2)
            char_num = loc_match.group(3)
            lower = stderr.lower()

            # Dollar-sign / variable reference errors (most common)
            if any(kw in lower for kw in ['$', 'variable', 'expression', 'variable reference']):
                return (
                    f"[AGENT HINT] Parse error at line:{line_num} char:{char_num} - "
                    "Unescaped $ in double-quoted string. Use single quotes for literals "
                    "or $() subexpression syntax. Example: 'Error: ' + $varName"
                )

            # Missing/unexpected token errors
            if any(kw in lower for kw in ['missing', 'unexpected', 'token', 'recognized']):
                return (
                    f"[AGENT HINT] Syntax error at line:{line_num} char:{char_num} - "
                    "Check for missing closing braces, quotes, or parentheses. "
                    "Try simplifying the command."
                )

        # Duplicate property in Select-Object
        dup_match = re.search(r"property\s+'(\w+)'\s+cannot be processed.*already exists", stderr, re.IGNORECASE)
        if dup_match:
            prop = dup_match.group(1)
            return f"[AGENT HINT] Duplicate property '{prop}' in Select-Object. Remove one instance."

        # Access denied
        if 'access' in stderr.lower() and 'denied' in stderr.lower():
            return "[AGENT HINT] Access denied. Add -ErrorAction SilentlyContinue for bulk operations."

        # Command not found
        if 'not recognized' in stderr.lower() or 'commandnotfoundexception' in stderr.lower():
            cmd_match = re.search(r"'([^']+)'\s+is not recognized", stderr)
            cmd = cmd_match.group(1) if cmd_match else "the command"
            return f"[AGENT HINT] '{cmd}' not found. Use full cmdlet names (Get-ChildItem not ls, Get-Process not ps)."

        return None

    def check_loop_detection(self, error_text: str) -> Optional[str]:
        """Track error signatures. Return forced approach-change message after 3 identical errors."""
        # Create a signature from the error (first 100 chars, normalized)
        sig = re.sub(r'\s+', ' ', error_text[:100]).strip().lower()
        self.recent_errors.append(sig)

        # Keep sliding window
        if len(self.recent_errors) > self.error_pattern_window:
            self.recent_errors = self.recent_errors[-self.error_pattern_window:]

        # Check for repeated identical errors
        if len(self.recent_errors) >= self.max_repeated_errors:
            last_n = self.recent_errors[-self.max_repeated_errors:]
            if len(set(last_n)) == 1:
                self.recent_errors.clear()
                return (
                    "[SYSTEM] STUCK DETECTED - Same error repeated 3 times. "
                    "You MUST change your approach completely: "
                    "1) Use single-quoted strings instead of double-quoted. "
                    "2) Use string concatenation instead of interpolation. "
                    "3) Simplify the command - break into smaller steps. "
                    "4) Try a completely different cmdlet or method."
                )
        return None

    def check_write_interceptor(self, path: str, content: str) -> Optional[str]:
        """Block plan/report file writes when user didn't ask for file output."""
        user_lower = self.user_message.lower()

        # Check if user explicitly asked for file output
        file_intent_keywords = [
            'save', 'write to', 'create file', 'output to', 'log to', 'store to',
            '.txt', '.ps1', '.json', '.csv', '.log', '.md'
        ]
        if any(kw in user_lower for kw in file_intent_keywords):
            return None  # User wants file output

        # Check if content looks like a plan/report
        content_lower = content.lower()[:500]
        plan_keywords = ['plan', 'report', 'analysis', 'optimization', 'summary', 'result', 'recommendation']
        if any(kw in content_lower for kw in plan_keywords):
            return (
                "[WRITE] BLOCKED - User did not ask for file output. "
                "Present this content directly in your text response instead. "
                "Only use write_file when user explicitly says 'save to file' or gives a file path."
            )

        return None

    def sanitize_path(self, path: str) -> str:
        """Strip invalid .\\C:\\ prefix from absolute Windows paths."""
        cleaned = re.sub(r'^\.[\\/]([A-Za-z]:\\)', r'\1', path)
        return cleaned

    def check_thinking_only(self, content: str) -> Optional[str]:
        """Detect all-<think> responses and return re-prompt message."""
        if not content:
            return None

        # Remove think blocks
        clean = re.sub(r'(?s)<think>.*?</think>', '', content).strip()

        if not clean and '<think>' in content:
            if not self.thinking_reprompted:
                self.thinking_reprompted = True
                return (
                    "[SYSTEM] Your entire response was inside <think> tags and invisible to the user. "
                    "Output your answer as PLAIN VISIBLE TEXT right now - do NOT use <think> tags."
                )
        return None

    def check_shallow_scan(self, tool_call_count: int) -> Optional[str]:
        """Detect shallow scans and demand deeper analysis."""
        if re.search(r'(?i)(scan deeply|deep scan|thorough|comprehensive)', self.user_message):
            if tool_call_count < 5 and not self.shallow_scan_reprompted:
                self.shallow_scan_reprompted = True
                return (
                    "[SYSTEM] You only used {0} tool calls for a deep scan task. "
                    "This is NOT thorough enough. Execute at least 5 more tool calls "
                    "to gather CPU, GPU, RAM, disk, network, process, service, and registry data. "
                    "Scan DEEPLY."
                ).format(tool_call_count)
        return None

    def process_tool_result(self, tool_name: str, stdout: str, stderr: str) -> tuple[str, Optional[str]]:
        """Process a tool result: truncate, analyze stderr, check loops. Returns (result_str, hint)."""
        from config import MAX_OUTPUT_CHARS

        # Truncate output
        if len(stdout) > MAX_OUTPUT_CHARS:
            stdout = stdout[:MAX_OUTPUT_CHARS] + f"\n... [TRUNCATED at {MAX_OUTPUT_CHARS} chars]"

        hint = None
        loop_msg = None

        if stderr and stderr.strip():
            # Analyze stderr
            hint = self.analyze_stderr(stderr)
            # Check for loops
            loop_msg = self.check_loop_detection(stderr)

            result = f"[STDOUT]\n{stdout}\n[STDERR]\n{stderr}"
            if hint:
                result += f"\n{hint}"
        else:
            result = stdout if stdout else "(no output)"

        return result, loop_msg
