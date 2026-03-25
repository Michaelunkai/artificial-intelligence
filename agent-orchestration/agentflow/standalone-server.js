/**
 * AgentFlow Standalone Development Server
 * Runs AgentFlow without OpenClaw gateway for testing
 * @author Till Thelet
 */

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Setup logger
const logger = {
  info: (msg, ...args) => console.log(`[INFO] ${msg}`, ...args),
  error: (msg, ...args) => console.error(`[ERROR] ${msg}`, ...args),
  warn: (msg, ...args) => console.warn(`[WARN] ${msg}`, ...args),
  debug: (msg, ...args) => console.debug(`[DEBUG] ${msg}`, ...args)
};

// Initialize database
const dbPath = path.join(__dirname, 'data', 'agentflow.db');
fs.mkdirSync(path.join(__dirname, 'data'), { recursive: true });
const db = new Database(dbPath);

logger.info('Database initialized at:', dbPath);

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
`);

// Initialize bots
const bots = ['session2', 'openclaw', 'openclaw4', 'main'];
const initBot = db.prepare(`
  INSERT OR IGNORE INTO bot_status (bot_id, last_seen) VALUES (?, ?)
`);
bots.forEach(botId => initBot.run(botId, Date.now()));

logger.info('Bot statuses initialized');

// ============ STATIC FILES ============

// Serve dashboard
app.get('/', (req, res) => {
  res.redirect('/agentflow');
});

app.get('/agentflow', (req, res) => {
  res.sendFile(path.join(__dirname, 'web', 'dashboard.html'));
});

app.get('/agentflow/style.css', (req, res) => {
  res.sendFile(path.join(__dirname, 'web', 'style.css'));
});

app.get('/agentflow/app.js', (req, res) => {
  res.sendFile(path.join(__dirname, 'web', 'app.js'));
});

// ============ TASKS API ============

// Get all tasks
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
    logger.error('Get tasks failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Create task
app.post('/agentflow/api/tasks', (req, res) => {
  try {
    const { description, bot_id } = req.body;
    
    if (!description) {
      return res.status(400).json({ success: false, error: 'Description required' });
    }
    
    // Auto-assign bot
    let assignedBot = bot_id;
    if (!assignedBot) {
      const lower = description.toLowerCase();
      if (lower.includes('job') || lower.includes('apply')) assignedBot = 'session2';
      else if (lower.includes('game') || lower.includes('download')) assignedBot = 'openclaw4';
      else if (lower.includes('browser') || lower.includes('youtube')) assignedBot = 'openclaw';
      else assignedBot = 'main';
    }
    
    const taskId = require('uuid').v4();
    const now = Date.now();
    
    const stmt = db.prepare(`
      INSERT INTO tasks (id, description, bot_id, status, created_at)
      VALUES (?, ?, ?, 'pending', ?)
    `);
    
    stmt.run(taskId, description, assignedBot, now);
    
    // Simulate starting the task after 1 second (for demo)
    setTimeout(() => {
      db.prepare(`
        UPDATE tasks SET status = 'running', started_at = ? WHERE id = ?
      `).run(Date.now(), taskId);
      
      db.prepare(`
        UPDATE bot_status SET status = 'running', current_task_id = ? WHERE bot_id = ?
      `).run(taskId, assignedBot);
    }, 1000);
    
    // Simulate completing the task after 5-15 seconds (for demo)
    const duration = 5000 + Math.random() * 10000;
    setTimeout(() => {
      const success = Math.random() < 0.9;
      
      if (success) {
        db.prepare(`
          UPDATE tasks SET 
            status = 'completed', 
            completed_at = ?,
            progress = '⚙️ Processing complete',
            result = '✅ Task completed successfully'
          WHERE id = ?
        `).run(Date.now(), taskId);
        
        db.prepare(`
          UPDATE bot_status SET 
            status = 'idle', 
            current_task_id = NULL,
            total_tasks = total_tasks + 1,
            successful_tasks = successful_tasks + 1
          WHERE bot_id = ?
        `).run(assignedBot);
      } else {
        db.prepare(`
          UPDATE tasks SET 
            status = 'failed', 
            completed_at = ?,
            error = '❌ Simulated failure for demo'
          WHERE id = ?
        `).run(Date.now(), taskId);
        
        db.prepare(`
          UPDATE bot_status SET 
            status = 'idle', 
            current_task_id = NULL,
            total_tasks = total_tasks + 1,
            failed_tasks = failed_tasks + 1
          WHERE bot_id = ?
        `).run(assignedBot);
      }
    }, duration);
    
    logger.info(`Task created: ${taskId} -> ${assignedBot}`);
    
    res.status(201).json({
      success: true,
      task: {
        id: taskId,
        description,
        bot_id: assignedBot,
        status: 'pending',
        created_at: now
      }
    });
  } catch (error) {
    logger.error('Create task failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get single task
app.get('/agentflow/api/tasks/:id', (req, res) => {
  try {
    const stmt = db.prepare('SELECT * FROM tasks WHERE id = ?');
    const task = stmt.get(req.params.id);
    
    if (!task) {
      return res.status(404).json({ success: false, error: 'Task not found' });
    }
    
    res.json({ success: true, task });
  } catch (error) {
    logger.error('Get task failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update task
app.patch('/agentflow/api/tasks/:id', (req, res) => {
  try {
    const { status, progress, result, error } = req.body;
    const now = Date.now();
    
    const updates = [];
    const params = [];
    
    if (status !== undefined) {
      updates.push('status = ?');
      params.push(status);
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
    
    const result_ = stmt.run(...params);
    
    if (result_.changes === 0) {
      return res.status(404).json({ success: false, error: 'Task not found' });
    }
    
    res.json({ success: true, message: 'Task updated' });
  } catch (error) {
    logger.error('Update task failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Delete task
app.delete('/agentflow/api/tasks/:id', (req, res) => {
  try {
    db.prepare('DELETE FROM outcomes WHERE task_id = ?').run(req.params.id);
    const stmt = db.prepare('DELETE FROM tasks WHERE id = ?');
    const result = stmt.run(req.params.id);
    
    if (result.changes === 0) {
      return res.status(404).json({ success: false, error: 'Task not found' });
    }
    
    res.json({ success: true, message: 'Task deleted' });
  } catch (error) {
    logger.error('Delete task failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============ BOTS API ============

// Get all bots
app.get('/agentflow/api/bots', (req, res) => {
  try {
    const stmt = db.prepare('SELECT * FROM bot_status ORDER BY bot_id');
    const bots = stmt.all();
    
    res.json({ success: true, bots, count: bots.length });
  } catch (error) {
    logger.error('Get bots failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get single bot
app.get('/agentflow/api/bots/:bot_id', (req, res) => {
  try {
    const stmt = db.prepare('SELECT * FROM bot_status WHERE bot_id = ?');
    const bot = stmt.get(req.params.bot_id);
    
    if (!bot) {
      return res.status(404).json({ success: false, error: 'Bot not found' });
    }
    
    // Get recent tasks
    bot.recent_tasks = db.prepare(`
      SELECT * FROM tasks WHERE bot_id = ? ORDER BY created_at DESC LIMIT 10
    `).all(bot.bot_id);
    
    res.json({ success: true, bot });
  } catch (error) {
    logger.error('Get bot failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Bot heartbeat
app.post('/agentflow/api/bots/:bot_id/heartbeat', (req, res) => {
  try {
    const { status, current_task_id } = req.body;
    const now = Date.now();
    
    const stmt = db.prepare(`
      UPDATE bot_status 
      SET last_seen = ?, status = COALESCE(?, status), current_task_id = ?
      WHERE bot_id = ?
    `);
    
    stmt.run(now, status, current_task_id, req.params.bot_id);
    
    res.json({ success: true, message: 'Heartbeat received' });
  } catch (error) {
    logger.error('Heartbeat failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============ ANALYTICS API ============

// Get analytics
app.get('/agentflow/api/analytics', (req, res) => {
  try {
    const range = req.query.range || '7d';
    
    let timeFilter = '';
    if (range !== 'all') {
      const days = parseInt(range.replace('d', ''));
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
          NULLIF(COUNT(*), 0) * 100, 2
        ) as success_rate
      FROM tasks ${timeFilter}
      GROUP BY bot_id
    `).all();
    
    res.json({
      success: true,
      analytics: { overall, perBot, timeRange: range }
    });
  } catch (error) {
    logger.error('Get analytics failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Record outcome
app.post('/agentflow/api/outcomes', (req, res) => {
  try {
    const { task_id, type, metrics, feedback_source } = req.body;
    
    if (!task_id || !type || !metrics) {
      return res.status(400).json({
        success: false,
        error: 'task_id, type, and metrics required'
      });
    }
    
    const outcomeId = require('uuid').v4();
    const now = Date.now();
    
    const stmt = db.prepare(`
      INSERT INTO outcomes (id, task_id, type, metrics, feedback_source, recorded_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    stmt.run(outcomeId, task_id, type, JSON.stringify(metrics), feedback_source || 'manual', now);
    
    res.status(201).json({
      success: true,
      outcome: { id: outcomeId, task_id, type, metrics, recorded_at: now }
    });
  } catch (error) {
    logger.error('Record outcome failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get insights
app.get('/agentflow/api/insights/:type', (req, res) => {
  try {
    const type = req.params.type;
    
    const stmt = db.prepare(`
      SELECT o.*, t.description, t.bot_id
      FROM outcomes o
      JOIN tasks t ON o.task_id = t.id
      WHERE o.type = ?
      ORDER BY o.recorded_at DESC
      LIMIT 50
    `);
    
    const outcomes = stmt.all(type);
    
    outcomes.forEach(o => {
      o.metrics = JSON.parse(o.metrics);
    });
    
    res.json({
      success: true,
      type,
      outcomes,
      total_outcomes: outcomes.length
    });
  } catch (error) {
    logger.error('Get insights failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============ ADMIN API ============

// Hot-reload (no-op in standalone mode)
app.post('/agentflow/api/admin/reload', (req, res) => {
  logger.info('Hot-reload requested (no-op in standalone mode)');
  res.json({ success: true, message: 'Standalone mode - no reload needed' });
});

// ============ START SERVER ============

app.listen(PORT, () => {
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║       🤖 AgentFlow Standalone Development Server 🤖          ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Dashboard: http://localhost:${PORT}/agentflow                    ║`);
  console.log(`║  API Base:  http://localhost:${PORT}/agentflow/api                ║`);
  console.log('║                                                              ║');
  console.log('║  This is a development server with simulated task execution ║');
  console.log('║  For production, use as OpenClaw extension                  ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\nShutting down...');
  db.close();
  process.exit(0);
});
