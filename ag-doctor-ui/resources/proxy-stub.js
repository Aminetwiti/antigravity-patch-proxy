const http = require('http');

const PORT = 50999;

const server = http.createServer((req, res) => {
  console.log(`[Stub] ${req.method} ${req.url}`);

  if (req.method === 'GET' && (req.url === '/health' || req.url === '/healthz')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', stub: true, port: PORT }));
    return;
  }

  // Intercept all other traffic with a 200 OK empty response,
  // preventing Go language server from crashing with ECONNREFUSED
  res.writeHead(200, {
    'Content-Type': 'application/json',
    'X-Proxy-Stub': '1'
  });
  res.end(JSON.stringify({}));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Stub] Proxy stub listening on http://127.0.0.1:${PORT}`);
});

server.on('error', (err) => {
  console.error('[Stub] Server error:', err);
  process.exit(1);
});
