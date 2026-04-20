/**
 * Task Management API Module
 * Handles CRUD operations for tasks
 * @author Till Thelet
 */

module.exports = function(app, db, logger) {
  const express = require('express');
  
  /**
   * Get all tasks with optional filtering
   * GET /agentflow/api/tasks?status=running&bot=session2&limit=50
   */
  app.get('/agentflow/api/tasks', (req, res) => {
    try {
      const { status, bot, limit = 50 } = req.query;
      
      let query = 'SELECT * FROM tasks WHERE 1=1';
      const params = [];
      
      if (status) {
        query += ' AND status = ?';
        params.push(status);
      }
      
      if (bot) {
        query += ' AND bot_id = ?';
        params.push(bot);
      }
      
      query += ' ORDER BY created_at DESC LIMIT ?';
      params.push(parseInt(limit));
      
      const stmt = db.prepare(query);
      const tasks = stmt.all(...params);
      
      res.json({ success: true, tasks, count: tasks.length });
    } catch (error) {
      logger.error('[AgentFlow Tasks] Get tasks failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get single task by ID
   * GET /agentflow/api/tasks/:id
   */
  app.get('/agentflow/api/tasks/:id', (req, res) => {
    try {
      const stmt = db.prepare('SELECT * FROM tasks WHERE id = ?');
      const task = stmt.get(req.params.id);
      
      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      
      // Also fetch associated outcome if exists
      const outcomeStmt = db.prepare('SELECT * FROM outcomes WHERE task_id = ?');
      const outcome = outcomeStmt.get(task.id);
      
      if (outcome) {
        outcome.metrics = JSON.parse(outcome.metrics);
        task.outcome = outcome;
      }
      
      res.json({ success: true, task });
    } catch (error) {
      logger.error('[AgentFlow Tasks] Get task failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Create new task
   * POST /agentflow/api/tasks
   * Body: { description, bot_id? }
   */
  app.post('/agentflow/api/tasks', express.json(), (req, res) => {
    try {
      const { description, bot_id } = req.body;
      
      if (!description || description.trim().length === 0) {
        return res.status(400).json({ success: false, error: 'Description required' });
      }
      
      // Auto-assign bot if not specified
      let assignedBot = bot_id;
      if (!assignedBot) {
        assignedBot = autoAssignBot(description);
      }
      
      const taskId = require('uuid').v4();
      const now = Date.now();
      
      const stmt = db.prepare(`
        INSERT INTO tasks (id, description, bot_id, status, created_at)
        VALUES (?, ?, ?, 'pending', ?)
      `);
      
      stmt.run(taskId, description.trim(), assignedBot, now);
      
      logger.info(`[AgentFlow Tasks] Task created: ${taskId} -> ${assignedBot}`);
      
      res.status(201).json({
        success: true,
        task: {
          id: taskId,
          description: description.trim(),
          bot_id: assignedBot,
          status: 'pending',
          created_at: now
        }
      });
    } catch (error) {
      logger.error('[AgentFlow Tasks] Create task failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Update task progress/status
   * PATCH /agentflow/api/tasks/:id
   * Body: { status?, progress?, result?, error? }
   */
  app.patch('/agentflow/api/tasks/:id', express.json(), (req, res) => {
    try {
      const { status, progress, result, error } = req.body;
      const now = Date.now();
      
      const updates = [];
      const params = [];
      
      if (status !== undefined) {
        updates.push('status = ?');
        params.push(status);
        
        // Auto-set timestamps based on status
        if (status === 'running') {
          updates.push('started_at = COALESCE(started_at, ?)');
          params.push(now);
        } else if (status === 'completed' || status === 'failed') {
          updates.push('completed_at = ?');
          params.push(now);
        }
      }
      
      if (progress !== undefined) {
        updates.push('progress = ?');
        params.push(progress);
      }
      
      if (result !== undefined) {
        updates.push('result = ?');
        params.push(result);
      }
      
      if (error !== undefined) {
        updates.push('error = ?');
        params.push(error);
      }
      
      if (updates.length === 0) {
        return res.status(400).json({ success: false, error: 'No updates provided' });
      }
      
      params.push(req.params.id);
      
      const stmt = db.prepare(`
        UPDATE tasks SET ${updates.join(', ')} WHERE id = ?
      `);
      
      const result = stmt.run(...params);
      
      if (result.changes === 0) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      
      // Update bot status if task completed/failed
      if (status === 'completed' || status === 'failed') {
        updateBotStats(db, req.params.id);
      }
      
      res.json({ success: true, message: 'Task updated' });
    } catch (error) {
      logger.error('[AgentFlow Tasks] Update task failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Delete task
   * DELETE /agentflow/api/tasks/:id
   */
  app.delete('/agentflow/api/tasks/:id', (req, res) => {
    try {
      // First delete associated outcomes
      db.prepare('DELETE FROM outcomes WHERE task_id = ?').run(req.params.id);
      
      // Then delete task
      const stmt = db.prepare('DELETE FROM tasks WHERE id = ?');
      const result = stmt.run(req.params.id);
      
      if (result.changes === 0) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      
      logger.info(`[AgentFlow Tasks] Task deleted: ${req.params.id}`);
      
      res.json({ success: true, message: 'Task deleted' });
    } catch (error) {
      logger.error('[AgentFlow Tasks] Delete task failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Export tasks to CSV
   * GET /agentflow/api/tasks/export/csv
   */
  app.get('/agentflow/api/tasks/export/csv', (req, res) => {
    try {
      const stmt = db.prepare('SELECT * FROM tasks ORDER BY created_at DESC');
      const tasks = stmt.all();
      
      const csv = tasksToCSV(tasks);
      
      res.setHeader('Content-Type', 'text/csv');
      res.setHeader('Content-Disposition', 'attachment; filename=agentflow-tasks.csv');
      res.send(csv);
    } catch (error) {
      logger.error('[AgentFlow Tasks] Export CSV failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
};

/**
 * Auto-assign task to best bot based on description keywords
 */
function autoAssignBot(description) {
  const lower = description.toLowerCase();
  
  const skillMap = {
    'browser': ['openclaw'],
    'linkedin': ['session2', 'openclaw'],
    'job': ['session2'],
    'apply': ['session2'],
    'application': ['session2'],
    'game': ['openclaw4'],
    'download': ['openclaw4'],
    'torrent': ['openclaw4'],
    'qbittorrent': ['openclaw4'],
    'tv show': ['openclaw4'],
    'movie': ['openclaw4'],
    'youtube': ['openclaw'],
    'playlist': ['openclaw']
  };
  
  for (const [keyword, bots] of Object.entries(skillMap)) {
    if (lower.includes(keyword)) {
      return bots[0];
    }
  }
  
  return 'main'; // Default fallback
}

/**
 * Update bot statistics after task completion
 */
function updateBotStats(db, taskId) {
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(taskId);
  
  if (!task) return;
  
  const duration = task.started_at && task.completed_at
    ? (task.completed_at - task.started_at) / 1000
    : null;
  
  const updateStmt = db.prepare(`
    UPDATE bot_status SET
      total_tasks = total_tasks + 1,
      successful_tasks = successful_tasks + CASE WHEN ? = 'completed' THEN 1 ELSE 0 END,
      failed_tasks = failed_tasks + CASE WHEN ? = 'failed' THEN 1 ELSE 0 END,
      avg_duration_seconds = CASE 
        WHEN ? IS NOT NULL THEN 
          ((avg_duration_seconds * total_tasks) + ?) / (total_tasks + 1)
        ELSE avg_duration_seconds
      END,
      last_seen = ?,
      status = 'idle',
      current_task_id = NULL
    WHERE bot_id = ?
  `);
  
  updateStmt.run(
    task.status,
    task.status,
    duration,
    duration || 0,
    Date.now(),
    task.bot_id
  );
}

/**
 * Convert tasks array to CSV string
 */
function tasksToCSV(tasks) {
  const headers = [
    'ID',
    'Description',
    'Bot',
    'Status',
    'Created',
    'Started',
    'Completed',
    'Duration (s)',
    'Progress',
    'Error'
  ];
  
  const rows = tasks.map(t => [
    t.id,
    `"${(t.description || '').replace(/"/g, '""')}"`,
    t.bot_id,
    t.status,
    new Date(t.created_at).toISOString(),
    t.started_at ? new Date(t.started_at).toISOString() : '',
    t.completed_at ? new Date(t.completed_at).toISOString() : '',
    t.started_at && t.completed_at ? ((t.completed_at - t.started_at) / 1000).toFixed(2) : '',
    `"${(t.progress || '').replace(/"/g, '""')}"`,
    `"${(t.error || '').replace(/"/g, '""')}"`
  ]);
  
  return [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
}
