import { useState } from 'react'

export default function ThinkingBlock({ content, tokenCount }) {
  const [expanded, setExpanded] = useState(false)
  const preview = content ? content.split('\n')[0].slice(0, 80) : ''

  return (
    <div className="px-4 py-1">
      <div
        className="text-xs text-terminal-muted cursor-pointer hover:text-terminal-text/60"
        onClick={() => setExpanded(!expanded)}
      >
        <span className="text-[10px]">[thinking]</span>
        {!expanded && (
          <span className="ml-2 italic opacity-60">
            {preview}... ({tokenCount || '?'} tokens)
          </span>
        )}
        <span className="ml-2">{expanded ? '-' : '+'}</span>
      </div>
      {expanded && (
        <div className="mt-1 text-xs text-terminal-muted/60 italic bg-terminal-surface/30 rounded p-2 max-h-48 overflow-y-auto whitespace-pre-wrap">
          {content}
        </div>
      )}
    </div>
  )
}
