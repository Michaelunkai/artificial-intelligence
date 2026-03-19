/**
 * Bot Manager - Handles bot connections and message routing
 * @author Till Thelet
 */

class BotManager {
  constructor(gateway, db, logger) {
    this.gateway = gateway;
    this.db = db;
    this.logger = logger;
    this.bots = new Map();
    this.messageHandlers = [];
    
    this.init();
  }
  
  /**
   * Initialize bot manager
   */
  init() {
    this.logger.info('[BotManager] Initializing...');
    
    // Register known bots
    const knownBots = ['session2', 'openclaw', 'openclaw4', 'main'];
    knownBots.forEach(botId => this.registerBot(botId));
    
    // Listen for gateway messages
    if (this.gateway.messageHub) {
      this.gateway.messageHub.on('bot:message', this.handleBotMessage.bind(this));
    }
    
    // Start heartbeat monitor
    this.startHeartbeatMonitor();
    
    this.logger.info('[BotManager] Initialized');
  }
  
  /**
   * Register a bot
   */
  registerBot(botId) {
    if (this.bots.has(botId)) {
      return this.bots.get(botId);
    }
    
    const bot = {
      id: botId,
      status: 'idle',
      lastSeen: Date.now(),
      currentTask: null
    };
    
    this.bots.set(botId, bot);
    
    // Ensure bot exists in database
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO bot_status (bot_id, last_seen) VALUES (?, ?)
    `);
    stmt.run(botId, Date.now());
    
    this.logger.info(`[BotManager] Bot registered: ${botId}`);
    
    return bot;
  }
  
  /**
   * Send task to bot
   */
  async sendTaskToBot(botId, taskId, description) {
    const bot = this.bots.get(botId);
    if (!bot) {
      throw new Error(`Bot not found: ${botId}`);
    }
    
    try {
      // Update bot status
      bot.status = 'running';
      bot.currentTask = taskId;
      bot.lastSeen = Date.now();
      
      // Update database
      this.db.prepare(`
        UPDATE bot_status 
        SET status = 'running', current_task_id = ?, last_seen = ?
        WHERE bot_id = ?
      `).run(taskId, Date.now(), botId);
      
      // Send message via gateway
      if (this.gateway.sendToBotSession) {
        await this.gateway.sendToBotSession(botId, description);
      } else if (this.gateway.messageHub) {
        this.gateway.messageHub.emit('task:assign', {
          botId,
          taskId,
          description
        });
      } else {
        this.logger.warn(`[BotManager] No message transport available for bot: ${botId}`);
      }
      
      this.logger.info(`[BotManager] Task sent to ${botId}: ${taskId}`);
      
      return { success: true, botId, taskId };
    } catch (error) {
      this.logger.error(`[BotManager] Failed to send task to ${botId}:`, error);
      
      // Revert bot status
      bot.status = 'idle';
      bot.currentTask = null;
      
      throw error;
    }
  }
  
  /**
   * Handle incoming bot message
   */
  handleBotMessage(event) {
    const { botId, content, timestamp } = event;
    
    const bot = this.bots.get(botId);
    if (bot) {
      bot.lastSeen = timestamp || Date.now();
      
      // Update database heartbeat
      this.db.prepare(`
        UPDATE bot_status SET last_seen = ? WHERE bot_id = ?
      `).run(bot.lastSeen, botId);
    }
    
    // Parse progress updates
    if (content.includes('⚙️')) {
      this.handleProgressUpdate(botId, content);
    } else if (content.includes('✅')) {
      this.handleTaskCompletion(botId, content, 'completed');
    } else if (content.includes('❌') || content.includes('🛑')) {
      this.handleTaskCompletion(botId, content, 'failed');
    }
    
    // Notify message handlers
    this.messageHandlers.forEach(handler => {
      try {
        handler({ botId, content, timestamp: bot?.lastSeen });
      } catch (error) {
        this.logger.error('[BotManager] Message handler error:', error);
      }
    });
  }
  
  /**
   * Handle progress update
   */
  handleProgressUpdate(botId, content) {
    const bot = this.bots.get(botId);
    if (!bot || !bot.currentTask) return;
    
    // Update task progress in database
    this.db.prepare(`
      UPDATE tasks 
      SET progress = ?, status = 'running'
      WHERE id = ?
    `).run(content, bot.currentTask);
    
    this.logger.debug(`[BotManager] Progress update from ${botId}: ${content.substring(0, 50)}...`);
  }
  
  /**
   * Handle task completion
   */
  handleTaskCompletion(botId, content, status) {
    const bot = this.bots.get(botId);
    if (!bot || !bot.currentTask) return;
    
    const now = Date.now();
    
    // Update task status
    this.db.prepare(`
      UPDATE tasks 
      SET status = ?, completed_at = ?, result = ?
      WHERE id = ?
    `).run(status, now, content, bot.currentTask);
    
    // Update bot status
    bot.status = 'idle';
    const taskId = bot.currentTask;
    bot.currentTask = null;
    
    this.db.prepare(`
      UPDATE bot_status 
      SET status = 'idle', current_task_id = NULL 
      WHERE bot_id = ?
    `).run(botId);
    
    // Update bot statistics
    this.updateBotStatistics(botId, taskId, status);
    
    this.logger.info(`[BotManager] Task ${taskId} ${status} by ${botId}`);
  }
  
  /**
   * Update bot statistics after task completion
   */
  updateBotStatistics(botId, taskId, status) {
    const task = this.db.prepare('SELECT * FROM tasks WHERE id = ?').get(taskId);
    if (!task) return;
    
    const duration = task.started_at && task.completed_at
      ? (task.completed_at - task.started_at) / 1000
      : null;
    
    this.db.prepare(`
      UPDATE bot_status SET
        total_tasks = total_tasks + 1,
        successful_tasks = successful_tasks + CASE WHEN ? = 'completed' THEN 1 ELSE 0 END,
        failed_tasks = failed_tasks + CASE WHEN ? = 'failed' THEN 1 ELSE 0 END,
        avg_duration_seconds = CASE 
          WHEN ? IS NOT NULL THEN 
            ((avg_duration_seconds * total_tasks) + ?) / (total_tasks + 1)
          ELSE avg_duration_seconds
        END
      WHERE bot_id = ?
    `).run(status, status, duration, duration || 0, botId);
  }
  
  /**
   * Start heartbeat monitor (detects offline bots)
   */
  startHeartbeatMonitor() {
    setInterval(() => {
      const now = Date.now();
      const timeout = 60000; // 60 seconds
      
      this.bots.forEach((bot, botId) => {
        if (now - bot.lastSeen > timeout) {
          if (bot.status !== 'offline') {
            bot.status = 'offline';
            
            this.db.prepare(`
              UPDATE bot_status SET status = 'offline' WHERE bot_id = ?
            `).run(botId);
            
            this.logger.warn(`[BotManager] Bot went offline: ${botId}`);
          }
        } else if (bot.status === 'offline') {
          // Bot came back online
          bot.status = 'idle';
          
          this.db.prepare(`
            UPDATE bot_status SET status = 'idle' WHERE bot_id = ?
          `).run(botId);
          
          this.logger.info(`[BotManager] Bot came back online: ${botId}`);
        }
      });
    }, 10000); // Check every 10 seconds
  }
  
  /**
   * Register message handler
   */
  onMessage(handler) {
    this.messageHandlers.push(handler);
  }
  
  /**
   * Get bot status
   */
  getBotStatus(botId) {
    return this.bots.get(botId) || null;
  }
  
  /**
   * Get all bot statuses
   */
  getAllBotStatuses() {
    return Array.from(this.bots.entries()).map(([id, bot]) => ({
      id,
      ...bot
    }));
  }
  
  /**
   * Assign task to best available bot
   */
  autoAssignTask(description) {
    // Try skill-based assignment first
    const preferredBot = this.getPreferredBot(description);
    
    // Check if preferred bot is available
    const bot = this.bots.get(preferredBot);
    if (bot && bot.status === 'idle') {
      return preferredBot;
    }
    
    // Fallback: find any idle bot
    for (const [botId, bot] of this.bots) {
      if (bot.status === 'idle') {
        return botId;
      }
    }
    
    // No idle bots, assign to preferred anyway
    return preferredBot;
  }
  
  /**
   * Get preferred bot based on task description
   */
  getPreferredBot(description) {
    const lower = description.toLowerCase();
    
    const skillMap = {
      'browser': 'openclaw',
      'linkedin': 'session2',
      'job': 'session2',
      'apply': 'session2',
      'game': 'openclaw4',
      'download': 'openclaw4',
      'tv': 'openclaw4',
      'movie': 'openclaw4'
    };
    
    for (const [keyword, botId] of Object.entries(skillMap)) {
      if (lower.includes(keyword)) {
        return botId;
      }
    }
    
    return 'main'; // Default
  }
}

module.exports = BotManager;
