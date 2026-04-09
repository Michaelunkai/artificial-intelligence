import { useState, useEffect, useCallback } from 'react'
import './index.css'
import TopBar from './components/layout/TopBar'
import BottomBar from './components/layout/BottomBar'
import Sidebar from './components/layout/Sidebar'
import ChatContainer from './components/chat/ChatContainer'
import InputBar from './components/chat/InputBar'
import CommandPalette from './components/palette/CommandPalette'
import useWebSocket from './hooks/useWebSocket'
import useSessionStore from './stores/sessionStore'
import useStatusStore from './stores/statusStore'
import useChatStore from './stores/chatStore'

function App() {
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const { sessions, activeSessionId, fetchSessions, createSession, setActiveSession } = useSessionStore()
  const fetchStatus = useStatusStore(s => s.fetchStatus)
  const clearMessages = useChatStore(s => s.clearMessages)
  const { sendMessage } = useWebSocket(activeSessionId)

  // Initial load
  useEffect(() => {
    fetchSessions()
    fetchStatus()
    const interval = setInterval(fetchStatus, 3000)
    return () => clearInterval(interval)
  }, [])

  // Auto-create session if none exists
  useEffect(() => {
    if (sessions.length === 0) return
    if (!activeSessionId) {
      setActiveSession(sessions[0].id)
    }
  }, [sessions, activeSessionId])

  const handleSend = useCallback((text) => {
    if (!activeSessionId) {
      createSession('New Chat').then(session => {
        if (session) {
          setTimeout(() => sendMessage(text), 200)
        }
      })
    } else {
      sendMessage(text)
    }
  }, [activeSessionId, sendMessage, createSession])

  const handleCommand = useCallback((cmd) => {
    if (cmd === '__toggle__') {
      setPaletteOpen(p => !p)
      return
    }
    setPaletteOpen(false)
    switch (cmd) {
      case '/clear':
        clearMessages()
        break
      case '/new':
        createSession()
        break
      case '/sidebar':
        setSidebarOpen(s => !s)
        break
      default:
        break
    }
  }, [clearMessages, createSession])

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e) => {
      if (e.key === 'l' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        clearMessages()
      }
      if (e.key === 'b' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        setSidebarOpen(s => !s)
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [clearMessages])

  return (
    <div className="h-screen flex flex-col bg-terminal-bg">
      <TopBar />
      <div className="flex flex-1 overflow-hidden">
        <Sidebar visible={sidebarOpen} />
        <div className="flex-1 flex flex-col overflow-hidden">
          <ChatContainer />
          <InputBar onSend={handleSend} />
        </div>
      </div>
      <BottomBar />
      <CommandPalette
        open={paletteOpen}
        onClose={() => setPaletteOpen(false)}
        onCommand={handleCommand}
      />
    </div>
  )
}

export default App
