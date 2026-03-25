/**
 * Seed Data Generator for AgentFlow
 * Generates realistic test data for development and demos
 * @author Till Thelet
 */

const Database = require('better-sqlite3');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');

// Sample task descriptions
const taskTemplates = {
  job_application: [
    'Apply to 10 DevOps jobs on LinkedIn',
    'Apply to 5 remote Python developer positions',
    'Submit applications to 8 cloud engineer roles',
    'Apply to SRE positions on Indeed',
    'Find and apply to 15 Kubernetes-related jobs',
    'Submit resume to 5 startup DevOps roles',
    'Apply to Azure/AWS architect positions',
    'Send applications to Infrastructure Engineer jobs'
  ],
  media_download: [
    'Download Hogwarts Legacy',
    'Download Red Dead Redemption 2',
    'Download The Witcher 3 GOTY Edition',
    'Download Starfield',
    'Download 5 games from my wishlist',
    'Download latest TV show episodes',
    'Download Breaking Bad complete series',
    'Download Metro Exodus Enhanced Edition'
  ],
  browser_automation: [
    'Add 50 videos to YouTube playlist',
    'Clear browser cache and cookies',
    'Open Gmail and check unread emails',
    'Navigate to GitHub and check notifications',
    'Update LinkedIn profile headline',
    'Check Todoist for pending tasks',
    'Open Render dashboard and check deployment status'
  ],
  general: [
    'Check system resources and report',
    'Run PowerShell cleanup script',
    'Backup important files to external drive',
    'Update Git repositories',
    'Check Docker containers status',
    'Run database maintenance',
    'Generate weekly progress report'
  ]
};

// Bot skill mapping
const botSkills = {
  'session2': ['job_application', 'general'],
  'openclaw': ['browser_automation', 'general'],
  'openclaw4': ['media_download', 'general'],
  'main': ['general']
};

// Progress message templates
const progressTemplates = [
  '⚙️ Processing {current}/{total} | ⏱️ {time} | 📍 Working on item',
  '⚙️ {current}/{total} done ({percent}%) | ⏱️ {time}',
  '⚙️ Step {current} of {total} | ⏱️ {time} elapsed',
  '⚙️ {percent}% complete | ⏱️ {time} | 📍 Analyzing...'
];

// Result templates
const resultTemplates = {
  completed: [
    '✅ Complete: {count} items processed | ⏱️ Total: {time}',
    '✅ Task finished successfully | {count} items | ⏱️ {time}',
    '✅ Done: Processed {count} of {total} | ⏱️ {time}'
  ],
  failed: [
    '❌ Failed: Connection timeout after {time}',
    '❌ Error: Element not found - task aborted',
    '❌ Failed: Rate limited - try again later',
    '❌ Error: Network connection lost'
  ]
};

/**
 * Generate random duration in seconds
 */
function randomDuration(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/**
 * Format duration as human-readable
 */
function formatDuration(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

/**
 * Get random item from array
 */
function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * Generate a random task
 */
function generateTask(botId, daysAgo = 0) {
  const skills = botSkills[botId];
  const taskType = randomItem(skills);
  const templates = taskTemplates[taskType];
  const description = randomItem(templates);
  
  const id = uuidv4();
  const now = Date.now();
  const createdAt = now - (daysAgo * 24 * 60 * 60 * 1000) - randomDuration(0, 86400000);
  
  // 85% completed, 10% failed, 5% pending/running
  const statusRoll = Math.random();
  let status, startedAt, completedAt, progress, result, error;
  
  if (statusRoll < 0.85) {
    // Completed
    status = 'completed';
    const duration = randomDuration(30, 600); // 30s to 10m
    startedAt = createdAt + randomDuration(0, 5000);
    completedAt = startedAt + (duration * 1000);
    
    const count = randomDuration(5, 20);
    const total = count + randomDuration(0, 5);
    progress = randomItem(progressTemplates)
      .replace('{current}', count)
      .replace('{total}', total)
      .replace('{percent}', Math.round(count/total * 100))
      .replace('{time}', formatDuration(duration - 30));
    
    result = randomItem(resultTemplates.completed)
      .replace('{count}', count)
      .replace('{total}', total)
      .replace('{time}', formatDuration(duration));
  } else if (statusRoll < 0.95) {
    // Failed
    status = 'failed';
    const duration = randomDuration(10, 120);
    startedAt = createdAt + randomDuration(0, 5000);
    completedAt = startedAt + (duration * 1000);
    
    error = randomItem(resultTemplates.failed)
      .replace('{time}', formatDuration(duration));
    progress = '⚙️ Starting task...';
  } else if (statusRoll < 0.97) {
    // Running
    status = 'running';
    startedAt = now - randomDuration(30, 300) * 1000;
    
    const elapsed = Math.floor((now - startedAt) / 1000);
    const current = randomDuration(1, 5);
    const total = randomDuration(10, 20);
    progress = randomItem(progressTemplates)
      .replace('{current}', current)
      .replace('{total}', total)
      .replace('{percent}', Math.round(current/total * 100))
      .replace('{time}', formatDuration(elapsed));
  } else {
    // Pending
    status = 'pending';
  }
  
  return {
    id,
    description,
    bot_id: botId,
    status,
    created_at: createdAt,
    started_at: startedAt || null,
    completed_at: completedAt || null,
    progress: progress || null,
    result: result || null,
    error: error || null
  };
}

/**
 * Generate outcome for a task
 */
function generateOutcome(task) {
  if (task.status !== 'completed') return null;
  
  const id = uuidv4();
  let type, metrics;
  
  if (task.description.toLowerCase().includes('job') || task.description.toLowerCase().includes('apply')) {
    type = 'job_application';
    const applied = randomDuration(5, 15);
    const responses = Math.random() < 0.15 ? randomDuration(1, 3) : 0;
    metrics = {
      applied,
      responses,
      interviews: responses > 0 && Math.random() < 0.3 ? 1 : 0,
      keywords: ['DevOps', 'Remote', 'Cloud', 'Kubernetes'].slice(0, randomDuration(1, 3)),
      applied_at: task.completed_at
    };
  } else if (task.description.toLowerCase().includes('download') || task.description.toLowerCase().includes('game')) {
    type = 'media_download';
    metrics = {
      success: true,
      size_mb: randomDuration(5000, 80000),
      speed_mbps: randomDuration(20, 100),
      items_downloaded: randomDuration(1, 5)
    };
  } else if (task.description.toLowerCase().includes('youtube') || task.description.toLowerCase().includes('playlist')) {
    type = 'browser_automation';
    metrics = {
      videos_added: randomDuration(30, 60),
      errors: randomDuration(0, 3),
      duration_seconds: randomDuration(60, 300)
    };
  } else {
    return null; // No outcome for general tasks
  }
  
  return {
    id,
    task_id: task.id,
    type,
    metrics: JSON.stringify(metrics),
    feedback_source: 'auto',
    recorded_at: task.completed_at + randomDuration(0, 60000)
  };
}

/**
 * Main seeding function
 */
function seedDatabase(dbPath, options = {}) {
  const {
    tasksPerBot = 30,
    daysOfHistory = 14,
    clearExisting = true
  } = options;
  
  console.log('🌱 Seeding AgentFlow database...');
  console.log(`   📂 Database: ${dbPath}`);
  console.log(`   📊 Tasks per bot: ${tasksPerBot}`);
  console.log(`   📅 Days of history: ${daysOfHistory}`);
  console.log('');
  
  // Ensure data directory exists
  const dataDir = path.dirname(dbPath);
  fs.mkdirSync(dataDir, { recursive: true });
  
  // Open database
  const db = new Database(dbPath);
  
  // Create tables if not exist
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
  
  // Clear existing data if requested
  if (clearExisting) {
    console.log('🗑️  Clearing existing data...');
    db.exec('DELETE FROM outcomes');
    db.exec('DELETE FROM tasks');
    db.exec('DELETE FROM bot_status');
  }
  
  // Prepare statements
  const insertTask = db.prepare(`
    INSERT INTO tasks (id, description, bot_id, status, created_at, started_at, completed_at, progress, result, error)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  
  const insertOutcome = db.prepare(`
    INSERT INTO outcomes (id, task_id, type, metrics, feedback_source, recorded_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  
  const insertBot = db.prepare(`
    INSERT OR REPLACE INTO bot_status (bot_id, status, last_seen, total_tasks, successful_tasks, failed_tasks, avg_duration_seconds)
    VALUES (?, 'idle', ?, ?, ?, ?, ?)
  `);
  
  const bots = ['session2', 'openclaw', 'openclaw4', 'main'];
  let totalTasks = 0;
  let totalOutcomes = 0;
  
  // Generate tasks for each bot
  for (const botId of bots) {
    console.log(`🤖 Generating data for ${botId}...`);
    
    let botTotalTasks = 0;
    let botSuccessful = 0;
    let botFailed = 0;
    let totalDuration = 0;
    
    for (let i = 0; i < tasksPerBot; i++) {
      const daysAgo = Math.floor(i / (tasksPerBot / daysOfHistory));
      const task = generateTask(botId, daysAgo);
      
      insertTask.run(
        task.id,
        task.description,
        task.bot_id,
        task.status,
        task.created_at,
        task.started_at,
        task.completed_at,
        task.progress,
        task.result,
        task.error
      );
      
      totalTasks++;
      botTotalTasks++;
      
      if (task.status === 'completed') {
        botSuccessful++;
        if (task.started_at && task.completed_at) {
          totalDuration += (task.completed_at - task.started_at) / 1000;
        }
        
        // Generate outcome for some completed tasks
        if (Math.random() < 0.6) {
          const outcome = generateOutcome(task);
          if (outcome) {
            insertOutcome.run(
              outcome.id,
              outcome.task_id,
              outcome.type,
              outcome.metrics,
              outcome.feedback_source,
              outcome.recorded_at
            );
            totalOutcomes++;
          }
        }
      } else if (task.status === 'failed') {
        botFailed++;
      }
    }
    
    const avgDuration = botSuccessful > 0 ? totalDuration / botSuccessful : 0;
    
    insertBot.run(
      botId,
      Date.now(),
      botTotalTasks,
      botSuccessful,
      botFailed,
      avgDuration
    );
    
    console.log(`   ✅ ${botTotalTasks} tasks, ${botSuccessful} successful, ${botFailed} failed`);
  }
  
  db.close();
  
  console.log('');
  console.log('✨ Seeding complete!');
  console.log(`   📊 Total tasks: ${totalTasks}`);
  console.log(`   📈 Total outcomes: ${totalOutcomes}`);
  console.log(`   🤖 Bots configured: ${bots.length}`);
}

// Run if executed directly
if (require.main === module) {
  const dbPath = process.argv[2] || path.join(__dirname, '..', 'data', 'agentflow.db');
  
  seedDatabase(dbPath, {
    tasksPerBot: 30,
    daysOfHistory: 14,
    clearExisting: true
  });
}

module.exports = { seedDatabase, generateTask, generateOutcome };
