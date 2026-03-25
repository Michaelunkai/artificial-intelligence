/**
 * AgentFlow WebSocket Client
 * Real-time updates for the dashboard
 * @author Till Thelet
 */

class AgentFlowWebSocket {
  constructor(options = {}) {
    this.url = options.url || `ws://${window.location.host}/agentflow/ws`;
    this.reconnectDelay = options.reconnectDelay || 3000;
    this.maxReconnectAttempts = options.maxReconnectAttempts || 10;
    
    this.ws = null;
    this.reconnectAttempts = 0;
    this.isConnected = false;
    this.clientId = null;
    
    // Event handlers
    this.handlers = {
      'task:created': [],
      'task:progress': [],
      'task:completed': [],
      'task:failed': [],
      'bot:status': [],
      'outcome:recorded': [],
      'connected': [],
      'disconnected': [],
      'error': []
    };
    
    // Auto-connect
    if (options.autoConnect !== false) {
      this.connect();
    }
  }
  
  /**
   * Connect to WebSocket server
   */
  connect() {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      console.log('[WS] Already connected');
      return;
    }
    
    console.log(`[WS] Connecting to ${this.url}...`);
    
    try {
      this.ws = new WebSocket(this.url);
      
      this.ws.onopen = () => {
        console.log('[WS] Connected');
        this.isConnected = true;
        this.reconnectAttempts = 0;
        
        // Subscribe to all events
        this.send({
          type: 'subscribe',
          events: ['*']
        });
      };
      
      this.ws.onmessage = (event) => {
        this.handleMessage(event.data);
      };
      
      this.ws.onclose = (event) => {
        console.log(`[WS] Disconnected (code: ${event.code})`);
        this.isConnected = false;
        this.clientId = null;
        
        this.emit('disconnected', { code: event.code, reason: event.reason });
        
        // Auto-reconnect
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++;
          console.log(`[WS] Reconnecting in ${this.reconnectDelay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})...`);
          setTimeout(() => this.connect(), this.reconnectDelay);
        } else {
          console.error('[WS] Max reconnection attempts reached');
        }
      };
      
      this.ws.onerror = (error) => {
        console.error('[WS] Error:', error);
        this.emit('error', { error });
      };
    } catch (error) {
      console.error('[WS] Connection failed:', error);
      this.emit('error', { error });
    }
  }
  
  /**
   * Disconnect from server
   */
  disconnect() {
    if (this.ws) {
      this.maxReconnectAttempts = 0; // Prevent auto-reconnect
      this.ws.close();
      this.ws = null;
    }
  }
  
  /**
   * Send message to server
   */
  send(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    } else {
      console.warn('[WS] Cannot send - not connected');
    }
  }
  
  /**
   * Handle incoming message
   */
  handleMessage(data) {
    try {
      const message = JSON.parse(data);
      
      // Special handling for connection message
      if (message.type === 'connected') {
        this.clientId = message.clientId;
        console.log(`[WS] Client ID: ${this.clientId}`);
        this.emit('connected', message);
        return;
      }
      
      // Emit event to handlers
      this.emit(message.type, message);
      
    } catch (error) {
      console.error('[WS] Invalid message:', error);
    }
  }
  
  /**
   * Register event handler
   */
  on(event, handler) {
    if (!this.handlers[event]) {
      this.handlers[event] = [];
    }
    this.handlers[event].push(handler);
    
    return () => this.off(event, handler); // Return unsubscribe function
  }
  
  /**
   * Remove event handler
   */
  off(event, handler) {
    if (this.handlers[event]) {
      this.handlers[event] = this.handlers[event].filter(h => h !== handler);
    }
  }
  
  /**
   * Emit event to handlers
   */
  emit(event, data) {
    if (this.handlers[event]) {
      this.handlers[event].forEach(handler => {
        try {
          handler(data);
        } catch (error) {
          console.error(`[WS] Handler error for ${event}:`, error);
        }
      });
    }
  }
  
  /**
   * Subscribe to specific events
   */
  subscribe(events) {
    this.send({
      type: 'subscribe',
      events: Array.isArray(events) ? events : [events]
    });
  }
  
  /**
   * Unsubscribe from specific events
   */
  unsubscribe(events) {
    this.send({
      type: 'unsubscribe',
      events: Array.isArray(events) ? events : [events]
    });
  }
  
  /**
   * Ping server (for keep-alive)
   */
  ping() {
    this.send({ type: 'ping' });
  }
  
  /**
   * Get connection status
   */
  getStatus() {
    return {
      isConnected: this.isConnected,
      clientId: this.clientId,
      reconnectAttempts: this.reconnectAttempts
    };
  }
}

// Export for use in dashboard
if (typeof window !== 'undefined') {
  window.AgentFlowWebSocket = AgentFlowWebSocket;
}

if (typeof module !== 'undefined') {
  module.exports = AgentFlowWebSocket;
}
