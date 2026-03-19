#!/usr/bin/env node

/**
 * AgentFlow CLI Tool
 * Command-line interface for managing AgentFlow
 * @author Till Thelet
 */

const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');

const command = process.argv[2];
const args = process.argv.slice(3);

const dbPath = process.env.DATABASE_PATH || path.join(__dirname, 'data', 'agentflow.db');

// Colors for terminal output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(colors[color] + message + colors.reset);
}

function error(message) {
  log(`❌ Error: ${message}`, 'red');
  process.exit(1);
}

function success(message) {
  log(`✅ ${message}`, 'green');
}

function info(message) {
  log(`ℹ️  ${message}`, 'blue');
}

// Check if database exists
if (!fs.existsSync(dbPath) && command !== 'init' && command !== 'help') {
  error(`Database not found at ${dbPath}. Run 'agentflow init' first.`);
}

// Database connection
let db;
if (command !== 'help' && command !== 'init') {
  db = new Database(dbPath, { readonly: command === 'status' || command === 'list' });
}

// Commands
const commands = {
  help: () => {
    log('\n🤖 AgentFlow CLI Tool\n', 'cyan');
    log('Usage: node cli.js <command> [options]\n', 'bright');
    log('Commands:', 'bright');
    log('  init                    Initialize database');
    log('  status                  Show overall status');
    log('  list [tasks|bots|scheduled]  List items');
    log('  create <description>    Create a new task');
    log('  schedule <desc> <schedule>  Create scheduled task');
    log('  delete <task-id>        Delete a task');
    log('  clean [days]            Clean old tasks (default: 90 days)');
    log('  export [format]         Export data (json|csv)');
    log('  backup [destination]    Backup database');
    log('  stats                   Show statistics');
    log('  help                    Show this help');
    log('\nExamples:', 'bright');
    log('  node cli.js create "Apply to 10 DevOps jobs"');
    log('  node cli.js schedule "Daily standup" "daily at 9:00"');
    log('  node cli.js list tasks');
    log('  node cli.js clean 30');
    log('  node cli.js export csv');
    log('');
  },

  init: () => {
    info('Initializing AgentFlow database...');
    
    const dir = path.dirname(dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    
    const newDb = new Database(dbPath);
    
    newDb.exec(`
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
      
      CREATE TABLE IF NOT EXISTS outcomes (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        type TEXT,
        metrics TEXT,
        feedback_source TEXT,
        recorded_at INTEGER
      );
      
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
      
      CREATE INDEX IF NOT EXISTS idx_tasks_bot ON tasks(bot_id);
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    `);
    
    // Insert default bot statuses
    const bots = ['session2', 'openclaw', 'openclaw4', 'main'];
    const stmt = newDb.prepare('INSERT OR IGNORE INTO bot_status (bot_id, last_seen) VALUES (?, ?)');
    bots.forEach(bot => stmt.run(bot, Date.now()));
    
    newDb.close();
    
    success(`Database initialized at ${dbPath}`);
  },

  status: () => {
    log('\n📊 AgentFlow Status\n', 'cyan');
    
    const stats = db.prepare(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
      FROM tasks
    `).get();
    
    const bots = db.prepare('SELECT * FROM bot_status').all();
    
    log('Tasks:', 'bright');
    log(`  Total: ${stats.total}`);
    log(`  Running: ${stats.running}`, stats.running > 0 ? 'yellow' : 'reset');
    log(`  Pending: ${stats.pending}`);
    log(`  Completed: ${stats.completed}`, 'green');
    log(`  Failed: ${stats.failed}`, stats.failed > 0 ? 'red' : 'reset');
    
    log('\nBots:', 'bright');
    bots.forEach(bot => {
      const successRate = bot.total_tasks > 0 
        ? ((bot.successful_tasks / bot.total_tasks) * 100).toFixed(1) + '%'
        : 'N/A';
      log(`  ${bot.bot_id}: ${bot.status} (${successRate} success rate)`);
    });
    
    log('');
  },

  list: () => {
    const type = args[0] || 'tasks';
    
    if (type === 'tasks') {
      const tasks = db.prepare('SELECT * FROM tasks ORDER BY created_at DESC LIMIT 20').all();
      
      log('\n📋 Recent Tasks\n', 'cyan');
      
      if (tasks.length === 0) {
        info('No tasks found');
        return;
      }
      
      tasks.forEach(task => {
        const statusEmoji = {
          pending: '⏳',
          running: '⚙️',
          completed: '✅',
          failed: '❌'
        }[task.status] || '❓';
        
        log(`${statusEmoji} [${task.bot_id}] ${task.description.substring(0, 60)}...`);
      });
      
      log('');
    } else if (type === 'bots') {
      const bots = db.prepare('SELECT * FROM bot_status').all();
      
      log('\n🤖 Bot Statuses\n', 'cyan');
      
      bots.forEach(bot => {
        log(`${bot.bot_id}: ${bot.status} (${bot.total_tasks} tasks)`);
      });
      
      log('');
    } else if (type === 'scheduled') {
      const scheduled = db.prepare('SELECT * FROM scheduled_tasks WHERE enabled = 1 ORDER BY next_run').all();
      
      log('\n⏰ Scheduled Tasks\n', 'cyan');
      
      if (scheduled.length === 0) {
        info('No scheduled tasks');
        return;
      }
      
      scheduled.forEach(task => {
        const nextRun = new Date(task.next_run).toLocaleString();
        log(`📅 ${task.description} (${task.schedule}) - Next: ${nextRun}`);
      });
      
      log('');
    }
  },

  create: () => {
    if (args.length === 0) {
      error('Please provide a task description');
    }
    
    const description = args.join(' ');
    const taskId = require('uuid').v4();
    const now = Date.now();
    
    db.prepare(`
      INSERT INTO tasks (id, description, bot_id, status, created_at)
      VALUES (?, ?, 'main', 'pending', ?)
    `).run(taskId, description, now);
    
    success(`Task created: ${taskId}`);
    info(`Description: ${description}`);
  },

  schedule: () => {
    if (args.length < 2) {
      error('Usage: node cli.js schedule <description> <schedule>');
    }
    
    const description = args.slice(0, -1).join(' ');
    const schedule = args[args.length - 1];
    
    const taskId = require('uuid').v4();
    const now = Date.now();
    const nextRun = now + (6 * 60 * 60 * 1000); // Default: 6 hours from now
    
    db.prepare(`
      INSERT INTO scheduled_tasks (id, description, schedule, next_run, enabled, created_at)
      VALUES (?, ?, ?, ?, 1, ?)
    `).run(taskId, description, schedule, nextRun, now);
    
    success(`Scheduled task created: ${taskId}`);
    info(`Description: ${description}`);
    info(`Schedule: ${schedule}`);
  },

  delete: () => {
    if (args.length === 0) {
      error('Please provide a task ID');
    }
    
    const taskId = args[0];
    
    const result = db.prepare('DELETE FROM tasks WHERE id = ?').run(taskId);
    
    if (result.changes === 0) {
      error(`Task not found: ${taskId}`);
    }
    
    success(`Task deleted: ${taskId}`);
  },

  clean: () => {
    const days = parseInt(args[0]) || 90;
    const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
    
    info(`Cleaning tasks older than ${days} days...`);
    
    const result = db.prepare('DELETE FROM tasks WHERE created_at < ?').run(cutoff);
    
    success(`Deleted ${result.changes} old tasks`);
  },

  export: () => {
    const format = args[0] || 'json';
    const tasks = db.prepare('SELECT * FROM tasks ORDER BY created_at DESC').all();
    
    const filename = `agentflow-export-${Date.now()}.${format}`;
    
    if (format === 'json') {
      fs.writeFileSync(filename, JSON.stringify(tasks, null, 2));
    } else if (format === 'csv') {
      const headers = ['ID', 'Description', 'Bot', 'Status', 'Created', 'Completed'];
      const rows = tasks.map(t => [
        t.id,
        `"${t.description.replace(/"/g, '""')}"`,
        t.bot_id,
        t.status,
        new Date(t.created_at).toISOString(),
        t.completed_at ? new Date(t.completed_at).toISOString() : ''
      ]);
      
      const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
      fs.writeFileSync(filename, csv);
    }
    
    success(`Data exported to ${filename}`);
  },

  backup: () => {
    const destination = args[0] || `agentflow-backup-${Date.now()}.db`;
    
    db.backup(destination);
    
    success(`Database backed up to ${destination}`);
  },

  stats: () => {
    log('\n📊 AgentFlow Statistics\n', 'cyan');
    
    const overall = db.prepare(`
      SELECT 
        COUNT(*) as total_tasks,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
        AVG(CASE WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
            THEN (completed_at - started_at) / 1000.0 
            ELSE NULL END) as avg_duration
      FROM tasks
    `).get();
    
    const successRate = overall.total_tasks > 0
      ? ((overall.completed / overall.total_tasks) * 100).toFixed(1)
      : '0';
    
    log('Overall:', 'bright');
    log(`  Total Tasks: ${overall.total_tasks}`);
    log(`  Completed: ${overall.completed}`, 'green');
    log(`  Failed: ${overall.failed}`, overall.failed > 0 ? 'red' : 'reset');
    log(`  Success Rate: ${successRate}%`);
    log(`  Avg Duration: ${overall.avg_duration ? overall.avg_duration.toFixed(1) + 's' : 'N/A'}`);
    
    const perBot = db.prepare(`
      SELECT bot_id, COUNT(*) as count
      FROM tasks
      WHERE status = 'completed'
      GROUP BY bot_id
    `).all();
    
    log('\nPer Bot:', 'bright');
    perBot.forEach(bot => {
      log(`  ${bot.bot_id}: ${bot.count} tasks`);
    });
    
    log('');
  }
};

// Execute command
if (!command || !commands[command]) {
  commands.help();
} else {
  commands[command]();
}

// Close database
if (db) {
  db.close();
}
