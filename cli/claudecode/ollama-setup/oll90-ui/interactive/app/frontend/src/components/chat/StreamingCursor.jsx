import useChatStore from '../../stores/chatStore'
import MarkdownRenderer from '../markdown/MarkdownRenderer'

export default function StreamingCursor() {
  const { streamingContent, isStreaming, isThinking, streamingThinking } = useChatStore()

  if (!isStreaming) return null

  return (
    <div className="px-4 py-2">
      {isThinking && streamingThinking && (
        <div className="text-terminal-muted text-xs italic mb-2 opacity-60">
          <span className="text-[10px] text-terminal-muted">[thinking] </span>
          {streamingThinking.slice(-200)}
        </div>
      )}
      {streamingContent && (
        <div className="border-l-2 border-terminal-magenta pl-3">
          <div className="text-sm">
            <MarkdownRenderer content={streamingContent} />
          </div>
        </div>
      )}
      {!streamingContent && !isThinking && (
        <div className="flex items-center gap-2 text-terminal-muted text-sm">
          <span className="spinner inline-block w-3 h-3 border border-terminal-cyan border-t-transparent rounded-full" />
          <span>Thinking...</span>
        </div>
      )}
      <span className="cursor-blink text-terminal-cyan">|</span>
    </div>
  )
}
