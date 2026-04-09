import { query } from "@anthropic-ai/claude-agent-sdk";
const DEFAULT_CWD = process.cwd();
export async function runClaude(options) {
    const { prompt, session, resumeSessionId, onEvent, onSessionUpdate } = options;
    const abortController = new AbortController();
    const sendMessage = (message) => {
        onEvent({
            type: "stream.message",
            payload: { sessionId: session.id, message }
        });
    };
    const sendPermissionRequest = (toolUseId, toolName, input) => {
        onEvent({
            type: "permission.request",
            payload: { sessionId: session.id, toolUseId, toolName, input }
        });
    };
    // Start the query in the background
    (async () => {
        try {
            const q = query({
                prompt,
                options: {
                    cwd: session.cwd ?? DEFAULT_CWD,
                    resume: resumeSessionId,
                    abortController,
                    env: { ...process.env },
                    permissionMode: "bypassPermissions",
                    includePartialMessages: true,
                    allowDangerouslySkipPermissions: true,
                    canUseTool: async (toolName, input, { signal }) => {
                        // For AskUserQuestion, we need to wait for user response
                        if (toolName === "AskUserQuestion") {
                            const toolUseId = crypto.randomUUID();
                            // Send permission request to frontend
                            sendPermissionRequest(toolUseId, toolName, input);
                            // Create a promise that will be resolved when user responds
                            return new Promise((resolve) => {
                                session.pendingPermissions.set(toolUseId, {
                                    toolUseId,
                                    toolName,
                                    input,
                                    resolve: (result) => {
                                        session.pendingPermissions.delete(toolUseId);
                                        resolve(result);
                                    }
                                });
                                // Handle abort
                                signal.addEventListener("abort", () => {
                                    session.pendingPermissions.delete(toolUseId);
                                    resolve({ behavior: "deny", message: "Session aborted" });
                                });
                            });
                        }
                        // Auto-approve other tools
                        return { behavior: "allow", updatedInput: input };
                    }
                }
            });
            // Capture session_id from init message
            for await (const message of q) {
                // Extract session_id from system init message
                if (message.type === "system" && "subtype" in message && message.subtype === "init") {
                    const sdkSessionId = message.session_id;
                    if (sdkSessionId) {
                        session.claudeSessionId = sdkSessionId;
                        onSessionUpdate?.({ claudeSessionId: sdkSessionId });
                    }
                }
                // Send message to frontend
                sendMessage(message);
                // Check for result to update session status
                if (message.type === "result") {
                    const status = message.subtype === "success" ? "completed" : "error";
                    onEvent({
                        type: "session.status",
                        payload: { sessionId: session.id, status, title: session.title }
                    });
                }
            }
            // Query completed normally
            if (session.status === "running") {
                onEvent({
                    type: "session.status",
                    payload: { sessionId: session.id, status: "completed", title: session.title }
                });
            }
        }
        catch (error) {
            if (error.name === "AbortError") {
                // Session was aborted, don't treat as error
                return;
            }
            onEvent({
                type: "session.status",
                payload: { sessionId: session.id, status: "error", title: session.title, error: String(error) }
            });
        }
    })();
    return {
        abort: () => abortController.abort()
    };
}
