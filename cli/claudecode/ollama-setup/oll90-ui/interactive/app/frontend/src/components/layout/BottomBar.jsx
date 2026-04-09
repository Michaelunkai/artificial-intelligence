import useChatStore from '../../stores/chatStore'

export default function BottomBar() {
  const { currentStep, maxSteps, elapsed, errorCount, tokensInfo, isStreaming, messages } = useChatStore()

  return (
    <div className="flex items-center justify-between px-4 py-1.5 bg-terminal-surface border-t border-terminal-border text-xs">
      <div className="flex items-center gap-4">
        {isStreaming && (
          <>
            <span className="text-terminal-yellow">Step {currentStep}/{maxSteps}</span>
            <span className="text-terminal-muted">|</span>
            <span className="text-terminal-cyan">{elapsed}</span>
            <span className="text-terminal-muted">|</span>
            <span className={errorCount > 0 ? 'text-terminal-red' : 'text-terminal-green'}>
              {errorCount} errors
            </span>
          </>
        )}
        {!isStreaming && <span className="text-terminal-muted">Ready</span>}
      </div>
      <div className="flex items-center gap-4">
        <span className="text-terminal-muted">Messages: {messages.length}</span>
        {tokensInfo && <span className="text-terminal-muted">{tokensInfo}</span>}
      </div>
    </div>
  )
}
