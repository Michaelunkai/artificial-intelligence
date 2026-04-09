class WS {
  constructor() {
    this.ws = null
    this.sessionId = null
    this.handlers = {}
    this.reconnectTimer = null
    this.reconnectDelay = 1000
  }

  on(event, handler) {
    if (!this.handlers[event]) this.handlers[event] = []
    this.handlers[event].push(handler)
  }

  emit(event, data) {
    (this.handlers[event] || []).forEach(h => h(data))
  }

  connect(sessionId) {
    this.sessionId = sessionId
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const url = `${protocol}//${window.location.host}/ws/${sessionId}`

    try {
      this.ws = new WebSocket(url)
    } catch (e) {
      this.emit('error', { message: 'Failed to connect' })
      this.scheduleReconnect()
      return
    }

    this.ws.onopen = () => {
      this.reconnectDelay = 1000
      this.emit('connected', { sessionId })
    }

    this.ws.onmessage = (evt) => {
      try {
        const data = JSON.parse(evt.data)
        this.emit(data.type, data)
        this.emit('message', data)
      } catch (e) {
        console.error('WS parse error:', e)
      }
    }

    this.ws.onclose = () => {
      this.emit('disconnected', {})
      this.scheduleReconnect()
    }

    this.ws.onerror = () => {
      this.emit('error', { message: 'WebSocket error' })
    }
  }

  scheduleReconnect() {
    if (this.reconnectTimer) return
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      if (this.sessionId) {
        this.connect(this.sessionId)
      }
    }, Math.min(this.reconnectDelay, 30000))
    this.reconnectDelay *= 2
  }

  send(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data))
    }
  }

  sendMessage(content) {
    this.send({ type: 'message', content })
  }

  sendCancel() {
    this.send({ type: 'cancel' })
  }

  sendSlashCommand(command) {
    this.send({ type: 'slash_command', command })
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
    this.sessionId = null
  }
}

export const ws = new WS()
export default ws
