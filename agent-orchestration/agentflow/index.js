/**
 * AgentFlow - OpenClaw Extension
 * Multi-Agent AI Orchestration Platform
 * 
 * @author Till Thelet
 * @version 1.0.0
 */

const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');
const { v4: uuidv4 } = require('uuid');

// Extension metadata
module.exports = {
  name: 'agentflow',
  version: '1.0.0',
  description: 'Multi-Agent AI Orchestration Platform',
  
  /**
   * Initialize extension when gateway starts
   * @param {Object} context - OpenClaw extension context
   */
  async init(context) {
    const { app, gateway, logger } = context;
    
    logger.info('[AgentFlow] Initializing extension...');
    
    // Initialize database
    const dbPath = path.join(__dirname, 'data', 'agentflow.db');
    fs.mkdirSync(path.join(__dirname, 'data'), { recursive: true });
    const db = new Database(dbPath);
    
    // Create tables
    db.exec(`
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        bot_id TEXT,
        status TEXT DEFAULT 'pending',
        created_at INTEGER,
        started_at INTEGER,
        completed_at INTEGER,
        progress TEXT,
        result TEXT,
        error TEXT
      );
      
      CREATE TABLE IF NOT EXISTS outcomes (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        type TEXT,
        metrics TEXT,
        feedback_source TEXT,
        recorded_at INTEGER,
        FOREIGN KEY(task_id) REFERENCES tasks(id)
      );
      
      CREATE TABLE IF NOT EXISTS bot_status (
        bot_id TEXT PRIMARY KEY,
        status TEXT DEFAULT 'idle',
        current_task_id TEXT,
        last_seen INTEGER,
        total_tasks INTEGER DEFAULT 0,
        successful_tasks INTEGER DEFAULT 0,
        failed_tasks INTEGER DEFAULT 0,
        avg_duration_seconds REAL DEFAULT 0
      );
      
      CREATE INDEX IF NOT EXISTS idx_tasks_bot ON tasks(bot_id);
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
      CREATE INDEX IF NOT EXISTS idx_outcomes_task ON outcomes(task_id);
    `);
    
    // Initialize bot statuses
    const bots = ['session2', 'openclaw', 'openclaw4', 'main'];
    const initBot = db.prepare(`
      INSERT OR IGNORE INTO bot_status (bot_id, last_seen) VALUES (?, ?)
    `);
    
    bots.forEach(botId => {
      initBot.run(botId, Date.now());
    });
    
    logger.info('[AgentFlow] Database initialized');
    
    // Serve static files
    app.use('/agentflow', (req, res, next) => {
      if (req.path === '/' || req.path === '/index.html') {
        res.sendFile(path.join(__dirname, 'web', 'dashboard.html'));
      } else if (req.path === '/style.css') {
        res.sendFile(path.join(__dirname, 'web', 'style.css'));
      } else if (req.path === '/app.js') {
        res.sendFile(path.join(__dirname, 'web', 'app.js'));
      } else {
        next();
      }
    });
    
    // API: Get all tasks
    app.get('/agentflow/api/tasks', (req, res) => {
      const limit = parseInt(req.query.limit) || 50;
      const status = req.query.status;
      
      let query = 'SELECT * FROM tasks';
      const params = [];
      
      if (status) {
        query += ' WHERE status = ?';
        params.push(status);
      }
      
      query += ' ORDER BY created_at DESC LIMIT ?';
      params.push(limit);
      
      const stmt = db.prepare(query);
      const tasks = stmt.all(...params);
      
      res.json({ success: true, tasks });
    });
    
    // API: Create task
    app.post('/agentflow/api/tasks', express.json(), (req, res) => {
      const { description, bot_id } = req.body;
      
      if (!description) {
        return res.status(400).json({ success: false, error: 'Description required' });
      }
      
      // Auto-assign bot if not specified
      let assignedBot = bot_id;
      if (!assignedBot) {
        assignedBot = autoAssignBot(description);
      }
      
      const taskId = uuidv4();
      const now = Date.now();
      
      const stmt = db.prepare(`
        INSERT INTO tasks (id, description, bot_id, status, created_at)
        VALUES (?, ?, ?, 'pending', ?)
      `);
      
      stmt.run(taskId, description, assignedBot, now);
      
      // Send task to bot via gateway message system
      if (gateway.sendToBotSession) {
        gateway.sendToBotSession(assignedBot, description);
      }
      
      logger.info(`[AgentFlow] Task created: ${taskId} -> ${assignedBot}`);
      
      res.json({
        success: true,
        task: {
          id: taskId,
          description,
          bot_id: assignedBot,
          status: 'pending',
          created_at: now
        }
      });
    });
    
    // API: Get task by ID
    app.get('/agentflow/api/tasks/:id', (req, res) => {
      const stmt = db.prepare('SELECT * FROM tasks WHERE id = ?');
      const task = stmt.get(req.params.id);
      
      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      
      res.json({ success: true, task });
    });
    
    // API: Update task progress
    app.patch('/agentflow/api/tasks/:id/progress', express.json(), (req, res) => {
      const { progress, status } = req.body;
      const now = Date.now();
      
      const updates = [];
      const params = [];
      
      if (progress !== undefined) {
        updates.push('progress = ?');
        params.push(progress);
      }
      
      if (status !== undefined) {
        updates.push('status = ?');
        params.push(status);
        
        if (status === 'running' && req.body.started_at === undefined) {
          updates.push('started_at = ?');
          params.push(now);
        } else if (status === 'completed' || status === 'failed') {
          updates.push('completed_at = ?');
          params.push(now);
        }
      }
      
      if (updates.length === 0) {
        return res.status(400).json({ success: false, error: 'No updates provided' });
      }
      
      params.push(req.params.id);
      
      const stmt = db.prepare(`
        UPDATE tasks SET ${updates.join(', ')} WHERE id = ?
      `);
      
      stmt.run(...params);
      
      res.json({ success: true });
    });
    
    // API: Get bot statuses
    app.get('/agentflow/api/bots', (req, res) => {
      const stmt = db.prepare('SELECT * FROM bot_status');
      const bots = stmt.all();
      
      res.json({ success: true, bots });
    });
    
    // API: Get analytics
    app.get('/agentflow/api/analytics', (req, res) => {
      const timeRange = req.query.range || '7d'; // 7d, 30d, 90d, all
      
      let timeFilter = '';
      if (timeRange !== 'all') {
        const days = parseInt(timeRange);
        const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
        timeFilter = `WHERE created_at >= ${cutoff}`;
      }
      
      // Overall stats
      const overall = db.prepare(`
        SELECT 
          COUNT(*) as total_tasks,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
          SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running,
          SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
          AVG(CASE WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
              THEN (completed_at - started_at) / 1000.0 
              ELSE NULL END) as avg_duration_seconds
        FROM tasks ${timeFilter}
      `).get();
      
      // Per-bot stats
      const perBot = db.prepare(`
        SELECT 
          bot_id,
          COUNT(*) as total_tasks,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
          AVG(CASE WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
              THEN (completed_at - started_at) / 1000.0 
              ELSE NULL END) as avg_duration_seconds,
          ROUND(
            CAST(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS REAL) / 
            NULLIF(COUNT(*), 0) * 100, 
            2
          ) as success_rate
        FROM tasks ${timeFilter}
        GROUP BY bot_id
      `).all();
      
      // Task types (inferred from description keywords)
      const taskTypes = db.prepare(`
        SELECT 
          CASE 
            WHEN description LIKE '%job%' OR description LIKE '%apply%' OR description LIKE '%linkedin%' THEN 'job_application'
            WHEN description LIKE '%game%' OR description LIKE '%download%' THEN 'media_download'
            WHEN description LIKE '%browser%' OR description LIKE '%web%' THEN 'browser_automation'
            ELSE 'general'
          END as type,
          COUNT(*) as count,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed
        FROM tasks ${timeFilter}
        GROUP BY type
      `).all();
      
      res.json({
        success: true,
        analytics: {
          overall,
          perBot,
          taskTypes,
          timeRange
        }
      });
    });
    
    // API: Record outcome
    app.post('/agentflow/api/outcomes', express.json(), (req, res) => {
      const { task_id, type, metrics, feedback_source } = req.body;
      
      if (!task_id || !type || !metrics) {
        return res.status(400).json({ 
          success: false, 
          error: 'task_id, type, and metrics required' 
        });
      }
      
      const outcomeId = uuidv4();
      const now = Date.now();
      
      const stmt = db.prepare(`
        INSERT INTO outcomes (id, task_id, type, metrics, feedback_source, recorded_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `);
      
      stmt.run(
        outcomeId,
        task_id,
        type,
        JSON.stringify(metrics),
        feedback_source,
        now
      );
      
      logger.info(`[AgentFlow] Outcome recorded: ${outcomeId} for task ${task_id}`);
      
      res.json({ success: true, outcome_id: outcomeId });
    });
    
    // API: Get insights
    app.get('/agentflow/api/insights/:type', (req, res) => {
      const type = req.params.type;
      
      const stmt = db.prepare(`
        SELECT o.*, t.description
        FROM outcomes o
        JOIN tasks t ON o.task_id = t.id
        WHERE o.type = ?
        ORDER BY o.recorded_at DESC
        LIMIT 50
      `);
      
      const outcomes = stmt.all(type);
      
      // Parse metrics JSON
      outcomes.forEach(outcome => {
        outcome.metrics = JSON.parse(outcome.metrics);
      });
      
      // Calculate insights
      const insights = calculateInsights(type, outcomes);
      
      res.json({ success: true, insights, outcomes });
    });
    
    // Admin API: Hot-reload extension
    app.post('/agentflow/api/admin/reload', (req, res) => {
      const adminToken = req.headers['x-admin-token'] || req.headers['authorization'];
      
      // Basic security check (in production, use proper auth)
      if (adminToken !== process.env.OPENCLAW_ADMIN_TOKEN && adminToken !== 'agentflow-dev-token') {
        return res.status(401).json({ success: false, error: 'Unauthorized' });
      }
      
      logger.info('[AgentFlow] Hot-reload requested');
      
      // Clear require cache for hot-reload
      Object.keys(require.cache).forEach(key => {
        if (key.includes('agentflow')) {
          delete require.cache[key];
        }
      });
      
      res.json({ success: true, message: 'Extension reloaded' });
    });
    
    // Export task history
    app.get('/agentflow/api/export', (req, res) => {
      const format = req.query.format || 'json';
      
      const stmt = db.prepare(`
        SELECT * FROM tasks ORDER BY created_at DESC
      `);
      
      const tasks = stmt.all();
      
      if (format === 'csv') {
        const csv = tasksToCSV(tasks);
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename=agentflow-tasks.csv');
        res.send(csv);
      } else {
        res.json({ success: true, tasks });
      }
    });
    
    logger.info('[AgentFlow] Extension loaded successfully');
    logger.info('[AgentFlow] Dashboard: http://localhost:18789/agentflow');
  },
  
  /**
   * Cleanup when extension unloads
   */
  async destroy() {
    // Close database connections, cleanup resources
  }
};

/**
 * Auto-assign task to best bot based on description
 */
function autoAssignBot(description) {
  const lower = description.toLowerCase();
  
  const skillMap = {
    'browser': ['openclaw'],
    'linkedin': ['session2', 'openclaw'],
    'job': ['session2'],
    'apply': ['session2'],
    'game': ['openclaw4'],
    'download': ['openclaw4'],
    'tv': ['openclaw4'],
    'movie': ['openclaw4']
  };
  
  for (const [keyword, bots] of Object.entries(skillMap)) {
    if (lower.includes(keyword)) {
      return bots[0];
    }
  }
  
  return 'main'; // Default
}

/**
 * Calculate insights from outcomes
 */
function calculateInsights(type, outcomes) {
  if (outcomes.length === 0) {
    return { message: 'Not enough data for insights' };
  }
  
  if (type === 'job_application') {
    const totalApplications = outcomes.length;
    const responsesReceived = outcomes.filter(o => o.metrics.responses > 0).length;
    const responseRate = (responsesReceived / totalApplications * 100).toFixed(2);
    
    // Best times (if tracked)
    const byHour = {};
    outcomes.forEach(o => {
      if (o.metrics.applied_at) {
        const hour = new Date(o.metrics.applied_at).getHours();
        if (!byHour[hour]) byHour[hour] = { total: 0, responses: 0 };
        byHour[hour].total++;
        if (o.metrics.responses > 0) byHour[hour].responses++;
      }
    });
    
    const bestHour = Object.entries(byHour)
      .map(([hour, data]) => ({ 
        hour, 
        rate: (data.responses / data.total * 100).toFixed(2) 
      }))
      .sort((a, b) => parseFloat(b.rate) - parseFloat(a.rate))[0];
    
    return {
      totalApplications,
      responsesReceived,
      responseRate: `${responseRate}%`,
      bestTimeToApply: bestHour ? `${bestHour.hour}:00 (${bestHour.rate}% response rate)` : 'N/A'
    };
  }
  
  if (type === 'media_download') {
    const totalDownloads = outcomes.length;
    const successful = outcomes.filter(o => o.metrics.success === true).length;
    const successRate = (successful / totalDownloads * 100).toFixed(2);
    
    return {
      totalDownloads,
      successful,
      successRate: `${successRate}%`
    };
  }
  
  return { message: 'No specific insights for this type yet' };
}

/**
 * Convert tasks to CSV
 */
function tasksToCSV(tasks) {
  const headers = ['ID', 'Description', 'Bot', 'Status', 'Created', 'Started', 'Completed', 'Duration (s)'];
  const rows = tasks.map(t => [
    t.id,
    `"${t.description.replace(/"/g, '""')}"`,
    t.bot_id,
    t.status,
    new Date(t.created_at).toISOString(),
    t.started_at ? new Date(t.started_at).toISOString() : '',
    t.completed_at ? new Date(t.completed_at).toISOString() : '',
    t.started_at && t.completed_at ? ((t.completed_at - t.started_at) / 1000).toFixed(2) : ''
  ]);
  
  return [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
}
