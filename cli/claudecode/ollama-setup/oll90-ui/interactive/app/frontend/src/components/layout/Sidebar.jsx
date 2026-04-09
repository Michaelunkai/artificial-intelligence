import { useState } from 'react'
import useSessionStore from '../../stores/sessionStore'

export default function Sidebar({ visible }) {
  const { sessions, activeSessionId, createSession, setActiveSession, deleteSession } = useSessionStore()
  const [tab, setTab] = useState('sessions')

  if (!visible) return null

  return (
    <div className="w-64 bg-terminal-surface border-r border-terminal-border flex flex-col h-full overflow-hidden">
      {/* Tabs */}
      <div className="flex border-b border-terminal-border">
        {['sessions', 'tools'].map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`flex-1 py-2 text-xs capitalize ${tab === t ? 'text-terminal-cyan border-b border-terminal-cyan' : 'text-terminal-muted hover:text-terminal-text'}`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'sessions' && (
        <div className="flex-1 overflow-y-auto">
          <button
            onClick={() => createSession()}
            className="w-full py-2 px-3 text-xs text-terminal-green hover:bg-terminal-border text-left"
          >
            + New Session
          </button>
          {sessions.map(s => (
            <div
              key={s.id}
              onClick={() => setActiveSession(s.id)}
              className={`px-3 py-2 text-xs cursor-pointer hover:bg-terminal-border flex justify-between items-center group ${
                s.id === activeSessionId ? 'border-l-2 border-terminal-cyan bg-terminal-border/50' : ''
              }`}
            >
              <div className="truncate flex-1">
                <div className="text-terminal-text truncate">{s.name}</div>
                <div className="text-terminal-muted text-[10px]">{s.message_count || 0} msgs</div>
              </div>
              <button
                onClick={(e) => { e.stopPropagation(); deleteSession(s.id) }}
                className="text-terminal-red opacity-0 group-hover:opacity-100 ml-2 text-[10px]"
              >
                x
              </button>
            </div>
          ))}
        </div>
      )}

      {tab === 'tools' && (
        <div className="flex-1 overflow-y-auto p-3 text-xs text-terminal-muted">
          <div className="mb-2 text-terminal-text">Available Tools:</div>
          {['run_powershell', 'run_cmd', 'write_file', 'read_file', 'edit_file', 'list_directory', 'search_files'].map(t => (
            <div key={t} className="py-1 text-terminal-yellow">{t}</div>
          ))}
        </div>
      )}
    </div>
  )
}
