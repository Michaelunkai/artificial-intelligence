from pathlib import Path
import time


SOURCE = Path(
    "/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/"
    "LocalAI/wsl2/a.sh"
)

text = SOURCE.read_text(encoding="utf-8")
marker = 'cat > "$HOME/.local/bin/llama-agent" <<\'AGENTEOF\'\n'
start = text.index(marker) + len(marker)
end = text.index("\nAGENTEOF\n", start)
namespace = {"__name__": "nature_tty_probe"}
exec(compile(text[start:end], "<embedded-llama-agent>", "exec"), namespace)

state = {
    "key": "scan:C",
    "message": "Checked 1,000 files in 20 folders. Now reading C:\\Windows.",
}
progress = namespace["LiveProgress"]()
progress.start(
    (state["key"], state["message"]),
    reporter=lambda elapsed: (state["key"], state["message"]),
)
time.sleep(0.2)
progress.refresh()
state["message"] = (
    "Checked 2,000 files in 40 folders. Now reading C:\\Program Files."
)
progress.refresh()
progress.refresh()
time.sleep(0.2)
progress.stop()

print("REDIRECTED_STDOUT_RESULT")
