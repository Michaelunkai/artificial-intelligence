/**
 * AgentFlow Dashboard - Frontend JavaScript
 * @author Till Thelet
 * @version 1.0.0
 */

const API_BASE = '/agentflow/api';
let currentFilter = 'all';
let refreshInterval;
let wsClient = null;

// Initialize dashboard on load
document.addEventListener('DOMContentLoaded', () => {
  console.log('[AgentFlow] Dashboard initializing...');
  
  // Load initial data
  loadBotStatuses();
  loadActiveTasks();
  loadTaskHistory();
  loadAnalytics();
  
  // Initialize WebSocket for real-time updates
  initWebSocket();
  
  // Set up fallback auto-refresh every 5 seconds (in case WS fails)
  refreshInterval = setInterval(() => {
    if (!wsClient || !wsClient.isConnected) {
      loadBotStatuses();
      loadActiveTasks();
      loadAnalytics();
    }
  }, 5000);
  
  console.log('[AgentFlow] Dashboard ready');
});

/**
 * Initialize WebSocket connection for real-time updates
 */
function initWebSocket() {
  if (typeof AgentFlowWebSocket === 'undefined') {
    console.log('[AgentFlow] WebSocket client not available, using polling');
    return;
  }
  
  try {
    wsClient = new AgentFlowWebSocket({
      reconnectDelay: 3000,
      maxReconnectAttempts: 10
    });
    
    // Update connection status in UI
    wsClient.on('connected', () => {
      updateConnectionStatus(true);
      showToast('Real-time updates connected', 'success');
    });
    
    wsClient.on('disconnected', () => {
      updateConnectionStatus(false);
    });
    
    // Handle task events
    wsClient.on('task:created', (data) => {
      console.log('[WS] Task created:', data.task.id);
      loadActiveTasks();
      loadAnalytics();
    });
    
    wsClient.on('task:progress', (data) => {
      console.log('[WS] Task progress:', data.taskId);
      updateTaskProgress(data.taskId, data.progress);
    });
    
    wsClient.on('task:completed', (data) => {
      console.log('[WS] Task completed:', data.task.id);
      loadActiveTasks();
      loadTaskHistory();
      loadAnalytics();
      showToast(`Task completed: ${data.task.description.substring(0, 30)}...`, 'success');
    });
    
    wsClient.on('task:failed', (data) => {
      console.log('[WS] Task failed:', data.task.id);
      loadActiveTasks();
      loadTaskHistory();
      loadAnalytics();
      showToast(`Task failed: ${data.task.description.substring(0, 30)}...`, 'error');
    });
    
    // Handle bot status events
    wsClient.on('bot:status', (data) => {
      console.log('[WS] Bot status:', data.botId, data.status);
      updateBotStatusInUI(data.botId, data.status);
    });
    
    console.log('[AgentFlow] WebSocket client initialized');
  } catch (error) {
    console.error('[AgentFlow] WebSocket init failed:', error);
  }
}

/**
 * Update connection status indicator in UI
 */
function updateConnectionStatus(connected) {
  const statusEl = document.getElementById('connectionStatus');
  if (statusEl) {
    if (connected) {
      statusEl.innerHTML = '<span class="badge badge-success">● Real-time Connected</span>';
    } else {
      statusEl.innerHTML = '<span class="badge badge-warning">● Polling Mode</span>';
    }
  }
}

/**
 * Update task progress in UI without full reload
 */
function updateTaskProgress(taskId, progress) {
  const taskCards = document.querySelectorAll('.task-card');
  taskCards.forEach(card => {
    if (card.dataset.taskId === taskId) {
      const progressEl = card.querySelector('.task-progress');
      if (progressEl) {
        progressEl.textContent = progress;
      }
    }
  });
}

/**
 * Update bot status in UI without full reload
 */
function updateBotStatusInUI(botId, status) {
  const botCards = document.querySelectorAll('.bot-card');
  botCards.forEach(card => {
    if (card.dataset.botId === botId) {
      const statusEl = card.querySelector('.bot-status');
      if (statusEl) {
        statusEl.textContent = status;
        statusEl.className = `bot-status status-${status}`;
      }
      card.className = `bot-card bot-${status}`;
    }
  });
}

/**
 * Load bot statuses
 */
async function loadBotStatuses() {
  try {
    const response = await fetch(`${API_BASE}/bots`);
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    const botGrid = document.getElementById('botGrid');
    botGrid.innerHTML = '';
    
    data.bots.forEach(bot => {
      const card = createBotCard(bot);
      botGrid.appendChild(card);
    });
  } catch (error) {
    console.error('[AgentFlow] Failed to load bot statuses:', error);
    showToast('Failed to load bot statuses', 'error');
  }
}

/**
 * Create bot status card
 */
function createBotCard(bot) {
  const div = document.createElement('div');
  const statusClass = bot.status === 'idle' ? 'bot-idle' : 
                      bot.status === 'running' ? 'bot-running' : 'bot-error';
  
  const successRate = bot.total_tasks > 0 
    ? ((bot.successful_tasks / bot.total_tasks) * 100).toFixed(1)
    : '0';
  
  div.className = `bot-card ${statusClass}`;
  div.innerHTML = `
    <div class="bot-header">
      <div class="bot-name">${bot.bot_id}</div>
      <span class="bot-status status-${bot.status}">${bot.status}</span>
    </div>
    <div class="bot-stats">
      <div class="bot-stat">
        <span class="bot-stat-label">Total Tasks:</span>
        <span class="bot-stat-value">${bot.total_tasks || 0}</span>
      </div>
      <div class="bot-stat">
        <span class="bot-stat-label">Success Rate:</span>
        <span class="bot-stat-value">${successRate}%</span>
      </div>
      <div class="bot-stat">
        <span class="bot-stat-label">Avg Duration:</span>
        <span class="bot-stat-value">${formatDuration(bot.avg_duration_seconds)}</span>
      </div>
      ${bot.current_task_id ? `
        <div class="bot-stat">
          <span class="bot-stat-label">Current Task:</span>
          <span class="bot-stat-value" style="font-size: 0.8rem;">
            ${bot.current_task_id.substring(0, 8)}...
          </span>
        </div>
      ` : ''}
    </div>
  `;
  
  return div;
}

/**
 * Load active (running) tasks
 */
async function loadActiveTasks() {
  try {
    const response = await fetch(`${API_BASE}/tasks?status=running&limit=10`);
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    const taskList = document.getElementById('activeTaskList');
    
    if (data.tasks.length === 0) {
      taskList.innerHTML = '<div class="empty-state">No active tasks</div>';
      return;
    }
    
    taskList.innerHTML = '';
    data.tasks.forEach(task => {
      const card = createTaskCard(task);
      taskList.appendChild(card);
    });
  } catch (error) {
    console.error('[AgentFlow] Failed to load active tasks:', error);
  }
}

/**
 * Load task history
 */
async function loadTaskHistory() {
  try {
    const statusParam = currentFilter === 'all' ? '' : `?status=${currentFilter}`;
    const response = await fetch(`${API_BASE}/tasks${statusParam}&limit=20`);
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    const taskList = document.getElementById('historyTaskList');
    
    if (data.tasks.length === 0) {
      taskList.innerHTML = '<div class="empty-state">No tasks found</div>';
      return;
    }
    
    taskList.innerHTML = '';
    data.tasks.forEach(task => {
      if (task.status !== 'running') { // Don't show running tasks in history
        const card = createTaskCard(task);
        taskList.appendChild(card);
      }
    });
  } catch (error) {
    console.error('[AgentFlow] Failed to load task history:', error);
  }
}

/**
 * Create task card element
 */
function createTaskCard(task) {
  const div = document.createElement('div');
  div.className = `task-card task-${task.status}`;
  
  const duration = task.started_at && task.completed_at
    ? formatDuration((task.completed_at - task.started_at) / 1000)
    : task.started_at
    ? `Running: ${formatDuration((Date.now() - task.started_at) / 1000)}`
    : 'Not started';
  
  const statusEmoji = {
    'pending': '⏳',
    'running': '⚙️',
    'completed': '✅',
    'failed': '❌'
  }[task.status] || '❓';
  
  div.innerHTML = `
    <div class="task-header">
      <div class="task-description">
        ${statusEmoji} ${escapeHtml(task.description)}
      </div>
    </div>
    <div class="task-meta">
      <span>Bot: <strong>${task.bot_id}</strong></span>
      <span>Created: ${formatDate(task.created_at)}</span>
      ${task.completed_at ? `<span>Duration: ${duration}</span>` : ''}
    </div>
    ${task.progress ? `
      <div class="task-progress">
        ${escapeHtml(task.progress)}
      </div>
    ` : ''}
    ${task.error ? `
      <div class="task-progress" style="color: var(--danger);">
        Error: ${escapeHtml(task.error)}
      </div>
    ` : ''}
  `;
  
  return div;
}

/**
 * Load analytics data
 */
async function loadAnalytics() {
  try {
    const response = await fetch(`${API_BASE}/analytics?range=7d`);
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    const { overall, perBot, timeline } = data.analytics;
    
    // Update overview stats
    document.getElementById('statTotalTasks').textContent = overall.total_tasks || 0;
    
    const successRate = overall.total_tasks > 0
      ? ((overall.completed / overall.total_tasks) * 100).toFixed(1)
      : '0';
    document.getElementById('statSuccessRate').textContent = `${successRate}%`;
    
    document.getElementById('statAvgDuration').textContent = 
      formatDuration(overall.avg_duration_seconds);
    
    document.getElementById('statActiveNow').textContent = overall.running || 0;
    
    // Render charts if chart library is available
    if (typeof createDonutChart !== 'undefined') {
      renderCharts(overall, perBot, timeline);
    }
    
    // Update performance table
    renderPerformanceTable(perBot);
  } catch (error) {
    console.error('[AgentFlow] Failed to load analytics:', error);
  }
}

/**
 * Render analytics charts
 */
function renderCharts(overall, perBot, timeline) {
  // Status distribution donut chart
  const statusDonutContainer = document.getElementById('statusDonutChart');
  if (statusDonutContainer) {
    const statusData = [
      { label: 'Completed', value: overall.completed || 0, color: chartColors.completed },
      { label: 'Failed', value: overall.failed || 0, color: chartColors.failed },
      { label: 'Running', value: overall.running || 0, color: chartColors.running },
      { label: 'Pending', value: overall.pending || 0, color: chartColors.pending }
    ].filter(d => d.value > 0);
    
    createDonutChart(statusDonutContainer, statusData, {
      width: 200,
      height: 200,
      innerRadius: 50,
      outerRadius: 80
    });
  }
  
  // Tasks per bot bar chart
  const botBarContainer = document.getElementById('botBarChart');
  if (botBarContainer && perBot) {
    const botData = perBot.map(bot => ({
      label: bot.bot_id,
      value: bot.total_tasks || 0,
      color: chartColors[bot.bot_id] || chartColors.primary
    }));
    
    createHorizontalBarChart(botBarContainer, botData, {
      width: 350,
      barHeight: 28
    });
  }
  
  // Timeline chart
  const timelineContainer = document.getElementById('timelineChart');
  if (timelineContainer && timeline && timeline.length > 0) {
    const timelineData = timeline
      .reverse() // Oldest first
      .map(day => ({
        label: day.date ? day.date.substring(5) : '', // MM-DD
        value: day.total || 0
      }));
    
    createLineChart(timelineContainer, timelineData, {
      width: Math.min(window.innerWidth - 100, 800),
      height: 180,
      showArea: true
    });
  }
  
  // Success rate ring
  const successRateRing = document.getElementById('successRateRing');
  if (successRateRing) {
    const rate = overall.total_tasks > 0
      ? (overall.completed / overall.total_tasks) * 100
      : 0;
    
    createProgressRing(successRateRing, rate, {
      size: 60,
      strokeWidth: 6,
      color: rate > 80 ? chartColors.success : rate > 50 ? chartColors.warning : chartColors.danger
    });
  }
}

/**
 * Render per-bot performance table
 */
function renderPerformanceTable(perBot) {
  const container = document.getElementById('performanceTable');
  
  if (!perBot || perBot.length === 0) {
    container.innerHTML = '<div class="empty-state">No data available</div>';
    return;
  }
  
  const table = document.createElement('table');
  table.innerHTML = `
    <thead>
      <tr>
        <th>Bot</th>
        <th>Total Tasks</th>
        <th>Completed</th>
        <th>Failed</th>
        <th>Success Rate</th>
        <th>Avg Duration</th>
      </tr>
    </thead>
    <tbody>
      ${perBot.map(bot => `
        <tr>
          <td><strong>${bot.bot_id}</strong></td>
          <td>${bot.total_tasks}</td>
          <td style="color: var(--success);">${bot.completed}</td>
          <td style="color: var(--danger);">${bot.failed}</td>
          <td><strong>${bot.success_rate}%</strong></td>
          <td>${formatDuration(bot.avg_duration_seconds)}</td>
        </tr>
      `).join('')}
    </tbody>
  `;
  
  container.innerHTML = '';
  container.appendChild(table);
}

/**
 * Show new task modal
 */
function showNewTaskModal() {
  const modal = document.getElementById('newTaskModal');
  modal.classList.add('active');
  
  // Focus on description field
  document.getElementById('taskDescription').focus();
}

/**
 * Close new task modal
 */
function closeNewTaskModal() {
  const modal = document.getElementById('newTaskModal');
  modal.classList.remove('active');
  
  // Clear form
  document.getElementById('taskDescription').value = '';
  document.getElementById('taskBot').value = '';
}

/**
 * Create new task
 */
async function createTask() {
  const description = document.getElementById('taskDescription').value.trim();
  const bot_id = document.getElementById('taskBot').value || undefined;
  
  if (!description) {
    showToast('Please enter a task description', 'error');
    return;
  }
  
  try {
    const response = await fetch(`${API_BASE}/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ description, bot_id })
    });
    
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    showToast(`Task created and assigned to ${data.task.bot_id}`, 'success');
    
    closeNewTaskModal();
    
    // Refresh views
    setTimeout(() => {
      loadActiveTasks();
      loadTaskHistory();
      loadAnalytics();
    }, 500);
  } catch (error) {
    console.error('[AgentFlow] Failed to create task:', error);
    showToast('Failed to create task', 'error');
  }
}

/**
 * Quick action buttons
 */
async function quickAction(type, bot) {
  const descriptions = {
    'job': 'Apply to 10 DevOps jobs on LinkedIn',
    'game': 'Download 5 new games matching my preferences',
    'tv': 'Download latest TV show episodes',
    'browser': 'Open browser and navigate to homepage'
  };
  
  const description = descriptions[type] || 'Perform task';
  
  try {
    const response = await fetch(`${API_BASE}/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ description, bot_id: bot })
    });
    
    const data = await response.json();
    
    if (!data.success) throw new Error(data.error);
    
    showToast(`Task sent to ${bot}`, 'success');
    
    // Refresh views
    setTimeout(() => {
      loadActiveTasks();
      loadAnalytics();
    }, 500);
  } catch (error) {
    console.error('[AgentFlow] Quick action failed:', error);
    showToast('Failed to create task', 'error');
  }
}

/**
 * Filter tasks by status
 */
function filterTasks(status) {
  currentFilter = status;
  loadTaskHistory();
}

/**
 * Refresh all data
 */
function refreshAll() {
  loadBotStatuses();
  loadActiveTasks();
  loadTaskHistory();
  loadAnalytics();
  
  showToast('Dashboard refreshed', 'info');
}

/**
 * Show toast notification
 */
function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  
  container.appendChild(toast);
  
  // Auto-remove after 3 seconds
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

/**
 * Utility: Format duration in seconds to human-readable
 */
function formatDuration(seconds) {
  if (!seconds || seconds < 0) return '0s';
  
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  
  if (hrs > 0) return `${hrs}h ${mins}m`;
  if (mins > 0) return `${mins}m ${secs}s`;
  return `${secs}s`;
}

/**
 * Utility: Format timestamp to human-readable date
 */
function formatDate(timestamp) {
  if (!timestamp) return 'N/A';
  
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  
  // Recent times
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 7) return `${diffDays}d ago`;
  
  // Older: show actual date
  return date.toLocaleDateString('en-US', { 
    month: 'short', 
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

/**
 * Utility: Escape HTML to prevent XSS
 */
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Close modal on outside click
document.addEventListener('click', (e) => {
  const modal = document.getElementById('newTaskModal');
  if (e.target === modal) {
    closeNewTaskModal();
  }
});

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  // Escape to close modal
  if (e.key === 'Escape') {
    closeNewTaskModal();
  }
  
  // Ctrl/Cmd + K to open new task modal
  if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
    e.preventDefault();
    showNewTaskModal();
  }
  
  // Ctrl/Cmd + R to refresh (prevent default browser refresh)
  if ((e.ctrlKey || e.metaKey) && e.key === 'r') {
    e.preventDefault();
    refreshAll();
  }
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
  if (refreshInterval) {
    clearInterval(refreshInterval);
  }
});
