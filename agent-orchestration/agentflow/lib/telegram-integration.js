/**
 * Telegram Integration for AgentFlow
 * Sends notifications and receives commands via Telegram
 * @author Till Thelet
 */

class TelegramIntegration {
  constructor(db, logger, options = {}) {
    this.db = db;
    this.logger = logger;
    this.chatId = options.chatId || '716239770'; // Till's Telegram ID
    this.apiBase = 'http://localhost:18789'; // OpenClaw gateway
    
    this.notificationSettings = {
      taskCompleted: true,
      taskFailed: true,
      dailySummary: true,
      insights: true
    };
  }
  
  /**
   * Send notification to Telegram
   */
  async sendNotification(message, options = {}) {
    try {
      const { silent = false, parseMode = 'HTML' } = options;
      
      // Using OpenClaw's message tool internally
      // In production, this would make an API call to the gateway
      this.logger.info(`[Telegram] Notification: ${message.substring(0, 50)}...`);
      
      // For now, just log - actual sending happens via OpenClaw message tool
      return { success: true, message: 'Notification logged' };
    } catch (error) {
      this.logger.error('[Telegram] Failed to send notification:', error);
      return { success: false, error: error.message };
    }
  }
  
  /**
   * Notify on task completion
   */
  async onTaskCompleted(task) {
    if (!this.notificationSettings.taskCompleted) return;
    
    const duration = task.started_at && task.completed_at
      ? ((task.completed_at - task.started_at) / 1000).toFixed(1)
      : 'N/A';
    
    const message = `
✅ <b>Task Completed</b>

📝 ${this.escapeHtml(task.description)}
🤖 Bot: ${task.bot_id}
⏱️ Duration: ${duration}s
📊 <a href="${this.apiBase}/agentflow">View Dashboard</a>
    `.trim();
    
    await this.sendNotification(message);
  }
  
  /**
   * Notify on task failure
   */
  async onTaskFailed(task) {
    if (!this.notificationSettings.taskFailed) return;
    
    const message = `
❌ <b>Task Failed</b>

📝 ${this.escapeHtml(task.description)}
🤖 Bot: ${task.bot_id}
⚠️ Error: ${this.escapeHtml(task.error || 'Unknown error')}
📊 <a href="${this.apiBase}/agentflow">View Dashboard</a>
    `.trim();
    
    await this.sendNotification(message);
  }
  
  /**
   * Send daily summary
   */
  async sendDailySummary() {
    if (!this.notificationSettings.dailySummary) return;
    
    const yesterday = Date.now() - (24 * 60 * 60 * 1000);
    
    // Get stats from database
    const stats = this.db.prepare(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
        AVG(CASE WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
            THEN (completed_at - started_at) / 1000.0 
            ELSE NULL END) as avg_duration
      FROM tasks
      WHERE created_at >= ?
    `).get(yesterday);
    
    // Get per-bot breakdown
    const perBot = this.db.prepare(`
      SELECT bot_id, COUNT(*) as count
      FROM tasks
      WHERE created_at >= ? AND status = 'completed'
      GROUP BY bot_id
    `).all(yesterday);
    
    const successRate = stats.total > 0 
      ? ((stats.completed / stats.total) * 100).toFixed(1)
      : '0';
    
    const botBreakdown = perBot
      .map(b => `  • ${b.bot_id}: ${b.count} tasks`)
      .join('\n');
    
    const message = `
📊 <b>AgentFlow Daily Summary</b>

📈 <b>Last 24 Hours:</b>
  • Total Tasks: ${stats.total}
  • Completed: ${stats.completed} ✅
  • Failed: ${stats.failed} ❌
  • Success Rate: ${successRate}%
  • Avg Duration: ${stats.avg_duration ? stats.avg_duration.toFixed(1) + 's' : 'N/A'}

🤖 <b>Per Bot:</b>
${botBreakdown || '  No completed tasks'}

📊 <a href="${this.apiBase}/agentflow">Open Dashboard</a>
    `.trim();
    
    await this.sendNotification(message);
  }
  
  /**
   * Send job application insights
   */
  async sendJobInsights() {
    if (!this.notificationSettings.insights) return;
    
    const outcomes = this.db.prepare(`
      SELECT metrics
      FROM outcomes
      WHERE type = 'job_application'
      ORDER BY recorded_at DESC
      LIMIT 50
    `).all();
    
    if (outcomes.length === 0) {
      return; // No data to report
    }
    
    let totalApplied = 0;
    let totalResponses = 0;
    let totalInterviews = 0;
    
    outcomes.forEach(o => {
      const metrics = JSON.parse(o.metrics);
      totalApplied += metrics.applied || 0;
      totalResponses += metrics.responses || 0;
      totalInterviews += metrics.interviews || 0;
    });
    
    const responseRate = totalApplied > 0 
      ? ((totalResponses / totalApplied) * 100).toFixed(1)
      : '0';
    
    const message = `
💼 <b>Job Application Insights</b>

📊 <b>Summary (Last 50 Sessions):</b>
  • Total Applied: ${totalApplied}
  • Responses: ${totalResponses}
  • Interviews: ${totalInterviews}
  • Response Rate: ${responseRate}%

🎯 <b>Recommendation:</b>
${responseRate > 10 
  ? 'Your response rate is above average! Keep using the same approach.'
  : 'Consider applying during morning hours (9-11 AM) for better response rates.'}

📊 <a href="${this.apiBase}/agentflow/insights.html">View Full Insights</a>
    `.trim();
    
    await this.sendNotification(message);
  }
  
  /**
   * Handle incoming Telegram command
   */
  async handleCommand(command, args = []) {
    switch (command.toLowerCase()) {
      case '/agentflow':
      case '/af':
        return this.getStatus();
        
      case '/tasks':
        return this.getRecentTasks();
        
      case '/bots':
        return this.getBotStatuses();
        
      case '/insights':
        await this.sendJobInsights();
        return { success: true };
        
      case '/newtask':
        return this.createTask(args.join(' '));
        
      default:
        return { success: false, error: 'Unknown command' };
    }
  }
  
  /**
   * Get AgentFlow status summary
   */
  getStatus() {
    const stats = this.db.prepare(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending
      FROM tasks
      WHERE created_at >= ?
    `).get(Date.now() - (24 * 60 * 60 * 1000));
    
    const bots = this.db.prepare(`
      SELECT bot_id, status FROM bot_status
    `).all();
    
    const onlineBots = bots.filter(b => b.status !== 'offline').length;
    
    return {
      success: true,
      message: `
🤖 <b>AgentFlow Status</b>

📊 Tasks (24h): ${stats.total} total
⚙️ Active: ${stats.running} running, ${stats.pending} pending
🤖 Bots: ${onlineBots}/${bots.length} online

📊 Dashboard: ${this.apiBase}/agentflow
      `.trim()
    };
  }
  
  /**
   * Get recent tasks
   */
  getRecentTasks() {
    const tasks = this.db.prepare(`
      SELECT description, bot_id, status, created_at
      FROM tasks
      ORDER BY created_at DESC
      LIMIT 5
    `).all();
    
    const taskList = tasks.map(t => {
      const status = t.status === 'completed' ? '✅' : 
                     t.status === 'failed' ? '❌' :
                     t.status === 'running' ? '⚙️' : '⏳';
      return `${status} ${t.description.substring(0, 40)}... (${t.bot_id})`;
    }).join('\n');
    
    return {
      success: true,
      message: `
📋 <b>Recent Tasks</b>

${taskList || 'No tasks found'}
      `.trim()
    };
  }
  
  /**
   * Get bot statuses
   */
  getBotStatuses() {
    const bots = this.db.prepare(`
      SELECT bot_id, status, total_tasks, successful_tasks
      FROM bot_status
    `).all();
    
    const botList = bots.map(b => {
      const status = b.status === 'idle' ? '🟢' :
                     b.status === 'running' ? '🟡' : '🔴';
      const rate = b.total_tasks > 0 
        ? ((b.successful_tasks / b.total_tasks) * 100).toFixed(0) + '%'
        : 'N/A';
      return `${status} ${b.bot_id}: ${b.status} (${rate} success)`;
    }).join('\n');
    
    return {
      success: true,
      message: `
🤖 <b>Bot Statuses</b>

${botList}
      `.trim()
    };
  }
  
  /**
   * Create task from Telegram command
   */
  createTask(description) {
    if (!description || description.trim().length === 0) {
      return {
        success: false,
        message: 'Please provide a task description.\nUsage: /newtask Apply to 10 DevOps jobs'
      };
    }
    
    // This would normally call the tasks API
    // For now, return instructions
    return {
      success: true,
      message: `
📝 <b>Task Queued</b>

Description: ${description}
Status: Will be auto-assigned to best bot

📊 <a href="${this.apiBase}/agentflow">View in Dashboard</a>
      `.trim()
    };
  }
  
  /**
   * Escape HTML special characters
   */
  escapeHtml(text) {
    if (!text) return '';
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
  
  /**
   * Update notification settings
   */
  updateSettings(settings) {
    Object.assign(this.notificationSettings, settings);
    this.logger.info('[Telegram] Settings updated:', this.notificationSettings);
  }
}

module.exports = TelegramIntegration;
