/**
 * AgentFlow Charts - SVG-based data visualizations
 * No external dependencies (pure SVG)
 * @author Till Thelet
 */

/**
 * Create a simple SVG bar chart
 */
function createBarChart(container, data, options = {}) {
  const {
    width = 400,
    height = 200,
    barColor = '#2563eb',
    labelColor = '#cbd5e1',
    gridColor = '#334155'
  } = options;
  
  if (!data || data.length === 0) {
    container.innerHTML = '<div class="empty-state">No data available</div>';
    return;
  }
  
  const maxValue = Math.max(...data.map(d => d.value));
  const barWidth = (width - 60) / data.length - 10;
  const chartHeight = height - 40;
  
  let svg = `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <!-- Grid lines -->
      ${[0, 0.25, 0.5, 0.75, 1].map(ratio => `
        <line 
          x1="50" y1="${20 + chartHeight * (1 - ratio)}" 
          x2="${width - 10}" y2="${20 + chartHeight * (1 - ratio)}"
          stroke="${gridColor}" stroke-dasharray="2"
        />
        <text x="45" y="${25 + chartHeight * (1 - ratio)}" 
          text-anchor="end" fill="${labelColor}" font-size="10">
          ${Math.round(maxValue * ratio)}
        </text>
      `).join('')}
      
      <!-- Bars -->
      ${data.map((d, i) => {
        const barHeight = (d.value / maxValue) * chartHeight;
        const x = 60 + i * (barWidth + 10);
        const y = 20 + chartHeight - barHeight;
        
        return `
          <rect 
            x="${x}" y="${y}" 
            width="${barWidth}" height="${barHeight}"
            fill="${d.color || barColor}"
            rx="3"
          >
            <title>${d.label}: ${d.value}</title>
          </rect>
          <text x="${x + barWidth / 2}" y="${height - 5}" 
            text-anchor="middle" fill="${labelColor}" font-size="10"
            transform="rotate(-45, ${x + barWidth / 2}, ${height - 5})">
            ${d.label}
          </text>
        `;
      }).join('')}
    </svg>
  `;
  
  container.innerHTML = svg;
}

/**
 * Create a donut/pie chart
 */
function createDonutChart(container, data, options = {}) {
  const {
    width = 200,
    height = 200,
    innerRadius = 40,
    outerRadius = 80,
    labelColor = '#cbd5e1'
  } = options;
  
  if (!data || data.length === 0) {
    container.innerHTML = '<div class="empty-state">No data available</div>';
    return;
  }
  
  const total = data.reduce((sum, d) => sum + d.value, 0);
  const cx = width / 2;
  const cy = height / 2;
  
  let currentAngle = -90; // Start from top
  
  const slices = data.map(d => {
    const angle = (d.value / total) * 360;
    const startAngle = currentAngle;
    currentAngle += angle;
    
    const startRad = (startAngle * Math.PI) / 180;
    const endRad = (currentAngle * Math.PI) / 180;
    
    const x1 = cx + outerRadius * Math.cos(startRad);
    const y1 = cy + outerRadius * Math.sin(startRad);
    const x2 = cx + outerRadius * Math.cos(endRad);
    const y2 = cy + outerRadius * Math.sin(endRad);
    
    const x3 = cx + innerRadius * Math.cos(endRad);
    const y3 = cy + innerRadius * Math.sin(endRad);
    const x4 = cx + innerRadius * Math.cos(startRad);
    const y4 = cy + innerRadius * Math.sin(startRad);
    
    const largeArc = angle > 180 ? 1 : 0;
    
    const path = `
      M ${x1} ${y1}
      A ${outerRadius} ${outerRadius} 0 ${largeArc} 1 ${x2} ${y2}
      L ${x3} ${y3}
      A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${x4} ${y4}
      Z
    `;
    
    return { ...d, path, midAngle: startAngle + angle / 2 };
  });
  
  const svg = `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      ${slices.map(slice => `
        <path d="${slice.path}" fill="${slice.color}">
          <title>${slice.label}: ${slice.value} (${((slice.value / total) * 100).toFixed(1)}%)</title>
        </path>
      `).join('')}
      
      <!-- Center text -->
      <text x="${cx}" y="${cy}" text-anchor="middle" fill="${labelColor}" font-size="24" font-weight="bold">
        ${total}
      </text>
      <text x="${cx}" y="${cy + 15}" text-anchor="middle" fill="${labelColor}" font-size="10">
        total
      </text>
    </svg>
    
    <!-- Legend -->
    <div class="chart-legend">
      ${slices.map(slice => `
        <div class="legend-item">
          <span class="legend-color" style="background: ${slice.color}"></span>
          <span class="legend-label">${slice.label}: ${slice.value}</span>
        </div>
      `).join('')}
    </div>
  `;
  
  container.innerHTML = svg;
}

/**
 * Create a line/area chart
 */
function createLineChart(container, data, options = {}) {
  const {
    width = 500,
    height = 200,
    lineColor = '#2563eb',
    areaColor = 'rgba(37, 99, 235, 0.2)',
    labelColor = '#cbd5e1',
    gridColor = '#334155',
    showArea = true
  } = options;
  
  if (!data || data.length < 2) {
    container.innerHTML = '<div class="empty-state">Not enough data for chart</div>';
    return;
  }
  
  const maxValue = Math.max(...data.map(d => d.value)) * 1.1;
  const minValue = 0;
  const chartWidth = width - 60;
  const chartHeight = height - 50;
  const stepX = chartWidth / (data.length - 1);
  
  const points = data.map((d, i) => ({
    x: 50 + i * stepX,
    y: 20 + chartHeight - ((d.value - minValue) / (maxValue - minValue)) * chartHeight,
    ...d
  }));
  
  const linePath = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
  const areaPath = linePath + ` L ${points[points.length - 1].x} ${20 + chartHeight} L ${points[0].x} ${20 + chartHeight} Z`;
  
  const svg = `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <!-- Grid lines -->
      ${[0, 0.25, 0.5, 0.75, 1].map(ratio => `
        <line 
          x1="50" y1="${20 + chartHeight * (1 - ratio)}" 
          x2="${width - 10}" y2="${20 + chartHeight * (1 - ratio)}"
          stroke="${gridColor}" stroke-dasharray="2"
        />
        <text x="45" y="${25 + chartHeight * (1 - ratio)}" 
          text-anchor="end" fill="${labelColor}" font-size="10">
          ${Math.round(minValue + (maxValue - minValue) * ratio)}
        </text>
      `).join('')}
      
      <!-- Area fill -->
      ${showArea ? `<path d="${areaPath}" fill="${areaColor}" />` : ''}
      
      <!-- Line -->
      <path d="${linePath}" fill="none" stroke="${lineColor}" stroke-width="2" stroke-linecap="round" />
      
      <!-- Data points -->
      ${points.map(p => `
        <circle cx="${p.x}" cy="${p.y}" r="4" fill="${lineColor}">
          <title>${p.label}: ${p.value}</title>
        </circle>
      `).join('')}
      
      <!-- X-axis labels -->
      ${points.filter((p, i) => i % Math.ceil(points.length / 7) === 0).map(p => `
        <text x="${p.x}" y="${height - 5}" 
          text-anchor="middle" fill="${labelColor}" font-size="9">
          ${p.label}
        </text>
      `).join('')}
    </svg>
  `;
  
  container.innerHTML = svg;
}

/**
 * Create a horizontal bar chart (good for bot comparison)
 */
function createHorizontalBarChart(container, data, options = {}) {
  const {
    width = 400,
    height = 150,
    barColor = '#2563eb',
    labelColor = '#cbd5e1',
    barHeight = 24
  } = options;
  
  if (!data || data.length === 0) {
    container.innerHTML = '<div class="empty-state">No data available</div>';
    return;
  }
  
  const maxValue = Math.max(...data.map(d => d.value));
  const chartWidth = width - 100;
  const calculatedHeight = data.length * (barHeight + 10) + 20;
  
  const svg = `
    <svg width="${width}" height="${calculatedHeight}" viewBox="0 0 ${width} ${calculatedHeight}">
      ${data.map((d, i) => {
        const barW = (d.value / maxValue) * chartWidth;
        const y = 10 + i * (barHeight + 10);
        
        return `
          <text x="5" y="${y + barHeight / 2 + 4}" 
            fill="${labelColor}" font-size="12" font-weight="500">
            ${d.label}
          </text>
          <rect x="90" y="${y}" width="${barW}" height="${barHeight}" 
            fill="${d.color || barColor}" rx="3">
            <title>${d.label}: ${d.value}</title>
          </rect>
          <text x="${95 + barW}" y="${y + barHeight / 2 + 4}" 
            fill="${labelColor}" font-size="11">
            ${d.value}
          </text>
        `;
      }).join('')}
    </svg>
  `;
  
  container.innerHTML = svg;
}

/**
 * Create a sparkline (mini line chart)
 */
function createSparkline(container, values, options = {}) {
  const {
    width = 100,
    height = 30,
    lineColor = '#10b981',
    lineWidth = 2
  } = options;
  
  if (!values || values.length < 2) {
    container.innerHTML = '';
    return;
  }
  
  const maxVal = Math.max(...values);
  const minVal = Math.min(...values);
  const range = maxVal - minVal || 1;
  
  const stepX = width / (values.length - 1);
  
  const points = values.map((v, i) => ({
    x: i * stepX,
    y: height - 2 - ((v - minVal) / range) * (height - 4)
  }));
  
  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
  
  container.innerHTML = `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <path d="${path}" fill="none" stroke="${lineColor}" stroke-width="${lineWidth}" stroke-linecap="round" />
      <circle cx="${points[points.length - 1].x}" cy="${points[points.length - 1].y}" r="3" fill="${lineColor}" />
    </svg>
  `;
}

/**
 * Create a progress ring
 */
function createProgressRing(container, percentage, options = {}) {
  const {
    size = 80,
    strokeWidth = 8,
    color = '#10b981',
    bgColor = '#334155',
    labelColor = '#f8fafc'
  } = options;
  
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percentage / 100) * circumference;
  
  container.innerHTML = `
    <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
      <!-- Background circle -->
      <circle
        cx="${size / 2}" cy="${size / 2}" r="${radius}"
        fill="none" stroke="${bgColor}" stroke-width="${strokeWidth}"
      />
      <!-- Progress circle -->
      <circle
        cx="${size / 2}" cy="${size / 2}" r="${radius}"
        fill="none" stroke="${color}" stroke-width="${strokeWidth}"
        stroke-dasharray="${circumference}"
        stroke-dashoffset="${offset}"
        stroke-linecap="round"
        transform="rotate(-90 ${size / 2} ${size / 2})"
        style="transition: stroke-dashoffset 0.5s ease;"
      />
      <!-- Percentage text -->
      <text x="${size / 2}" y="${size / 2 + 5}" 
        text-anchor="middle" fill="${labelColor}" font-size="14" font-weight="bold">
        ${Math.round(percentage)}%
      </text>
    </svg>
  `;
}

// Color schemes
const chartColors = {
  primary: '#2563eb',
  success: '#10b981',
  warning: '#f59e0b',
  danger: '#ef4444',
  secondary: '#64748b',
  
  // Bot colors
  session2: '#10b981',   // Green
  openclaw: '#2563eb',   // Blue
  openclaw4: '#f59e0b',  // Orange
  main: '#8b5cf6',       // Purple
  
  // Status colors
  completed: '#10b981',
  failed: '#ef4444',
  running: '#f59e0b',
  pending: '#64748b'
};

// Export for use in dashboard
if (typeof window !== 'undefined') {
  window.chartColors = chartColors;
  window.createBarChart = createBarChart;
  window.createDonutChart = createDonutChart;
  window.createLineChart = createLineChart;
  window.createHorizontalBarChart = createHorizontalBarChart;
  window.createSparkline = createSparkline;
  window.createProgressRing = createProgressRing;
}
