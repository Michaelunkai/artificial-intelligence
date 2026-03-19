# AgentFlow Deployment Guide

Complete guide for deploying AgentFlow in production or development environments.

## Quick Start (5 Minutes)

### Option 1: As OpenClaw Extension (Recommended)

```powershell
# 1. Navigate to project directory
cd F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\agent-orchestration\agentflow

# 2. Install dependencies
npm install

# 3. Run installation script
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 4. (Optional) Add tray integration
powershell -ExecutionPolicy Bypass -File .\install-tray-integration.ps1

# 5. Restart OpenClaw gateway
# Method A: Right-click tray icon → "Restart Gateway"
# Method B: Run command
openclaw gateway restart

# 6. Access dashboard
start http://localhost:18789/agentflow
```

**Done!** AgentFlow is now running and will auto-start on every reboot.

### Option 2: Standalone Development Server

```powershell
# 1. Install dependencies
cd F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\agent-orchestration\agentflow
npm install

# 2. (Optional) Seed with test data
node scripts/seed-data.js

# 3. Start server
npm start

# 4. Access dashboard
start http://localhost:3000/agentflow
```

---

## Detailed Installation

### Prerequisites

- **Node.js** >= 18.0.0 (check: `node --version`)
- **OpenClaw** installed (for extension mode)
- **Windows** 10/11 or Linux
- **Port availability**: 18789 (OpenClaw) or 3000 (standalone)

### Install Dependencies

```bash
npm install
```

**Installed packages:**
- `express` - Web server
- `ws` - WebSocket support
- `better-sqlite3` - Database
- `uuid` - Unique ID generation
- `cors` - CORS middleware
- `body-parser` - JSON parsing

### Database Initialization

The database (`data/agentflow.db`) is created automatically on first run.

**Manual initialization:**
```bash
node -e "require('./index.js')"
```

**Seed with test data:**
```bash
node scripts/seed-data.js
# Options:
node scripts/seed-data.js C:\custom\path\to\agentflow.db
```

### Configuration

**Environment Variables** (optional):

```env
# .env file
PORT=3000                           # Standalone server port
OPENCLAW_ADMIN_TOKEN=your-token     # Admin API token
DATABASE_PATH=./data/agentflow.db   # Custom database path
LOG_LEVEL=info                      # Logging level (debug, info, warn, error)
```

---

## Deployment Methods

### 1. OpenClaw Extension (Production)

#### Installation

```powershell
# Copy entire folder to OpenClaw extensions directory
Copy-Item -Path . -Destination "C:\Users\micha\.openclaw\extensions\agentflow" -Recurse -Force

# Or use install script
.\install.ps1
```

#### Auto-Start Configuration

Extension auto-loads when gateway starts. No additional setup needed.

**Verify installation:**
1. Open OpenClaw gateway logs
2. Look for: `[AgentFlow] Extension loaded successfully`
3. Access: http://localhost:18789/agentflow

#### Updating Extension

```powershell
# Method 1: Hot-reload (no gateway restart)
curl -X POST http://localhost:18789/agentflow/api/admin/reload `
     -H "X-Admin-Token: agentflow-dev-token"

# Method 2: Full restart (safer for major changes)
openclaw gateway restart
```

### 2. Standalone Server (Development)

#### Start Server

```bash
# Development mode (auto-reload with nodemon)
npm run dev

# Production mode
npm start

# Custom port
PORT=5000 npm start
```

#### Process Manager (PM2)

Keep server running in background:

```bash
# Install PM2
npm install -g pm2

# Start AgentFlow
pm2 start standalone-server.js --name agentflow

# Auto-start on boot
pm2 startup
pm2 save

# View logs
pm2 logs agentflow

# Restart
pm2 restart agentflow

# Stop
pm2 stop agentflow
```

### 3. Docker Deployment

**Dockerfile:**
```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "standalone-server.js"]
```

**Build and run:**
```bash
# Build image
docker build -t agentflow:latest .

# Run container
docker run -d \
  --name agentflow \
  -p 3000:3000 \
  -v $(pwd)/data:/app/data \
  agentflow:latest

# View logs
docker logs -f agentflow

# Stop
docker stop agentflow
```

**Docker Compose:**
```yaml
version: '3.8'

services:
  agentflow:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - ./data:/app/data
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
    restart: unless-stopped
```

```bash
docker-compose up -d
```

### 4. Windows Service (Production)

Install as Windows service using NSSM:

```powershell
# Download NSSM
Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile "nssm.zip"
Expand-Archive -Path "nssm.zip" -DestinationPath "C:\nssm"

# Install service
C:\nssm\nssm-2.24\win64\nssm.exe install AgentFlow "C:\Program Files\nodejs\node.exe"
C:\nssm\nssm-2.24\win64\nssm.exe set AgentFlow AppDirectory "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\agent-orchestration\agentflow"
C:\nssm\nssm-2.24\win64\nssm.exe set AgentFlow AppParameters "standalone-server.js"
C:\nssm\nssm-2.24\win64\nssm.exe set AgentFlow Start SERVICE_AUTO_START

# Start service
Start-Service AgentFlow

# Check status
Get-Service AgentFlow

# View logs
nssm.exe set AgentFlow AppStdout "C:\logs\agentflow-stdout.log"
nssm.exe set AgentFlow AppStderr "C:\logs\agentflow-stderr.log"
```

---

## Verification & Testing

### Health Check

```bash
# Check if server is running
curl http://localhost:18789/agentflow

# API health check
curl http://localhost:18789/agentflow/api/bots

# WebSocket check (in browser console)
const ws = new WebSocket('ws://localhost:18789/agentflow/ws');
ws.onopen = () => console.log('WebSocket connected!');
```

### Run Tests

```bash
# Unit tests
npm test

# Or manually
node tests/utils.test.js
```

### Verify Features

**Dashboard:**
```
http://localhost:18789/agentflow
```
- [ ] Bot status cards show all 4 bots
- [ ] Create new task works
- [ ] Active tasks update in real-time
- [ ] Analytics charts render correctly

**Insights Page:**
```
http://localhost:18789/agentflow/insights.html
```
- [ ] Job application insights load
- [ ] Charts display correctly
- [ ] Recent outcomes list populated

**Scheduled Tasks:**
```
http://localhost:18789/agentflow/scheduled.html
```
- [ ] Can create new scheduled task
- [ ] Upcoming tasks list shows next runs
- [ ] Pause/resume/delete work

### Logs

**Extension mode (OpenClaw):**
```powershell
# View gateway logs
openclaw logs

# Or check file
Get-Content "C:\Users\micha\.openclaw\logs\gateway.log" -Tail 50
```

**Standalone mode:**
```bash
# Console output (if running in foreground)
# Or check PM2 logs
pm2 logs agentflow

# Docker logs
docker logs -f agentflow
```

---

## Troubleshooting

### Common Issues

#### "Cannot find module 'express'"
```bash
# Solution: Install dependencies
npm install
```

#### "Port 18789 already in use"
```bash
# Solution: OpenClaw gateway is already running
# Just access the dashboard directly
start http://localhost:18789/agentflow
```

#### "Extension not loading"
```bash
# Solution: Check OpenClaw version
openclaw --version  # Should be >= 0.50.0

# Check extension directory
dir "C:\Users\micha\.openclaw\extensions\agentflow"

# Check logs
openclaw logs | Select-String "agentflow"
```

#### "WebSocket connection failed"
```bash
# Solution: Extension may not support WebSocket yet
# Dashboard falls back to polling automatically
# Check browser console for errors
```

#### "Database locked"
```bash
# Solution: Another process is using the database
# Stop all AgentFlow processes
pm2 stop agentflow
# Or restart gateway
openclaw gateway restart
```

#### "Tasks not executing"
```bash
# Solution: Check bot statuses
curl http://localhost:18789/agentflow/api/bots

# Verify BotManager is initialized
# Check logs for errors
```

### Reset Database

```bash
# Backup current database
cp data/agentflow.db data/agentflow.db.backup

# Delete database (will recreate on next start)
rm data/agentflow.db

# Restart server/gateway
```

### Force Reinstall

```powershell
# 1. Stop gateway/service
openclaw gateway stop

# 2. Delete extension
Remove-Item -Recurse -Force "C:\Users\micha\.openclaw\extensions\agentflow"

# 3. Reinstall
.\install.ps1

# 4. Restart gateway
openclaw gateway start
```

---

## Performance Optimization

### Database Optimization

```sql
-- Run periodically to optimize database
VACUUM;
ANALYZE;

-- Create additional indexes if needed
CREATE INDEX idx_tasks_completed ON tasks(completed_at);
CREATE INDEX idx_outcomes_type ON outcomes(type);
```

### Memory Usage

**Expected memory usage:**
- Extension mode: ~50MB (shared with gateway)
- Standalone mode: ~80MB
- With 10,000 tasks: ~150MB

**Reduce memory:**
```javascript
// In index.js, limit result sets
const TASK_LIMIT = 100; // Default: 50
const HISTORY_DAYS = 30; // Default: unlimited
```

### Disk Space

**Expected disk usage:**
- Code: ~5MB
- Database (6 months): ~50MB
- Logs (if enabled): ~10MB/month

**Cleanup old data:**
```sql
-- Delete tasks older than 90 days
DELETE FROM tasks WHERE created_at < strftime('%s', 'now', '-90 days') * 1000;

-- Delete outcomes older than 180 days
DELETE FROM outcomes WHERE recorded_at < strftime('%s', 'now', '-180 days') * 1000;

-- Vacuum to reclaim space
VACUUM;
```

---

## Security Considerations

### API Access Control

**Admin endpoints** (require token):
- `/agentflow/api/admin/*`

**Set admin token:**
```bash
# Windows
$env:OPENCLAW_ADMIN_TOKEN = "your-secure-token-here"

# Linux
export OPENCLAW_ADMIN_TOKEN="your-secure-token-here"
```

**Use in requests:**
```bash
curl -X POST http://localhost:18789/agentflow/api/admin/reload \
     -H "X-Admin-Token: your-secure-token-here"
```

### Network Security

**Localhost only (default):**
Dashboard accessible only from same machine.

**Allow remote access (use with caution):**
```javascript
// In index.js or standalone-server.js
app.listen(PORT, '0.0.0.0', () => {
  // Now accessible from network
});
```

**Use reverse proxy (nginx):**
```nginx
server {
  listen 80;
  server_name agentflow.your-domain.com;
  
  location /agentflow {
    proxy_pass http://localhost:18789;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
  }
}
```

### Data Privacy

- All data stored locally (no external API calls)
- Database encrypted at rest (if using BitLocker/LUKS)
- Task descriptions may contain sensitive info (careful with backups)

---

## Backup & Restore

### Backup

```bash
# Full backup (database + config)
tar -czf agentflow-backup-$(date +%Y%m%d).tar.gz data/ extension.json

# Database only
cp data/agentflow.db backups/agentflow-$(date +%Y%m%d).db
```

**Automated backup (Windows Task Scheduler):**
```powershell
# Create backup script
$date = Get-Date -Format "yyyyMMdd"
Copy-Item "F:\...\agentflow\data\agentflow.db" "F:\backups\agentflow-$date.db"

# Schedule daily at 2 AM via Task Scheduler
```

### Restore

```bash
# Stop server/gateway
openclaw gateway stop

# Restore database
cp backups/agentflow-20260318.db data/agentflow.db

# Restart
openclaw gateway start
```

---

## Monitoring

### Metrics to Track

- Active tasks count
- Bot success rates
- Average task duration
- Database size
- Memory usage
- WebSocket connections

### Prometheus Integration (Future)

```javascript
// Add to index.js
const prometheus = require('prom-client');

const taskCounter = new prometheus.Counter({
  name: 'agentflow_tasks_total',
  help: 'Total number of tasks',
  labelNames: ['bot_id', 'status']
});

// Expose metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});
```

---

## Production Checklist

Before deploying to production:

- [ ] Set secure `OPENCLAW_ADMIN_TOKEN`
- [ ] Configure automated backups
- [ ] Set up log rotation
- [ ] Test hot-reload functionality
- [ ] Verify auto-start on boot
- [ ] Document custom configurations
- [ ] Set up monitoring/alerts
- [ ] Test disaster recovery procedure
- [ ] Review security settings
- [ ] Enable HTTPS (if remote access)

---

## Support

**Documentation:**
- Main README: `README.md`
- Architecture: `ARCHITECTURE.md`
- Contributing: `CONTRIBUTING.md`

**Issues:**
- GitHub: https://github.com/Michaelunkai/agentflow/issues

**Contact:**
- Email: michaelovsky22@gmail.com
- Telegram: @TillThelet

---

**Version:** 1.0.0  
**Last Updated:** 2026-03-18  
**Author:** Till Thelet
