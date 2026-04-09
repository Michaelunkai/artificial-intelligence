"""Context window management - token tracking and auto-compaction"""
import re
from typing import Optional

from config import CONTEXT_WINDOW, COMPACTION_THRESHOLD


class ContextManager:
    def __init__(self, max_tokens: int = CONTEXT_WINDOW, compact_at: float = COMPACTION_THRESHOLD):
        self.max_tokens = max_tokens
        self.compact_threshold = int(max_tokens * compact_at)
        self.total_prompt_tokens = 0
        self.total_completion_tokens = 0

    def estimate_tokens(self, messages: list[dict]) -> int:
        """Rough estimate: total chars / 3.5 for Qwen tokenizer."""
        total_chars = sum(len(m.get("content", "")) for m in messages)
        return int(total_chars / 3.5)

    def update_from_response(self, prompt_eval_count: int = 0, eval_count: int = 0):
        """Update token counts from Ollama streaming response metrics."""
        if prompt_eval_count:
            self.total_prompt_tokens = prompt_eval_count
        if eval_count:
            self.total_completion_tokens += eval_count

    def needs_compaction(self, messages: list[dict]) -> bool:
        """Check if we should compact based on actual or estimated tokens."""
        if self.total_prompt_tokens > 0:
            return self.total_prompt_tokens > self.compact_threshold
        return self.estimate_tokens(messages) > self.compact_threshold

    def compact(self, messages: list[dict]) -> list[dict]:
        """Compact conversation history, keeping system + last 8 messages."""
        keep_first = 1  # System message
        keep_last = 8   # Last 4 user/assistant pairs

        if len(messages) <= keep_first + keep_last:
            return messages

        # Build summary of middle messages
        middle = messages[keep_first:-keep_last]
        summary_parts = ["=== CONVERSATION SUMMARY (auto-compacted) ==="]

        for m in middle:
            role = m.get("role", "")
            content = m.get("content", "")
            if role == "user":
                preview = content[:100].replace('\n', ' ')
                summary_parts.append(f"USER: {preview}...")
            elif role == "assistant" and content:
                clean = re.sub(r'(?s)<think>.*?</think>', '', content).strip()
                if clean:
                    preview = clean[:200].replace('\n', ' ')
                    summary_parts.append(f"AGENT: {preview}...")
            # Skip tool messages entirely

        summary_parts.append("=== END SUMMARY ===")
        summary = "\n".join(summary_parts)

        # Rebuild messages
        result = [messages[0]]  # System message
        result.append({"role": "user", "content": summary})
        result.extend(messages[-keep_last:])

        return result

    def get_usage_str(self) -> str:
        """Return human-readable token usage string."""
        if self.total_prompt_tokens > 0:
            used = self.total_prompt_tokens
        else:
            used = 0
        return f"~{used // 1000}K/{self.max_tokens // 1000}K tokens"
