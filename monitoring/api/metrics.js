'use strict';
// ============================================================
//  Portfolio MCS — Prometheus Metrics
//  All application metrics are defined and exported here.
//  Imported once in index.js; all route files share this module.
// ============================================================

const client = require('prom-client');

// ── Registry ─────────────────────────────────────────────────
// Use the default global registry so prom-client's built-in
// Node.js metrics (GC, event loop lag, memory, etc.) are
// automatically included alongside our custom metrics.
const register = client.register;

// Collect default Node.js metrics at 10s intervals.
// Gives us: process_cpu_*, process_heap_*, nodejs_gc_*, etc.
client.collectDefaultMetrics({
  register,
  prefix: 'portfolio_',     // prefix to distinguish from exporters
  gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5],
  eventLoopMonitoringPrecision: 10,
});

// ── HTTP Request metrics ─────────────────────────────────────

const httpRequestsTotal = new client.Counter({
  name: 'portfolio_http_requests_total',
  help: 'Total number of HTTP requests by method, route, and status code',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDurationSeconds = new client.Histogram({
  name: 'portfolio_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

const httpRequestsInFlight = new client.Gauge({
  name: 'portfolio_http_requests_in_flight',
  help: 'Current number of HTTP requests being processed',
  registers: [register],
});

// ── Database metrics ─────────────────────────────────────────

const dbQueryDurationSeconds = new client.Histogram({
  name: 'portfolio_db_query_duration_seconds',
  help: 'PostgreSQL query duration in seconds by operation',
  labelNames: ['operation'],
  buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

const dbPoolConnectionsActive = new client.Gauge({
  name: 'portfolio_db_pool_connections_active',
  help: 'Number of active connections in the PostgreSQL connection pool',
  registers: [register],
});

const dbPoolConnectionsIdle = new client.Gauge({
  name: 'portfolio_db_pool_connections_idle',
  help: 'Number of idle connections in the PostgreSQL connection pool',
  registers: [register],
});

const dbErrorsTotal = new client.Counter({
  name: 'portfolio_db_errors_total',
  help: 'Total number of database errors by type',
  labelNames: ['type'],
  registers: [register],
});

// ── Business metrics ─────────────────────────────────────────

const contactSubmissionsTotal = new client.Counter({
  name: 'portfolio_contact_submissions_total',
  help: 'Total number of contact form submissions by status',
  labelNames: ['status'],   // 'success' | 'error' | 'rate_limited'
  registers: [register],
});

const authAttemptsTotal = new client.Counter({
  name: 'portfolio_auth_attempts_total',
  help: 'Total number of authentication attempts by result',
  labelNames: ['result'],   // 'success' | 'failure'
  registers: [register],
});

const passwordResetRequestsTotal = new client.Counter({
  name: 'portfolio_password_reset_requests_total',
  help: 'Total number of password reset requests',
  registers: [register],
});

const profileRequestsTotal = new client.Counter({
  name: 'portfolio_profile_requests_total',
  help: 'Total number of public profile GET requests',
  registers: [register],
});

const projectsRequestsTotal = new client.Counter({
  name: 'portfolio_projects_requests_total',
  help: 'Total number of public projects list requests',
  registers: [register],
});

const contentCreatedTotal = new client.Counter({
  name: 'portfolio_content_created_total',
  help: 'Total number of content items created by type',
  labelNames: ['type'],   // 'project' | 'skill' | 'experience' | 'certification'
  registers: [register],
});

const contentUpdatedTotal = new client.Counter({
  name: 'portfolio_content_updated_total',
  help: 'Total number of content items updated by type',
  labelNames: ['type'],
  registers: [register],
});

const contentDeletedTotal = new client.Counter({
  name: 'portfolio_content_deleted_total',
  help: 'Total number of content items deleted by type',
  labelNames: ['type'],
  registers: [register],
});

// ── Export everything ─────────────────────────────────────────
module.exports = {
  register,
  // HTTP
  httpRequestsTotal,
  httpRequestDurationSeconds,
  httpRequestsInFlight,
  // DB
  dbQueryDurationSeconds,
  dbPoolConnectionsActive,
  dbPoolConnectionsIdle,
  dbErrorsTotal,
  // Business
  contactSubmissionsTotal,
  authAttemptsTotal,
  passwordResetRequestsTotal,
  profileRequestsTotal,
  projectsRequestsTotal,
  contentCreatedTotal,
  contentUpdatedTotal,
  contentDeletedTotal,
};
