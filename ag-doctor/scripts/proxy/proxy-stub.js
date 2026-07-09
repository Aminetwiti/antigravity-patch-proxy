const http = require('http');

const port = process.env.PORT || 50999;

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/healthz')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', stub: true, port: port }));
    return;
  }
  
  // Fake successful response for all other endpoints to prevent the language server from complaining
  res.writeHead(200, {
    'Content-Type': 'application/json',
    'X-Proxy-Stub': '1'
  });
  res.end(JSON.stringify({}));
});

server.listen(port, '127.0.0.1', () => {
  console.log(`[Proxy Stub] Listening on http://127.0.0.1:${port}`);
});
