/**
 * Analytics API Module
 * Provides insights, metrics, and outcome tracking
 * @author Till Thelet
 */

module.exports = function(app, db, logger) {
  const express = require('express');
  
  /**
   * Get overall analytics
   * GET /agentflow/api/analytics?range=7d
   */
  app.get('/agentflow/api/analytics', (req, res) => {
    try {
      const range = req.query.range || '7d'; // 7d, 30d, 90d, all
      
      let timeFilter = '';
      let cutoff = 0;
      
      if (range !== 'all') {
        const days = parseInt(range.replace('d', ''));
        cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
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
          AVG(CASE 
            WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
            THEN (completed_at - started_at) / 1000.0 
            ELSE NULL 
          END) as avg_duration_seconds,
          MIN(created_at) as oldest_task,
          MAX(created_at) as newest_task
        FROM tasks ${timeFilter}
      `).get();
      
      // Per-bot stats
      const perBot = db.prepare(`
        SELECT 
          bot_id,
          COUNT(*) as total_tasks,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
          AVG(CASE 
            WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
            THEN (completed_at - started_at) / 1000.0 
            ELSE NULL 
          END) as avg_duration_seconds,
          ROUND(
            CAST(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS REAL) / 
            NULLIF(COUNT(*), 0) * 100,
            2
          ) as success_rate
        FROM tasks ${timeFilter}
        GROUP BY bot_id
        ORDER BY total_tasks DESC
      `).all();
      
      // Task types (inferred from keywords)
      const taskTypes = db.prepare(`
        SELECT 
          CASE 
            WHEN description LIKE '%job%' OR description LIKE '%apply%' OR description LIKE '%linkedin%' THEN 'job_application'
            WHEN description LIKE '%game%' OR description LIKE '%download%' THEN 'media_download'
            WHEN description LIKE '%browser%' OR description LIKE '%web%' THEN 'browser_automation'
            ELSE 'general'
          END as type,
          COUNT(*) as count,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
          AVG(CASE 
            WHEN completed_at IS NOT NULL AND started_at IS NOT NULL 
            THEN (completed_at - started_at) / 1000.0 
            ELSE NULL 
          END) as avg_duration
        FROM tasks ${timeFilter}
        GROUP BY type
        ORDER BY count DESC
      `).all();
      
      // Timeline data (tasks per day)
      const timeline = db.prepare(`
        SELECT 
          DATE(created_at / 1000, 'unixepoch', 'localtime') as date,
          COUNT(*) as total,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
        FROM tasks ${timeFilter}
        GROUP BY date
        ORDER BY date DESC
        LIMIT 30
      `).all();
      
      res.json({
        success: true,
        analytics: {
          overall,
          perBot,
          taskTypes,
          timeline,
          timeRange: range
        }
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Get analytics failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Record outcome for a task
   * POST /agentflow/api/outcomes
   * Body: { task_id, type, metrics, feedback_source }
   */
  app.post('/agentflow/api/outcomes', express.json(), (req, res) => {
    try {
      const { task_id, type, metrics, feedback_source } = req.body;
      
      if (!task_id || !type || !metrics) {
        return res.status(400).json({
          success: false,
          error: 'task_id, type, and metrics required'
        });
      }
      
      // Verify task exists
      const task = db.prepare('SELECT id FROM tasks WHERE id = ?').get(task_id);
      if (!task) {
        return res.status(404).json({
          success: false,
          error: 'Task not found'
        });
      }
      
      const outcomeId = require('uuid').v4();
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
        feedback_source || 'manual',
        now
      );
      
      logger.info(`[AgentFlow Analytics] Outcome recorded: ${outcomeId} for task ${task_id}`);
      
      res.status(201).json({
        success: true,
        outcome: {
          id: outcomeId,
          task_id,
          type,
          metrics,
          recorded_at: now
        }
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Record outcome failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get insights for a specific outcome type
   * GET /agentflow/api/insights/:type
   */
  app.get('/agentflow/api/insights/:type', (req, res) => {
    try {
      const type = req.params.type;
      
      const stmt = db.prepare(`
        SELECT o.*, t.description, t.bot_id
        FROM outcomes o
        JOIN tasks t ON o.task_id = t.id
        WHERE o.type = ?
        ORDER BY o.recorded_at DESC
        LIMIT 100
      `);
      
      const outcomes = stmt.all(type);
      
      // Parse JSON metrics
      outcomes.forEach(o => {
        o.metrics = JSON.parse(o.metrics);
      });
      
      // Calculate insights based on type
      const insights = calculateInsights(type, outcomes);
      
      res.json({
        success: true,
        type,
        insights,
        outcomes: outcomes.slice(0, 20), // Return top 20 for display
        total_outcomes: outcomes.length
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Get insights failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get outcome trends over time
   * GET /agentflow/api/outcomes/trends/:type
   */
  app.get('/agentflow/api/outcomes/trends/:type', (req, res) => {
    try {
      const type = req.params.type;
      const days = parseInt(req.query.days) || 30;
      const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
      
      const stmt = db.prepare(`
        SELECT 
          DATE(recorded_at / 1000, 'unixepoch', 'localtime') as date,
          COUNT(*) as count,
          metrics
        FROM outcomes
        WHERE type = ? AND recorded_at >= ?
        GROUP BY date
        ORDER BY date DESC
      `);
      
      const trends = stmt.all(type, cutoff);
      
      // Parse metrics for aggregation
      trends.forEach(t => {
        t.metrics = JSON.parse(t.metrics);
      });
      
      res.json({
        success: true,
        type,
        trends,
        days
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Get trends failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get top performing tasks
   * GET /agentflow/api/analytics/top-tasks
   */
  app.get('/agentflow/api/analytics/top-tasks', (req, res) => {
    try {
      const metric = req.query.metric || 'fastest'; // fastest, most_successful, recent
      
      let orderBy = '';
      if (metric === 'fastest') {
        orderBy = '(completed_at - started_at) ASC';
      } else if (metric === 'recent') {
        orderBy = 'created_at DESC';
      }
      
      const stmt = db.prepare(`
        SELECT 
          id,
          description,
          bot_id,
          status,
          created_at,
          started_at,
          completed_at,
          (completed_at - started_at) / 1000.0 as duration_seconds
        FROM tasks
        WHERE status = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL
        ORDER BY ${orderBy}
        LIMIT 10
      `);
      
      const topTasks = stmt.all();
      
      res.json({
        success: true,
        metric,
        tasks: topTasks
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Get top tasks failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
  
  /**
   * Get failure analysis
   * GET /agentflow/api/analytics/failures
   */
  app.get('/agentflow/api/analytics/failures', (req, res) => {
    try {
      const days = parseInt(req.query.days) || 7;
      const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
      
      const failures = db.prepare(`
        SELECT 
          id,
          description,
          bot_id,
          error,
          created_at
        FROM tasks
        WHERE status = 'failed' AND created_at >= ?
        ORDER BY created_at DESC
        LIMIT 50
      `).all(cutoff);
      
      // Categorize errors
      const errorCategories = {};
      failures.forEach(f => {
        if (!f.error) return;
        
        let category = 'other';
        if (f.error.includes('timeout')) category = 'timeout';
        else if (f.error.includes('network') || f.error.includes('connection')) category = 'network';
        else if (f.error.includes('browser')) category = 'browser';
        else if (f.error.includes('not found')) category = 'not_found';
        else if (f.error.includes('permission')) category = 'permission';
        
        errorCategories[category] = (errorCategories[category] || 0) + 1;
      });
      
      res.json({
        success: true,
        failures: failures.slice(0, 20), // Top 20 for display
        total_failures: failures.length,
        error_categories: errorCategories,
        days
      });
    } catch (error) {
      logger.error('[AgentFlow Analytics] Get failures failed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });
};

/**
 * Calculate insights from outcomes
 */
function calculateInsights(type, outcomes) {
  if (outcomes.length === 0) {
    return {
      message: 'Not enough data for insights yet',
      sample_size: 0
    };
  }
  
  if (type === 'job_application') {
    const totalApplications = outcomes.length;
    const withResponses = outcomes.filter(o => o.metrics.responses > 0);
    const responsesReceived = withResponses.length;
    const responseRate = (responsesReceived / totalApplications * 100).toFixed(2);
    
    // Best times analysis
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
        hour: parseInt(hour),
        total: data.total,
        responses: data.responses,
        rate: (data.responses / data.total * 100).toFixed(2)
      }))
      .filter(h => h.total >= 3) // Min 3 samples
      .sort((a, b) => parseFloat(b.rate) - parseFloat(a.rate))[0];
    
    // Best keywords
    const keywordPerformance = {};
    withResponses.forEach(o => {
      if (o.metrics.keywords) {
        o.metrics.keywords.forEach(kw => {
          if (!keywordPerformance[kw]) keywordPerformance[kw] = 0;
          keywordPerformance[kw]++;
        });
      }
    });
    
    const topKeywords = Object.entries(keywordPerformance)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([kw, count]) => ({ keyword: kw, count }));
    
    return {
      total_applications: totalApplications,
      responses_received: responsesReceived,
      response_rate: `${responseRate}%`,
      best_time_to_apply: bestHour ? {
        hour: `${bestHour.hour}:00`,
        response_rate: `${bestHour.rate}%`,
        sample_size: bestHour.total
      } : null,
      top_keywords: topKeywords,
      recommendation: bestHour 
        ? `Apply around ${bestHour.hour}:00 for ${bestHour.rate}% response rate`
        : 'Keep tracking to find best application times'
    };
  }
  
  if (type === 'media_download') {
    const totalDownloads = outcomes.length;
    const successful = outcomes.filter(o => o.metrics.success === true).length;
    const successRate = (successful / totalDownloads * 100).toFixed(2);
    
    const avgSize = outcomes
      .filter(o => o.metrics.size_mb)
      .reduce((sum, o) => sum + o.metrics.size_mb, 0) / totalDownloads;
    
    return {
      total_downloads: totalDownloads,
      successful: successful,
      failed: totalDownloads - successful,
      success_rate: `${successRate}%`,
      avg_size_mb: avgSize.toFixed(2)
    };
  }
  
  // Generic insights for other types
  return {
    total_outcomes: outcomes.length,
    message: 'Custom insights for this type are not yet implemented'
  };
}
