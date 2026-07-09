// Minimal HTTP stub on 127.0.0.1:50999.
//
// Purpose: makes the local-proxy port reachable so ag-doctor's "Local proxy"
// check passes and the patched language_server.exe stops flooding
// "connect ECONNREFUSED 127.0.0.1:50999" errors.
//
// This is NOT the real proxy (dist/proxy.js) — it does NOT inject custom
// models. It returns empty/minimal responses so the LS can initialise.
// For full custom-model support, run repack.ps1 to fix the bundled proxy.
const http = require('http');
const fs = require('fs');

const LOG = 'C:\\Users\\Admin\\AppData\\Local\\Temp\\proxy-stub.log';
const PORT = 50999;

function log(line) {
  const ts = new Date().toISOString();
  try { fs.appendFileSync(LOG, '[' + ts + '] ' + line + '\n'); } catch (_) {}
  try { process.stdout.write('[' + ts + '] ' + line + '\n'); } catch (_) {}
}

try { fs.writeFileSync(LOG, ''); } catch (_) {}
log('proxy-stub starting on 127.0.0.1:' + PORT);

const server = http.createServer((req, res) => {
  log(req.method + ' ' + req.url + ' from ' + (req.socket.remoteAddress || '?'));

  // Health probe (ag-doctor checkProxy + manual)
  if (req.url === '/health' || req.url.startsWith('/health?')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', stub: true, port: PORT }));
    return;
  }

  // Collect body but don't block — return a minimal response immediately.
  // The patched LS hits /v1internal/xxxxxxx/v1internal:* with POST/GET.
  let bodyLen = 0;
  req.on('data', (c) => { bodyLen += c.length; });
  req.on('end', () => {
    log('  -> body bytes=' + bodyLen + ', returning empty 200');
    // Empty 200 with JSON content-type. The Go LS treats most of these as
    // "no data" and moves on (it logs a warning but does not crash).
    res.writeHead(200, { 'Content-Type': 'application/json', 'X-Proxy-Stub': '1' });
    res.end('{}');
  });
  req.on('error', (e) => log('req error: ' + e.message));
});

server.on('error', (err) => {
  log('server error: ' + err.code + ' ' + err.message);
  if (err.code === 'EADDRINUSE') {
    log('Port ' + PORT + ' already in use — another process is bound. Exiting.');
  }
  process.exit(1);
});

server.listen(PORT, '127.0.0.1', () => {
  log('listening on http://127.0.0.1:' + PORT + ' (pid=' + process.pid + ')');
});

process.on('uncaughtException', (e) => log('uncaught: ' + (e.stack || e)));
process.on('SIGINT', () => { log('SIGINT, closing'); server.close(); process.exit(0); });
process.on('SIGTERM', () => { log('SIGTERM, closing'); server.close(); process.exit(0); });
