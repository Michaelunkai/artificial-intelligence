/**
 * Bot Management API Module
 * Handles bot status, health checks, and control
 * @author Till Thelet
 */

module.exports = function(app, db, logger) {
  const express = require('express');
  
  /**
   * Get all bot statuses
   * GET /agentflow/api/bots
   */
  app.get('/agentflow/api/bots', (req, res) => {
    try {
      const stmt = db.prepare(`
        SELECT 
          bs.*,
          (SELECT COUNT(*) FROM tasks WHERE bot_id = bs.bot_id AND status = 'running') as active_tasks
        FROM bot_status bs
        ORDER BY bs.bot_id
      `);
      
      const bots = stmt.all();
      
      // Check if bots are actually online (last_seen within 30 seconds)
      const now = Date.now();
      bots.forEach(bot => {
        if (bot.last_seen && (now - bot.last_seen) > 30000) {
          bot.status = 'offline';
        }
      });
      
      res.json({ success: true, bots, count: bots.length });
    } catch (error) {
      logger.error('[AgentFlow Bots] Get bots failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get single bot status
   * GET /agentflow/api/bots/:bot_id
   */
  app.get('/agentflow/api/bots/:bot_id', (req, res) => {
    try {
      const stmt = db.prepare(`
        SELECT 
          bs.*,
          (SELECT COUNT(*) FROM tasks WHERE bot_id = bs.bot_id AND status = 'running') as active_tasks,
          (SELECT COUNT(*) FROM tasks WHERE bot_id = bs.bot_id AND status = 'pending') as queued_tasks
        FROM bot_status bs
        WHERE bs.bot_id = ?
      `);
      
      const bot = stmt.get(req.params.bot_id);
      
      if (!bot) {
        return res.status(404).json({ success: false, error: 'Bot not found' });
      }
      
      // Get recent tasks for this bot
      const tasksStmt = db.prepare(`
        SELECT * FROM tasks 
        WHERE bot_id = ? 
        ORDER BY created_at DESC 
        LIMIT 10
      `);
      
      bot.recent_tasks = tasksStmt.all(bot.bot_id);
      
      res.json({ success: true, bot });
    } catch (error) {
      logger.error('[AgentFlow Bots] Get bot failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Update bot status (heartbeat endpoint)
   * POST /agentflow/api/bots/:bot_id/heartbeat
   * Body: { status?, current_task_id? }
   */
  app.post('/agentflow/api/bots/:bot_id/heartbeat', express.json(), (req, res) => {
    try {
      const { status, current_task_id } = req.body;
      const now = Date.now();
      
      const updates = ['last_seen = ?'];
      const params = [now];
      
      if (status) {
        updates.push('status = ?');
        params.push(status);
      }
      
      if (current_task_id !== undefined) {
        updates.push('current_task_id = ?');
        params.push(current_task_id);
      }
      
      params.push(req.params.bot_id);
      
      const stmt = db.prepare(`
        UPDATE bot_status SET ${updates.join(', ')} WHERE bot_id = ?
      `);
      
      const result = stmt.run(...params);
      
      if (result.changes === 0) {
        // Bot doesn't exist, create it
        const insertStmt = db.prepare(`
          INSERT INTO bot_status (bot_id, status, current_task_id, last_seen)
          VALUES (?, ?, ?, ?)
        `);
        
        insertStmt.run(
          req.params.bot_id,
          status || 'idle',
          current_task_id || null,
          now
        );
        
        logger.info(`[AgentFlow Bots] New bot registered: ${req.params.bot_id}`);
      }
      
      res.json({ success: true, message: 'Heartbeat received' });
    } catch (error) {
      logger.error('[AgentFlow Bots] Heartbeat failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Reset bot statistics
   * POST /agentflow/api/bots/:bot_id/reset-stats
   */
  app.post('/agentflow/api/bots/:bot_id/reset-stats', (req, res) => {
    try {
      const stmt = db.prepare(`
        UPDATE bot_status SET
          total_tasks = 0,
          successful_tasks = 0,
          failed_tasks = 0,
          avg_duration_seconds = 0
        WHERE bot_id = ?
      `);
      
      const result = stmt.run(req.params.bot_id);
      
      if (result.changes === 0) {
        return res.status(404).json({ success: false, error: 'Bot not found' });
      }
      
      logger.info(`[AgentFlow Bots] Stats reset for: ${req.params.bot_id}`);
      
      res.json({ success: true, message: 'Bot statistics reset' });
    } catch (error) {
      logger.error('[AgentFlow Bots] Reset stats failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get bot health summary
   * GET /agentflow/api/bots/health/summary
   */
  app.get('/agentflow/api/bots/health/summary', (req, res) => {
    try {
      const summary = {
        total_bots: 0,
        online: 0,
        idle: 0,
        running: 0,
        offline: 0,
        error: 0
      };
      
      const stmt = db.prepare('SELECT * FROM bot_status');
      const bots = stmt.all();
      
      summary.total_bots = bots.length;
      
      const now = Date.now();
      bots.forEach(bot => {
        // Check if online (heartbeat within 30s)
        if (bot.last_seen && (now - bot.last_seen) <= 30000) {
          summary.online++;
          
          if (bot.status === 'idle') summary.idle++;
          else if (bot.status === 'running') summary.running++;
          else if (bot.status === 'error') summary.error++;
        } else {
          summary.offline++;
        }
      });
      
      res.json({ success: true, health: summary });
    } catch (error) {
      logger.error('[AgentFlow Bots] Health summary failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get bot comparison (performance metrics)
   * GET /agentflow/api/bots/compare
   */
  app.get('/agentflow/api/bots/compare', (req, res) => {
    try {
      const stmt = db.prepare(`
        SELECT 
          bot_id,
          total_tasks,
          successful_tasks,
          failed_tasks,
          ROUND(
            CAST(successful_tasks AS REAL) / NULLIF(total_tasks, 0) * 100,
            2
          ) as success_rate,
          avg_duration_seconds,
          last_seen,
          status
        FROM bot_status
        ORDER BY total_tasks DESC
      `);
      
      const bots = stmt.all();
      
      // Calculate rankings
      const rankings = {
        most_productive: bots[0]?.bot_id || null,
        highest_success_rate: bots.sort((a, b) => (b.success_rate || 0) - (a.success_rate || 0))[0]?.bot_id || null,
        fastest: bots.sort((a, b) => (a.avg_duration_seconds || Infinity) - (b.avg_duration_seconds || Infinity))[0]?.bot_id || null
      };
      
      res.json({ success: true, bots, rankings });
    } catch (error) {
      logger.error('[AgentFlow Bots] Compare bots failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Delete bot (admin only)
   * DELETE /agentflow/api/bots/:bot_id
   */
  app.delete('/agentflow/api/bots/:bot_id', (req, res) => {
    try {
      // Check admin token
      const adminToken = req.headers['x-admin-token'] || req.headers['authorization'];
      if (adminToken !== process.env.OPENCLAW_ADMIN_TOKEN && adminToken !== 'agentflow-dev-token') {
        return res.status(401).json({ success: false, error: 'Unauthorized' });
      }
      
      // Delete bot status
      const stmt = db.prepare('DELETE FROM bot_status WHERE bot_id = ?');
      const result = stmt.run(req.params.bot_id);
      
      if (result.changes === 0) {
        return res.status(404).json({ success: false, error: 'Bot not found' });
      }
      
      // Optionally delete associated tasks
      if (req.query.delete_tasks === 'true') {
        db.prepare('DELETE FROM tasks WHERE bot_id = ?').run(req.params.bot_id);
      }
      
      logger.info(`[AgentFlow Bots] Bot deleted: ${req.params.bot_id}`);
      
      res.json({ success: true, message: 'Bot deleted' });
    } catch (error) {
      logger.error('[AgentFlow Bots] Delete bot failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
};
