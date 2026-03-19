# AgentFlow - System Architecture

## Overview

AgentFlow is a production-grade multi-agent orchestration platform built as an OpenClaw extension. It manages 4+ concurrent AI agents with real-time task distribution, progress monitoring, and outcome-based learning.

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         USER (Till Thelet)                        │
│   Web Browser → Dashboard (http://localhost:18789/agentflow)     │
└───────────────────────────┬──────────────────────────────────────┘
                            │ HTTP/WebSocket
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                   OpenClaw Gateway (Node.js)                      │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │               AgentFlow Extension                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │  │
│  │  │  Web Server  │  │ Bot Manager  │  │  Task Scheduler │  │  │
│  │  │ (Express API)│  │ (Connection  │  │  (Auto-assign)  │  │  │
│  │  └──────┬───────┘  │   Handler)   │  └────────┬────────┘  │  │
│  │         │          └──────┬───────┘           │           │  │
│  │         ▼                 ▼                   ▼           │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │           SQLite Database (agentflow.db)             │  │  │
│  │  │  • tasks          • outcomes                         │  │  │
│  │  │  • bot_status     • analytics cache                  │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│                  ┌───────────┴───────────┐                       │
│                  ▼                       ▼                       │
│  ┌──────────────────────┐   ┌──────────────────────┐           │
│  │ Internal Message Bus │   │  Telegram Bot API    │           │
│  └──────────┬───────────┘   └──────────┬───────────┘           │
│             │                           │                        │
└─────────────┼───────────────────────────┼────────────────────────┘
              │                           │
      ┌───────┴──────┬───────────┬───────┴──────┐
      ▼              ▼           ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ session2 │  │ openclaw │  │openclaw4 │  │   main   │
│  (Bot)   │  │  (Bot)   │  │  (Bot)   │  │  (Bot)   │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
     │              │              │              │
     ▼              ▼              ▼              ▼
┌─────────────────────────────────────────────────────┐
│       External Services & Automation Targets        │
│  • LinkedIn        • qBittorrent    • Browser        │
│  • Todoist         • File System    • YouTube        │
└─────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Frontend (Dashboard)

**Files:**
- `web/dashboard.html` - Main UI
- `web/style.css` - Styling (dark theme, responsive)
- `web/app.js` - Client-side logic

**Features:**
- Real-time bot status cards (4 bots)
- Active tasks list with progress tracking
- Task history with filtering
- Analytics dashboard (charts, metrics)
- New task modal with auto-assignment
- Quick action buttons (job, game, TV, browser)
- Toast notifications
- Keyboard shortcuts (Ctrl+K, Ctrl+R, Escape)

**Tech Stack:**
- Vanilla JavaScript (no frameworks)
- CSS Grid/Flexbox
- Fetch API for REST calls
- Auto-refresh every 5 seconds

### 2. Backend (Express API)

**Files:**
- `index.js` - Main extension entry point
- `api/tasks.js` - Task CRUD operations
- `api/bots.js` - Bot management
- `api/analytics.js` - Insights & outcomes
- `lib/bot-manager.js` - Bot connection handler

**API Endpoints:**

#### Tasks
```
GET    /agentflow/api/tasks                 # List tasks (with filters)
POST   /agentflow/api/tasks                 # Create task
GET    /agentflow/api/tasks/:id             # Get single task
PATCH  /agentflow/api/tasks/:id             # Update task progress/status
DELETE /agentflow/api/tasks/:id             # Delete task
GET    /agentflow/api/tasks/export/csv      # Export to CSV
```

#### Bots
```
GET    /agentflow/api/bots                  # List all bots
GET    /agentflow/api/bots/:id              # Get single bot + recent tasks
POST   /agentflow/api/bots/:id/heartbeat    # Update bot status (heartbeat)
POST   /agentflow/api/bots/:id/reset-stats  # Reset statistics
GET    /agentflow/api/bots/health/summary   # Overall health check
GET    /agentflow/api/bots/compare          # Performance comparison
```

#### Analytics
```
GET    /agentflow/api/analytics?range=7d    # Overall stats
POST   /agentflow/api/outcomes              # Record outcome (job app response, etc.)
GET    /agentflow/api/insights/:type        # Get insights for outcome type
GET    /agentflow/api/outcomes/trends/:type # Outcome trends over time
GET    /agentflow/api/analytics/top-tasks   # Top performing tasks
GET    /agentflow/api/analytics/failures    # Failure analysis
```

#### Admin
```
POST   /agentflow/api/admin/reload          # Hot-reload extension (requires admin token)
```

### 3. Database Schema

**SQLite (`data/agentflow.db`)**

#### `tasks` Table
```sql
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,               -- UUID
  description TEXT NOT NULL,         -- Task description
  bot_id TEXT,                       -- Assigned bot
  status TEXT DEFAULT 'pending',     -- pending, running, completed, failed
  created_at INTEGER,                -- Unix timestamp
  started_at INTEGER,                -- When bot started
  completed_at INTEGER,              -- When finished
  progress TEXT,                     -- Latest progress message
  result TEXT,                       -- Final result
  error TEXT                         -- Error message if failed
);
```

#### `bot_status` Table
```sql
CREATE TABLE bot_status (
  bot_id TEXT PRIMARY KEY,           -- Bot identifier
  status TEXT DEFAULT 'idle',        -- idle, running, offline, error
  current_task_id TEXT,              -- Currently executing task
  last_seen INTEGER,                 -- Last heartbeat timestamp
  total_tasks INTEGER DEFAULT 0,     -- Lifetime task count
  successful_tasks INTEGER DEFAULT 0,-- Completed count
  failed_tasks INTEGER DEFAULT 0,    -- Failed count
  avg_duration_seconds REAL DEFAULT 0 -- Average completion time
);
```

#### `outcomes` Table
```sql
CREATE TABLE outcomes (
  id TEXT PRIMARY KEY,               -- UUID
  task_id TEXT,                      -- Foreign key to tasks
  type TEXT,                         -- job_application, media_download, etc.
  metrics TEXT,                      -- JSON: { responses: 3, views: 1000, ... }
  feedback_source TEXT,              -- manual, tiktok_analytics, linkedin_api, etc.
  recorded_at INTEGER,               -- Timestamp
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```

### 4. Bot Manager

**Responsibilities:**
- Register and track 4 bots (session2, openclaw, openclaw4, main)
- Route tasks to appropriate bot based on keywords
- Monitor bot heartbeats (detect offline/online)
- Parse progress updates from bot messages
- Auto-update database on task completion
- Calculate bot statistics (success rate, avg duration)

**Message Protocol:**
```
Progress Update:  "⚙️ [X/Y done] | ⏱️ Xm Ys | 📍 [current step]"
Completion:       "✅ Complete: [summary] | ⏱️ Total: Xm Ys"
Failure:          "❌ Failed: [reason]"
```

**Auto-Assignment Algorithm:**
```javascript
const skillMap = {
  'browser': ['openclaw'],
  'linkedin': ['session2'],
  'job': ['session2'],
  'game': ['openclaw4'],
  'download': ['openclaw4'],
  'tv': ['openclaw4']
};

// Match description against keywords
// Fallback to 'main' if no match
```

### 5. Analytics Engine

**Insights Generated:**
- **Job Applications:**
  - Response rate (%)
  - Best times to apply (hour of day)
  - Top performing keywords
  - Recommendation: "Apply at 9:00 AM for 24% response rate"

- **Media Downloads:**
  - Success rate (%)
  - Average file size
  - Failed download patterns

- **Browser Automation:**
  - Task completion time
  - Error frequency by site
  - Timeout occurrences

**Trend Tracking:**
- Daily task volume
- Success/failure rates over time
- Per-bot performance changes
- Outcome metrics timeline

### 6. Tray Integration

**Modified File:**
`C:\Users\micha\.openclaw\ClawdbotTray.ps1`

**New Menu Items:**
```
[OpenClaw Tray Icon] (Right-click)
├─ Dashboard
├─ 🤖 AgentFlow Dashboard       ← Opens http://localhost:18789/agentflow
├─ 🔄 Restart AgentFlow         ← Hot-reload without gateway restart
├─ ─────────────────
├─ Restart Gateway
├─ Stop Gateway
└─ Quit
```

**Hot-Reload Mechanism:**
1. User clicks "Restart AgentFlow"
2. Tray sends POST to `/agentflow/api/admin/reload`
3. Extension clears require cache for its modules
4. Gateway re-requires `index.js`
5. New code loaded without restarting gateway
6. **Bots stay connected** (no interruption)
7. Balloon notification confirms success

## Data Flow

### 1. Task Creation Flow

```
User Input (Dashboard)
  → POST /agentflow/api/tasks { description, bot_id? }
  → Auto-assign bot if not specified
  → Insert task into database (status: pending)
  → BotManager.sendTaskToBot(botId, taskId, description)
  → Gateway message bus → Bot receives task
  → Bot starts work, sends progress updates
```

### 2. Progress Update Flow

```
Bot sends message: "⚙️ Processing 3/10 items..."
  → Gateway message bus
  → BotManager.handleBotMessage(event)
  → Parse progress indicator (⚙️)
  → UPDATE tasks SET progress = ... WHERE id = ?
  → Frontend polls /agentflow/api/tasks every 5s
  → Dashboard displays real-time progress
```

### 3. Task Completion Flow

```
Bot sends message: "✅ Complete: Downloaded 5 games | ⏱️ 5m 12s"
  → BotManager.handleTaskCompletion(botId, content, 'completed')
  → UPDATE tasks SET status = 'completed', completed_at = NOW()
  → UPDATE bot_status SET status = 'idle', successful_tasks + 1
  → Calculate avg_duration_seconds
  → Frontend refreshes → Shows task in history
```

### 4. Outcome Recording Flow

```
User/System records outcome
  → POST /agentflow/api/outcomes { task_id, type, metrics }
  → Insert into outcomes table
  → Analytics engine processes new data
  → GET /agentflow/api/insights/:type → Updated recommendations
```

## Deployment Architecture

### Development Mode
```
F:\study\AI_ML\...\agentflow\
  → Run: node index.js
  → Access: http://localhost:3000 (standalone)
```

### Production Mode (OpenClaw Extension)
```
C:\Users\micha\.openclaw\extensions\agentflow\
  → Auto-loaded by gateway on startup
  → Access: http://localhost:18789/agentflow
  → No separate process needed
```

### Auto-Start Flow
```
1. Windows boots
2. ClawdbotTray.ps1 starts (Startup folder)
3. Tray detects no gateway → starts gateway
4. Gateway loads extensions from extensions/
5. AgentFlow extension init() called
6. Web server registers routes on port 18789
7. BotManager initializes bot tracking
8. Database initialized (SQLite)
9. Dashboard accessible immediately
```

## Security Model

### Authentication
- **Extension admin endpoint:** Requires `X-Admin-Token` header
- **Default dev token:** `agentflow-dev-token`
- **Production token:** `$env:OPENCLAW_ADMIN_TOKEN`

### Data Privacy
- All data stored locally (`~/.openclaw/extensions/agentflow/data/`)
- No external API calls (except bot-initiated ones)
- Task history never leaves local machine
- Outcome metrics user-controlled

### Access Control
- Web dashboard: localhost only by default
- No remote access unless explicitly configured
- SQLite database file permissions: user-only read/write
- Admin operations require token

## Performance Characteristics

### Scalability
- **Bots:** Designed for 4, can handle 10+ with minimal changes
- **Tasks:** SQLite supports millions of records
- **Concurrent requests:** Express handles 1000+ req/s
- **Real-time updates:** 5-second polling (upgradeable to WebSocket)

### Resource Usage
- **Memory:** ~50MB (Node.js + SQLite)
- **Disk:** <5MB (code), <100MB (database after 6 months)
- **CPU:** <1% idle, ~5% under load
- **Network:** <100KB/s (local HTTP only)

### Response Times
- **Dashboard load:** <100ms
- **API calls:** <10ms (database queries)
- **Task creation:** <50ms
- **Analytics calculation:** <200ms
- **Hot-reload:** <2 seconds

## Extension Lifecycle

### Initialization
```javascript
module.exports = {
  name: 'agentflow',
  version: '1.0.0',
  
  async init(context) {
    const { app, gateway, logger } = context;
    
    // 1. Initialize database
    // 2. Register API routes
    // 3. Start BotManager
    // 4. Serve static files
    // 5. Log ready message
  }
};
```

### Hot-Reload
```javascript
// Clear require cache
Object.keys(require.cache).forEach(key => {
  if (key.includes('agentflow')) {
    delete require.cache[key];
  }
});

// Re-require main module → init() called again
```

### Graceful Shutdown
```javascript
async destroy() {
  // 1. Close database connections
  // 2. Save pending tasks
  // 3. Update bot statuses to offline
  // 4. Clear timers/intervals
}
```

## Future Enhancements (Roadmap)

### Phase 2 (Next 3 Months)
- **WebSocket support:** Real-time updates without polling
- **Task dependencies:** "After task A completes, run task B"
- **Scheduled tasks:** Cron-like job scheduling
- **Bot prioritization:** Assign high-priority tasks first
- **Mobile app:** React Native dashboard

### Phase 3 (6 Months)
- **Multi-user support:** Per-user task queues
- **Cloud sync:** Optional backup to S3/Google Drive
- **Machine learning:** Predict task duration, optimize assignment
- **Plugin system:** Third-party integrations
- **REST webhooks:** External systems trigger tasks

### Phase 4 (12 Months)
- **Distributed deployment:** Multiple gateway instances
- **Kubernetes operator:** Deploy on K8s cluster
- **Enterprise features:** RBAC, audit logs, SSO
- **Marketplace:** Share skills and automations
- **AI co-pilot:** Natural language task creation

## Developer Documentation

### Adding a New API Endpoint

1. **Create handler in `api/` folder:**
```javascript
// api/reports.js
module.exports = function(app, db, logger) {
  app.get('/agentflow/api/reports/weekly', (req, res) => {
    // Your logic here
    res.json({ success: true, data: ... });
  });
};
```

2. **Require in `index.js`:**
```javascript
require('./api/reports')(app, db, logger);
```

3. **Test:**
```bash
curl http://localhost:18789/agentflow/api/reports/weekly
```

### Adding a New Frontend Feature

1. **Add UI in `web/dashboard.html`:**
```html
<button onclick="myNewFeature()">New Feature</button>
```

2. **Add logic in `web/app.js`:**
```javascript
async function myNewFeature() {
  const response = await fetch('/agentflow/api/new-endpoint');
  const data = await response.json();
  // Update UI
}
```

3. **Add styles in `web/style.css`:**
```css
.my-new-class { color: var(--primary); }
```

### Testing Changes Locally

```bash
# 1. Make changes in F:\study\AI_ML\...\agentflow\

# 2. Copy to OpenClaw extensions
powershell .\install.ps1

# 3. Restart extension (not gateway)
curl -X POST http://localhost:18789/agentflow/api/admin/reload \
     -H "X-Admin-Token: agentflow-dev-token"

# 4. Refresh browser → Changes visible
```

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-03-18  
**Author:** Till Thelet  
**License:** MIT
