/**
 * Task Scheduler for AgentFlow
 * Handles scheduled/recurring tasks
 * @author Till Thelet
 */

const { v4: uuidv4 } = require('uuid');

class Scheduler {
  constructor(db, botManager, logger) {
    this.db = db;
    this.botManager = botManager;
    this.logger = logger;
    
    this.jobs = new Map();
    this.timers = new Map();
    
    this.init();
  }
  
  /**
   * Initialize scheduler
   */
  init() {
    this.logger.info('[Scheduler] Initializing...');
    
    // Create scheduled_tasks table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS scheduled_tasks (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        bot_id TEXT,
        schedule TEXT NOT NULL,
        next_run INTEGER,
        last_run INTEGER,
        run_count INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        created_at INTEGER
      );
      
      CREATE INDEX IF NOT EXISTS idx_scheduled_next ON scheduled_tasks(next_run);
    `);
    
    // Load existing jobs
    this.loadJobs();
    
    // Start scheduler loop (check every minute)
    this.schedulerInterval = setInterval(() => {
      this.checkDueTasks();
    }, 60000);
    
    // Initial check
    this.checkDueTasks();
    
    this.logger.info('[Scheduler] Initialized');
  }
  
  /**
   * Load scheduled jobs from database
   */
  loadJobs() {
    const jobs = this.db.prepare(`
      SELECT * FROM scheduled_tasks WHERE enabled = 1
    `).all();
    
    jobs.forEach(job => {
      this.jobs.set(job.id, job);
    });
    
    this.logger.info(`[Scheduler] Loaded ${jobs.length} scheduled tasks`);
  }
  
  /**
   * Create a scheduled task
   */
  createScheduledTask(options) {
    const {
      description,
      bot_id,
      schedule, // cron-like: "0 9 * * *" or interval: "every 6h"
      enabled = true
    } = options;
    
    if (!description || !schedule) {
      throw new Error('Description and schedule are required');
    }
    
    const id = uuidv4();
    const now = Date.now();
    const nextRun = this.calculateNextRun(schedule);
    
    const stmt = this.db.prepare(`
      INSERT INTO scheduled_tasks (id, description, bot_id, schedule, next_run, enabled, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    
    stmt.run(id, description, bot_id, schedule, nextRun, enabled ? 1 : 0, now);
    
    const job = {
      id,
      description,
      bot_id,
      schedule,
      next_run: nextRun,
      last_run: null,
      run_count: 0,
      enabled: enabled ? 1 : 0,
      created_at: now
    };
    
    this.jobs.set(id, job);
    
    this.logger.info(`[Scheduler] Created scheduled task: ${id}`);
    
    return job;
  }
  
  /**
   * Update a scheduled task
   */
  updateScheduledTask(id, updates) {
    const job = this.jobs.get(id);
    if (!job) {
      throw new Error('Scheduled task not found');
    }
    
    const allowedFields = ['description', 'bot_id', 'schedule', 'enabled'];
    const setClause = [];
    const params = [];
    
    for (const [key, value] of Object.entries(updates)) {
      if (allowedFields.includes(key)) {
        setClause.push(`${key} = ?`);
        params.push(key === 'enabled' ? (value ? 1 : 0) : value);
      }
    }
    
    if (setClause.length === 0) {
      return job;
    }
    
    // Recalculate next_run if schedule changed
    if (updates.schedule) {
      setClause.push('next_run = ?');
      params.push(this.calculateNextRun(updates.schedule));
    }
    
    params.push(id);
    
    this.db.prepare(`
      UPDATE scheduled_tasks SET ${setClause.join(', ')} WHERE id = ?
    `).run(...params);
    
    // Reload job
    const updatedJob = this.db.prepare('SELECT * FROM scheduled_tasks WHERE id = ?').get(id);
    this.jobs.set(id, updatedJob);
    
    this.logger.info(`[Scheduler] Updated scheduled task: ${id}`);
    
    return updatedJob;
  }
  
  /**
   * Delete a scheduled task
   */
  deleteScheduledTask(id) {
    const job = this.jobs.get(id);
    if (!job) {
      throw new Error('Scheduled task not found');
    }
    
    this.db.prepare('DELETE FROM scheduled_tasks WHERE id = ?').run(id);
    this.jobs.delete(id);
    
    // Clear any pending timer
    if (this.timers.has(id)) {
      clearTimeout(this.timers.get(id));
      this.timers.delete(id);
    }
    
    this.logger.info(`[Scheduler] Deleted scheduled task: ${id}`);
  }
  
  /**
   * Get all scheduled tasks
   */
  getScheduledTasks() {
    return this.db.prepare(`
      SELECT * FROM scheduled_tasks ORDER BY next_run ASC
    `).all();
  }
  
  /**
   * Check for due tasks and execute them
   */
  async checkDueTasks() {
    const now = Date.now();
    
    const dueTasks = this.db.prepare(`
      SELECT * FROM scheduled_tasks 
      WHERE enabled = 1 AND next_run <= ?
    `).all(now);
    
    for (const job of dueTasks) {
      await this.executeScheduledTask(job);
    }
  }
  
  /**
   * Execute a scheduled task
   */
  async executeScheduledTask(job) {
    const now = Date.now();
    
    this.logger.info(`[Scheduler] Executing scheduled task: ${job.description}`);
    
    try {
      // Create actual task
      const taskId = uuidv4();
      const assignedBot = job.bot_id || this.botManager.autoAssignTask(job.description);
      
      this.db.prepare(`
        INSERT INTO tasks (id, description, bot_id, status, created_at)
        VALUES (?, ?, ?, 'pending', ?)
      `).run(taskId, `[Scheduled] ${job.description}`, assignedBot, now);
      
      // Send to bot
      if (this.botManager) {
        await this.botManager.sendTaskToBot(assignedBot, taskId, job.description);
      }
      
      // Update scheduled task
      const nextRun = this.calculateNextRun(job.schedule);
      
      this.db.prepare(`
        UPDATE scheduled_tasks 
        SET last_run = ?, next_run = ?, run_count = run_count + 1
        WHERE id = ?
      `).run(now, nextRun, job.id);
      
      // Update in-memory job
      job.last_run = now;
      job.next_run = nextRun;
      job.run_count++;
      this.jobs.set(job.id, job);
      
      this.logger.info(`[Scheduler] Task executed, next run: ${new Date(nextRun).toISOString()}`);
    } catch (error) {
      this.logger.error(`[Scheduler] Failed to execute task: ${error.message}`);
    }
  }
  
  /**
   * Calculate next run time from schedule
   */
  calculateNextRun(schedule) {
    const now = Date.now();
    
    // Simple interval format: "every Xh", "every Xm", "every Xd"
    const intervalMatch = schedule.match(/^every\s+(\d+)(h|m|d)$/i);
    if (intervalMatch) {
      const value = parseInt(intervalMatch[1]);
      const unit = intervalMatch[2].toLowerCase();
      
      let ms;
      switch (unit) {
        case 'm': ms = value * 60 * 1000; break;
        case 'h': ms = value * 60 * 60 * 1000; break;
        case 'd': ms = value * 24 * 60 * 60 * 1000; break;
      }
      
      return now + ms;
    }
    
    // Daily at specific time: "daily at 9:00", "daily at 14:30"
    const dailyMatch = schedule.match(/^daily\s+at\s+(\d{1,2}):(\d{2})$/i);
    if (dailyMatch) {
      const hour = parseInt(dailyMatch[1]);
      const minute = parseInt(dailyMatch[2]);
      
      const target = new Date();
      target.setHours(hour, minute, 0, 0);
      
      // If target time has passed today, schedule for tomorrow
      if (target.getTime() <= now) {
        target.setDate(target.getDate() + 1);
      }
      
      return target.getTime();
    }
    
    // Simplified cron: "0 9 * * *" (minute hour day month weekday)
    const cronMatch = schedule.match(/^(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)$/);
    if (cronMatch) {
      const [, minute, hour, day, month, weekday] = cronMatch;
      
      const target = new Date();
      
      if (hour !== '*') {
        target.setHours(parseInt(hour));
      }
      if (minute !== '*') {
        target.setMinutes(parseInt(minute));
      }
      target.setSeconds(0);
      target.setMilliseconds(0);
      
      // If target time has passed, move to next occurrence
      while (target.getTime() <= now) {
        target.setDate(target.getDate() + 1);
      }
      
      return target.getTime();
    }
    
    // Default: 24 hours from now
    this.logger.warn(`[Scheduler] Unknown schedule format: ${schedule}, defaulting to 24h`);
    return now + (24 * 60 * 60 * 1000);
  }
  
  /**
   * Get upcoming scheduled tasks
   */
  getUpcoming(limit = 10) {
    return this.db.prepare(`
      SELECT * FROM scheduled_tasks 
      WHERE enabled = 1 
      ORDER BY next_run ASC 
      LIMIT ?
    `).all(limit);
  }
  
  /**
   * Pause a scheduled task
   */
  pauseTask(id) {
    return this.updateScheduledTask(id, { enabled: false });
  }
  
  /**
   * Resume a scheduled task
   */
  resumeTask(id) {
    return this.updateScheduledTask(id, { enabled: true });
  }
  
  /**
   * Run a scheduled task immediately
   */
  async runNow(id) {
    const job = this.jobs.get(id);
    if (!job) {
      throw new Error('Scheduled task not found');
    }
    
    await this.executeScheduledTask(job);
  }
  
  /**
   * Clean up
   */
  destroy() {
    if (this.schedulerInterval) {
      clearInterval(this.schedulerInterval);
    }
    
    this.timers.forEach(timer => clearTimeout(timer));
    this.timers.clear();
    
    this.logger.info('[Scheduler] Destroyed');
  }
}

module.exports = Scheduler;
