/**
 * WebSocket Server for Real-Time Updates
 * Provides push-based updates instead of polling
 * @author Till Thelet
 */

const WebSocket = require('ws');

class WebSocketServer {
  constructor(server, logger) {
    this.logger = logger;
    this.clients = new Set();
    this.wss = null;
    
    if (server) {
      this.init(server);
    }
  }
  
  /**
   * Initialize WebSocket server
   */
  init(server) {
    this.wss = new WebSocket.Server({
      server,
      path: '/agentflow/ws'
    });
    
    this.wss.on('connection', (ws, req) => {
      const clientId = Math.random().toString(36).substring(7);
      
      this.logger.info(`[WebSocket] Client connected: ${clientId}`);
      
      // Add to clients
      ws.clientId = clientId;
      ws.isAlive = true;
      this.clients.add(ws);
      
      // Send welcome message
      this.send(ws, {
        type: 'connected',
        clientId,
        timestamp: Date.now()
      });
      
      // Handle incoming messages
      ws.on('message', (data) => {
        this.handleMessage(ws, data);
      });
      
      // Handle pong (heartbeat response)
      ws.on('pong', () => {
        ws.isAlive = true;
      });
      
      // Handle close
      ws.on('close', () => {
        this.logger.info(`[WebSocket] Client disconnected: ${clientId}`);
        this.clients.delete(ws);
      });
      
      // Handle errors
      ws.on('error', (error) => {
        this.logger.error(`[WebSocket] Client error (${clientId}):`, error);
        this.clients.delete(ws);
      });
    });
    
    // Start heartbeat interval (ping clients every 30 seconds)
    this.heartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
          this.clients.delete(ws);
          return ws.terminate();
        }
        
        ws.isAlive = false;
        ws.ping();
      });
    }, 30000);
    
    this.logger.info('[WebSocket] Server initialized on /agentflow/ws');
  }
  
  /**
   * Handle incoming message from client
   */
  handleMessage(ws, data) {
    try {
      const message = JSON.parse(data.toString());
      
      switch (message.type) {
        case 'ping':
          this.send(ws, { type: 'pong', timestamp: Date.now() });
          break;
          
        case 'subscribe':
          // Subscribe to specific events
          ws.subscriptions = ws.subscriptions || new Set();
          if (message.events) {
            message.events.forEach(event => ws.subscriptions.add(event));
          }
          this.send(ws, {
            type: 'subscribed',
            events: Array.from(ws.subscriptions)
          });
          break;
          
        case 'unsubscribe':
          // Unsubscribe from events
          if (ws.subscriptions && message.events) {
            message.events.forEach(event => ws.subscriptions.delete(event));
          }
          break;
          
        default:
          this.logger.debug(`[WebSocket] Unknown message type: ${message.type}`);
      }
    } catch (error) {
      this.logger.error('[WebSocket] Invalid message:', error);
    }
  }
  
  /**
   * Send message to single client
   */
  send(ws, data) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data));
    }
  }
  
  /**
   * Broadcast message to all clients
   */
  broadcast(data, eventType = null) {
    const message = JSON.stringify(data);
    
    this.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        // Check if client is subscribed to this event type
        if (eventType && client.subscriptions) {
          if (!client.subscriptions.has(eventType) && !client.subscriptions.has('*')) {
            return; // Skip if not subscribed
          }
        }
        
        client.send(message);
      }
    });
  }
  
  /**
   * Notify clients of task creation
   */
  taskCreated(task) {
    this.broadcast({
      type: 'task:created',
      task,
      timestamp: Date.now()
    }, 'task:created');
  }
  
  /**
   * Notify clients of task progress update
   */
  taskProgress(taskId, progress, botId) {
    this.broadcast({
      type: 'task:progress',
      taskId,
      botId,
      progress,
      timestamp: Date.now()
    }, 'task:progress');
  }
  
  /**
   * Notify clients of task completion
   */
  taskCompleted(task) {
    this.broadcast({
      type: 'task:completed',
      task,
      timestamp: Date.now()
    }, 'task:completed');
  }
  
  /**
   * Notify clients of task failure
   */
  taskFailed(task) {
    this.broadcast({
      type: 'task:failed',
      task,
      timestamp: Date.now()
    }, 'task:failed');
  }
  
  /**
   * Notify clients of bot status change
   */
  botStatusChanged(botId, status, currentTaskId = null) {
    this.broadcast({
      type: 'bot:status',
      botId,
      status,
      currentTaskId,
      timestamp: Date.now()
    }, 'bot:status');
  }
  
  /**
   * Notify clients of new outcome recorded
   */
  outcomeRecorded(outcome) {
    this.broadcast({
      type: 'outcome:recorded',
      outcome,
      timestamp: Date.now()
    }, 'outcome:recorded');
  }
  
  /**
   * Get connection stats
   */
  getStats() {
    return {
      connectedClients: this.clients.size,
      uptime: process.uptime()
    };
  }
  
  /**
   * Close server
   */
  close() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    
    if (this.wss) {
      this.wss.close();
    }
    
    this.logger.info('[WebSocket] Server closed');
  }
}

module.exports = WebSocketServer;
