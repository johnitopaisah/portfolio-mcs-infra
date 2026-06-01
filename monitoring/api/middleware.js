'use strict';
// ============================================================
//  Portfolio MCS — Prometheus HTTP Middleware
//  Instruments every Express request automatically.
//  Mount BEFORE all route handlers in index.js.
// ============================================================

const {
  httpRequestsTotal,
  httpRequestDurationSeconds,
  httpRequestsInFlight,
} = require('./metrics');

// Normalise dynamic route segments so cardinality stays low.
// e.g. /api/projects/550e8400-e29b-41d4-a716-446655440000 → /api/projects/:id
// Without this, every UUID would create a unique time series → OOM in Prometheus.
function normaliseRoute(path) {
  return path
    // UUIDs
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, ':id')
    // Pure numeric IDs
    .replace(/\/\d+/g, '/:id')
    // Trailing slash
    .replace(/\/$/, '') || '/';
}

function prometheusMiddleware(req, res, next) {
  // Skip the /metrics endpoint itself — no point in tracking it
  if (req.path === '/metrics') return next();

  const start = process.hrtime.bigint();
  httpRequestsInFlight.inc();

  res.on('finish', () => {
    const durationSeconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route           = normaliseRoute(req.path);
    const labels          = {
      method:      req.method,
      route,
      status_code: String(res.statusCode),
    };

    httpRequestsTotal.inc(labels);
    httpRequestDurationSeconds.observe(labels, durationSeconds);
    httpRequestsInFlight.dec();
  });

  next();
}

module.exports = prometheusMiddleware;
