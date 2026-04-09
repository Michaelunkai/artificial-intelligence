import { useState, useRef, useEffect } from 'react'
import useChatStore from '../../stores/chatStore'

export default function InputBar({ onSend }) {
  const [input, setInput] = useState('')
  const [history, setHistory] = useState([])
  const [histIdx, setHistIdx] = useState(-1)
  const textareaRef = useRef(null)
  const isStreaming = useChatStore(s => s.isStreaming)

  useEffect(() => {
    if (!isStreaming && textareaRef.current) textareaRef.current.focus()
  }, [isStreaming])

  const handleSubmit = () => {
    const text = input.trim()
    if (!text || isStreaming) return
    setHistory(h => [text, ...h.slice(0, 49)])
    setHistIdx(-1)
    setInput('')
    onSend(text)
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
    if (e.key === 'ArrowUp' && !input) {
      e.preventDefault()
      if (histIdx < history.length - 1) {
        const idx = histIdx + 1
        setHistIdx(idx)
        setInput(history[idx])
      }
    }
    if (e.key === 'ArrowDown' && histIdx >= 0) {
      e.preventDefault()
      if (histIdx > 0) {
        const idx = histIdx - 1
        setHistIdx(idx)
        setInput(history[idx])
      } else {
        setHistIdx(-1)
        setInput('')
      }
    }
  }

  return (
    <div className="border-t border-terminal-border bg-terminal-surface px-4 py-3">
      <div className="flex items-center gap-2">
        <span className="text-terminal-cyan font-bold text-sm shrink-0">oll90&gt;</span>
        <textarea
          ref={textareaRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={isStreaming}
          placeholder={isStreaming ? 'Agent is working...' : 'Type a message...'}
          rows={1}
          className="flex-1 bg-transparent text-terminal-text outline-none resize-none placeholder:text-terminal-muted text-sm disabled:opacity-40"
          style={{ minHeight: '20px', maxHeight: '120px' }}
        />
        <button
          onClick={handleSubmit}
          disabled={isStreaming || !input.trim()}
          className="px-3 py-1 text-xs bg-terminal-cyan/20 text-terminal-cyan rounded hover:bg-terminal-cyan/30 disabled:opacity-30"
        >
          Send
        </button>
      </div>
    </div>
  )
}
