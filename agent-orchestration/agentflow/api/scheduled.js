/**
 * Scheduled Tasks API Module
 * Handles CRUD operations for scheduled/recurring tasks
 * @author Till Thelet
 */

module.exports = function(app, db, scheduler, logger) {
  const express = require('express');
  
  /**
   * Get all scheduled tasks
   * GET /agentflow/api/scheduled
   */
  app.get('/agentflow/api/scheduled', (req, res) => {
    try {
      const { enabled } = req.query;
      
      let query = 'SELECT * FROM scheduled_tasks';
      const params = [];
      
      if (enabled !== undefined) {
        query += ' WHERE enabled = ?';
        params.push(enabled === 'true' ? 1 : 0);
      }
      
      query += ' ORDER BY next_run ASC';
      
      const tasks = db.prepare(query).all(...params);
      
      // Add human-readable next_run
      tasks.forEach(task => {
        task.next_run_human = task.next_run 
          ? new Date(task.next_run).toLocaleString()
          : null;
        task.last_run_human = task.last_run 
          ? new Date(task.last_run).toLocaleString()
          : null;
      });
      
      res.json({ success: true, tasks, count: tasks.length });
    } catch (error) {
      logger.error('[Scheduled API] Get tasks failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get upcoming scheduled tasks
   * GET /agentflow/api/scheduled/upcoming
   */
  app.get('/agentflow/api/scheduled/upcoming', (req, res) => {
    try {
      const limit = parseInt(req.query.limit) || 10;
      const tasks = scheduler.getUpcoming(limit);
      
      tasks.forEach(task => {
        task.next_run_human = new Date(task.next_run).toLocaleString();
        task.time_until = formatTimeUntil(task.next_run);
      });
      
      res.json({ success: true, tasks });
    } catch (error) {
      logger.error('[Scheduled API] Get upcoming failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Create scheduled task
   * POST /agentflow/api/scheduled
   * Body: { description, schedule, bot_id?, enabled? }
   */
  app.post('/agentflow/api/scheduled', express.json(), (req, res) => {
    try {
      const { description, schedule, bot_id, enabled } = req.body;
      
      if (!description) {
        return res.status(400).json({ success: false, error: 'Description required' });
      }
      
      if (!schedule) {
        return res.status(400).json({ success: false, error: 'Schedule required' });
      }
      
      // Validate schedule format
      if (!isValidSchedule(schedule)) {
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid schedule format. Use: "every Xh", "daily at HH:MM", or cron format' 
        });
      }
      
      const task = scheduler.createScheduledTask({
        description,
        schedule,
        bot_id,
        enabled: enabled !== false
      });
      
      logger.info(`[Scheduled API] Created: ${task.id}`);
      
      res.status(201).json({ success: true, task });
    } catch (error) {
      logger.error('[Scheduled API] Create failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get single scheduled task
   * GET /agentflow/api/scheduled/:id
   */
  app.get('/agentflow/api/scheduled/:id', (req, res) => {
    try {
      const task = db.prepare('SELECT * FROM scheduled_tasks WHERE id = ?')
        .get(req.params.id);
      
      if (!task) {
        return res.status(404).json({ success: false, error: 'Scheduled task not found' });
      }
      
      task.next_run_human = task.next_run 
        ? new Date(task.next_run).toLocaleString()
        : null;
      
      // Get recent runs (tasks created from this schedule)
      task.recent_runs = db.prepare(`
        SELECT id, status, created_at, completed_at
        FROM tasks
        WHERE description LIKE ?
        ORDER BY created_at DESC
        LIMIT 5
      `).all(`[Scheduled] ${task.description}`);
      
      res.json({ success: true, task });
    } catch (error) {
      logger.error('[Scheduled API] Get task failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Update scheduled task
   * PATCH /agentflow/api/scheduled/:id
   */
  app.patch('/agentflow/api/scheduled/:id', express.json(), (req, res) => {
    try {
      const { description, schedule, bot_id, enabled } = req.body;
      
      const updates = {};
      if (description !== undefined) updates.description = description;
      if (schedule !== undefined) {
        if (!isValidSchedule(schedule)) {
          return res.status(400).json({ success: false, error: 'Invalid schedule format' });
        }
        updates.schedule = schedule;
      }
      if (bot_id !== undefined) updates.bot_id = bot_id;
      if (enabled !== undefined) updates.enabled = enabled;
      
      const task = scheduler.updateScheduledTask(req.params.id, updates);
      
      res.json({ success: true, task });
    } catch (error) {
      logger.error('[Scheduled API] Update failed:', error);
      res.status(error.message.includes('not found') ? 404 : 500)
        .json({ success: false, error: error.message });
    }
  });
  
  /**
   * Delete scheduled task
   * DELETE /agentflow/api/scheduled/:id
   */
  app.delete('/agentflow/api/scheduled/:id', (req, res) => {
    try {
      scheduler.deleteScheduledTask(req.params.id);
      res.json({ success: true, message: 'Scheduled task deleted' });
    } catch (error) {
      logger.error('[Scheduled API] Delete failed:', error);
      res.status(error.message.includes('not found') ? 404 : 500)
        .json({ success: false, error: error.message });
    }
  });
  
  /**
   * Pause scheduled task
   * POST /agentflow/api/scheduled/:id/pause
   */
  app.post('/agentflow/api/scheduled/:id/pause', (req, res) => {
    try {
      const task = scheduler.pauseTask(req.params.id);
      res.json({ success: true, task, message: 'Task paused' });
    } catch (error) {
      logger.error('[Scheduled API] Pause failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Resume scheduled task
   * POST /agentflow/api/scheduled/:id/resume
   */
  app.post('/agentflow/api/scheduled/:id/resume', (req, res) => {
    try {
      const task = scheduler.resumeTask(req.params.id);
      res.json({ success: true, task, message: 'Task resumed' });
    } catch (error) {
      logger.error('[Scheduled API] Resume failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Run scheduled task immediately
   * POST /agentflow/api/scheduled/:id/run
   */
  app.post('/agentflow/api/scheduled/:id/run', async (req, res) => {
    try {
      await scheduler.runNow(req.params.id);
      res.json({ success: true, message: 'Task triggered' });
    } catch (error) {
      logger.error('[Scheduled API] Run now failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
};

/**
 * Validate schedule format
 */
function isValidSchedule(schedule) {
  // Interval format: "every Xh", "every Xm", "every Xd"
  if (/^every\s+\d+(h|m|d)$/i.test(schedule)) {
    return true;
  }
  
  // Daily at time: "daily at HH:MM"
  if (/^daily\s+at\s+\d{1,2}:\d{2}$/i.test(schedule)) {
    return true;
  }
  
  // Cron format: "* * * * *"
  if (/^(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)\s+(\d+|\*)$/.test(schedule)) {
    return true;
  }
  
  return false;
}

/**
 * Format time until next run
 */
function formatTimeUntil(timestamp) {
  const now = Date.now();
  const diff = timestamp - now;
  
  if (diff < 0) return 'overdue';
  
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  
  if (days > 0) return `in ${days}d ${hours % 24}h`;
  if (hours > 0) return `in ${hours}h ${minutes % 60}m`;
  return `in ${minutes}m`;
}
