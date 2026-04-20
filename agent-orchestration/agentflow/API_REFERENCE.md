# AgentFlow API Reference

Complete API documentation for all endpoints.

**Base URL:** `http://localhost:18789/agentflow/api` (extension) or `http://localhost:3000/agentflow/api` (standalone)

---

## Authentication

Most endpoints are public (localhost-only by default). Admin endpoints require a token:

```http
POST /agentflow/api/admin/*
X-Admin-Token: your-admin-token-here
```

---

## Tasks API

### Get All Tasks
```http
GET /agentflow/api/tasks
```

**Query Parameters:**
- `status` (string, optional): Filter by status (pending, running, completed, failed)
- `bot` (string, optional): Filter by bot_id
- `limit` (number, optional): Max results (default: 50)

**Response:**
```json
{
  "success": true,
  "tasks": [
    {
      "id": "uuid",
      "description": "Apply to 10 jobs",
      "bot_id": "session2",
      "status": "completed",
      "created_at": 1710759600000,
      "started_at": 1710759605000,
      "completed_at": 1710759900000,
      "progress": "⚙️ Processing 10/10",
      "result": "✅ Task completed"
    }
  ],
  "count": 1
}
```

### Create Task
```http
POST /agentflow/api/tasks
Content-Type: application/json
```

**Body:**
```json
{
  "description": "Download Starfield",
  "bot_id": "openclaw4"
}
```

**Response:**
```json
{
  "success": true,
  "task": {
    "id": "uuid",
    "description": "Download Starfield",
    "bot_id": "openclaw4",
    "status": "pending",
    "created_at": 1710759600000
  }
}
```

### Get Single Task
```http
GET /agentflow/api/tasks/:id
```

**Response:**
```json
{
  "success": true,
  "task": { /* task object */ }
}
```

### Update Task
```http
PATCH /agentflow/api/tasks/:id
Content-Type: application/json
```

**Body:**
```json
{
  "status": "running",
  "progress": "⚙️ Step 1 of 5"
}
```

### Delete Task
```http
DELETE /agentflow/api/tasks/:id
```

### Export Tasks
```http
GET /agentflow/api/tasks/export/csv
```

Returns CSV file download.

---

## Bots API

### Get All Bots
```http
GET /agentflow/api/bots
```

**Response:**
```json
{
  "success": true,
  "bots": [
    {
      "bot_id": "session2",
      "status": "idle",
      "current_task_id": null,
      "last_seen": 1710759600000,
      "total_tasks": 150,
      "successful_tasks": 142,
      "failed_tasks": 8,
      "avg_duration_seconds": 45.3
    }
  ],
  "count": 4
}
```

### Get Single Bot
```http
GET /agentflow/api/bots/:bot_id
```

Includes recent_tasks array.

### Bot Heartbeat
```http
POST /agentflow/api/bots/:bot_id/heartbeat
Content-Type: application/json
```

**Body:**
```json
{
  "status": "running",
  "current_task_id": "uuid"
}
```

### Reset Bot Stats
```http
POST /agentflow/api/bots/:bot_id/reset-stats
```

### Health Summary
```http
GET /agentflow/api/bots/health/summary
```

**Response:**
```json
{
  "success": true,
  "health": {
    "total_bots": 4,
    "online": 4,
    "idle": 3,
    "running": 1,
    "offline": 0,
    "error": 0
  }
}
```

### Compare Bots
```http
GET /agentflow/api/bots/compare
```

Returns performance rankings.

---

## Analytics API

### Get Analytics
```http
GET /agentflow/api/analytics?range=7d
```

**Query Parameters:**
- `range` (string, optional): 7d, 30d, 90d, all (default: 7d)

**Response:**
```json
{
  "success": true,
  "analytics": {
    "overall": {
      "total_tasks": 500,
      "completed": 470,
      "failed": 20,
      "running": 5,
      "pending": 5,
      "avg_duration_seconds": 42.5
    },
    "perBot": [
      {
        "bot_id": "session2",
        "total_tasks": 200,
        "completed": 190,
        "failed": 10,
        "avg_duration_seconds": 50.2,
        "success_rate": 95.0
      }
    ],
    "taskTypes": [
      {
        "type": "job_application",
        "count": 150,
        "completed": 145,
        "failed": 5
      }
    ],
    "timeline": [
      {
        "date": "2026-03-18",
        "total": 50,
        "completed": 48,
        "failed": 2
      }
    ],
    "timeRange": "7d"
  }
}
```

### Record Outcome
```http
POST /agentflow/api/outcomes
Content-Type: application/json
```

**Body:**
```json
{
  "task_id": "uuid",
  "type": "job_application",
  "metrics": {
    "applied": 10,
    "responses": 2,
    "interviews": 1,
    "keywords": ["DevOps", "Remote"]
  },
  "feedback_source": "manual"
}
```

### Get Insights
```http
GET /agentflow/api/insights/:type
```

**Types:** `job_application`, `media_download`, `browser_automation`

**Response:**
```json
{
  "success": true,
  "type": "job_application",
  "insights": {
    "total_applications": 127,
    "responses_received": 15,
    "response_rate": "11.8%",
    "best_time_to_apply": {
      "hour": "9:00",
      "response_rate": "24%",
      "sample_size": 30
    },
    "top_keywords": [
      { "keyword": "DevOps", "count": 8 },
      { "keyword": "Remote", "count": 5 }
    ],
    "recommendation": "Apply around 9:00 AM for best response rate"
  },
  "outcomes": [ /* recent outcomes */ ],
  "total_outcomes": 127
}
```

### Outcome Trends
```http
GET /agentflow/api/outcomes/trends/:type?days=30
```

### Top Tasks
```http
GET /agentflow/api/analytics/top-tasks?metric=fastest
```

**Metrics:** fastest, most_successful, recent

### Failure Analysis
```http
GET /agentflow/api/analytics/failures?days=7
```

---

## Scheduled Tasks API

### Get Scheduled Tasks
```http
GET /agentflow/api/scheduled?enabled=true
```

**Query Parameters:**
- `enabled` (boolean, optional): Filter by enabled status

### Get Upcoming
```http
GET /agentflow/api/scheduled/upcoming?limit=10
```

### Create Scheduled Task
```http
POST /agentflow/api/scheduled
Content-Type: application/json
```

**Body:**
```json
{
  "description": "Apply to jobs daily",
  "schedule": "daily at 9:00",
  "bot_id": "session2",
  "enabled": true
}
```

**Schedule Formats:**
- Interval: `every 6h`, `every 30m`, `every 1d`
- Daily: `daily at 9:00`, `daily at 14:30`
- Cron: `0 9 * * *`

### Get Single Scheduled Task
```http
GET /agentflow/api/scheduled/:id
```

Includes `recent_runs`.

### Update Scheduled Task
```http
PATCH /agentflow/api/scheduled/:id
Content-Type: application/json
```

### Delete Scheduled Task
```http
DELETE /agentflow/api/scheduled/:id
```

### Pause Task
```http
POST /agentflow/api/scheduled/:id/pause
```

### Resume Task
```http
POST /agentflow/api/scheduled/:id/resume
```

### Run Now
```http
POST /agentflow/api/scheduled/:id/run
```

Triggers immediate execution.

---

## Admin API

### Hot-Reload Extension
```http
POST /agentflow/api/admin/reload
X-Admin-Token: your-token
```

Reloads extension without restarting gateway.

---

## WebSocket API

### Connection
```javascript
const ws = new WebSocket('ws://localhost:18789/agentflow/ws');
```

### Subscribe to Events
```javascript
ws.send(JSON.stringify({
  type: 'subscribe',
  events: ['task:created', 'task:completed', 'bot:status']
}));
```

### Events

**task:created**
```json
{
  "type": "task:created",
  "task": { /* task object */ },
  "timestamp": 1710759600000
}
```

**task:progress**
```json
{
  "type": "task:progress",
  "taskId": "uuid",
  "botId": "session2",
  "progress": "⚙️ Processing...",
  "timestamp": 1710759600000
}
```

**task:completed**
```json
{
  "type": "task:completed",
  "task": { /* task object */ },
  "timestamp": 1710759600000
}
```

**task:failed**
```json
{
  "type": "task:failed",
  "task": { /* task object */ },
  "timestamp": 1710759600000
}
```

**bot:status**
```json
{
  "type": "bot:status",
  "botId": "session2",
  "status": "running",
  "currentTaskId": "uuid",
  "timestamp": 1710759600000
}
```

**outcome:recorded**
```json
{
  "type": "outcome:recorded",
  "outcome": { /* outcome object */ },
  "timestamp": 1710759600000
}
```

### Ping/Pong
```javascript
// Client sends ping
ws.send(JSON.stringify({ type: 'ping' }));

// Server responds
// { type: 'pong', timestamp: 1710759600000 }
```

---

## Error Responses

All errors follow this format:

```json
{
  "success": false,
  "error": "Error message here"
}
```

**HTTP Status Codes:**
- `200` OK
- `201` Created
- `400` Bad Request
- `401` Unauthorized
- `404` Not Found
- `500` Internal Server Error

---

## Rate Limiting

**Default limits:**
- 100 requests per 15 minutes per IP
- WebSocket: 100 concurrent connections

**Rate limit headers:**
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1710760500
```

---

## Examples

### Create and Monitor Task (cURL)

```bash
# Create task
TASK_ID=$(curl -X POST http://localhost:18789/agentflow/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"description":"Apply to 10 jobs"}' \
  | jq -r '.task.id')

echo "Task created: $TASK_ID"

# Monitor progress
curl "http://localhost:18789/agentflow/api/tasks/$TASK_ID" | jq '.task.status'
```

### WebSocket Client (JavaScript)

```javascript
const ws = new WebSocket('ws://localhost:18789/agentflow/ws');

ws.onopen = () => {
  console.log('Connected');
  ws.send(JSON.stringify({
    type: 'subscribe',
    events: ['*'] // Subscribe to all events
  }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Event:', data.type, data);
};
```

### Schedule Daily Job (JavaScript)

```javascript
fetch('http://localhost:18789/agentflow/api/scheduled', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    description: 'Apply to jobs',
    schedule: 'daily at 9:00',
    bot_id: 'session2'
  })
})
.then(r => r.json())
.then(data => console.log('Scheduled:', data.task));
```

---

**Version:** 1.0.0  
**Last Updated:** 2026-03-18  
**Author:** Till Thelet
