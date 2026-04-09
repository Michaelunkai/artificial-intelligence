import { useState, useEffect, useRef } from 'react'

const COMMANDS = [
  { name: '/clear', description: 'Clear conversation history', shortcut: 'Ctrl+L' },
  { name: '/history', description: 'Show message count and token estimate' },
  { name: '/tools', description: 'List available tools' },
  { name: '/new', description: 'Create new session' },
  { name: '/exit', description: 'Close session' },
]

export default function CommandPalette({ open, onClose, onCommand }) {
  const [filter, setFilter] = useState('')
  const [selected, setSelected] = useState(0)
  const inputRef = useRef(null)

  const filtered = COMMANDS.filter(c =>
    c.name.toLowerCase().includes(filter.toLowerCase()) ||
    c.description.toLowerCase().includes(filter.toLowerCase())
  )

  useEffect(() => {
    if (open) {
      setFilter('')
      setSelected(0)
      setTimeout(() => inputRef.current?.focus(), 50)
    }
  }, [open])

  useEffect(() => {
    const handler = (e) => {
      if (e.key === 'k' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        if (open) onClose()
        else onCommand('__toggle__')
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open, onClose, onCommand])

  if (!open) return null

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') onClose()
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setSelected(s => Math.min(s + 1, filtered.length - 1))
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      setSelected(s => Math.max(s - 1, 0))
    }
    if (e.key === 'Enter' && filtered[selected]) {
      onCommand(filtered[selected].name)
      onClose()
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-start justify-center pt-24 z-50" onClick={onClose}>
      <div className="w-96 bg-terminal-surface border border-terminal-border rounded-lg shadow-xl" onClick={e => e.stopPropagation()}>
        <input
          ref={inputRef}
          value={filter}
          onChange={e => setFilter(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type a command..."
          className="w-full px-4 py-3 bg-transparent text-terminal-text outline-none border-b border-terminal-border text-sm"
        />
        <div className="max-h-64 overflow-y-auto">
          {filtered.map((cmd, i) => (
            <div
              key={cmd.name}
              onClick={() => { onCommand(cmd.name); onClose() }}
              className={`px-4 py-2 flex justify-between items-center cursor-pointer text-xs ${
                i === selected ? 'bg-terminal-border text-terminal-text' : 'text-terminal-muted hover:bg-terminal-border/50'
              }`}
            >
              <div>
                <span className="text-terminal-cyan">{cmd.name}</span>
                <span className="ml-2 text-terminal-muted">{cmd.description}</span>
              </div>
              {cmd.shortcut && <span className="text-terminal-muted text-[10px]">{cmd.shortcut}</span>}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
