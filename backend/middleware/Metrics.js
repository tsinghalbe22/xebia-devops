const client = require('prom-client');
const express = require('express');
const router = express.Router();

const register = new client.Registry();
client.collectDefaultMetrics({ register });

// HTTP request counter
const httpRequestCounter = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests received',
  labelNames: ['method', 'route', 'status'],
});
register.registerMetric(httpRequestCounter);

// Track every request
function trackRequests(req, res, next) {
  res.on('finish', () => {
    httpRequestCounter.inc({
      method: req.method,
      route: req.route ? req.baseUrl + req.route.path : req.originalUrl,
      status: res.statusCode,
    });
  });
  next();
}

// /metrics route
router.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

module.exports = { metricsRouter: router, trackRequests };
