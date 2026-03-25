# AgentFlow Dockerfile
# Multi-stage build for optimized production image

# Stage 1: Builder
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm ci

# Copy source code
COPY . .

# Run tests (optional)
# RUN npm test

# Stage 2: Production
FROM node:18-alpine

WORKDIR /app

# Install only production dependencies
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy built application from builder
COPY --from=builder /app .

# Create data directory
RUN mkdir -p /app/data /app/logs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/agentflow/api/bots', (r) => { process.exit(r.statusCode === 200 ? 0 : 1) })"

# Non-root user for security
RUN addgroup -g 1001 -S agentflow && \
    adduser -S agentflow -u 1001

# Change ownership
RUN chown -R agentflow:agentflow /app

USER agentflow

# Start server
CMD ["node", "standalone-server.js"]
