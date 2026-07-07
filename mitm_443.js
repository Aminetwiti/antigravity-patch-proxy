/**
 * MITM HTTPS forwarder on port 443.
 * Terminates TLS for *.googleapis.com (using a user-trusted CA),
 * then forwards requests to the Antigravity local proxy on localhost:50999.
 *
 * Requires:
 *   - CA cert trusted in Windows (LocalMachine\Root)
 *   - Run with admin rights so Node can bind port 443
 *
 * Usage (PowerShell admin):
 *   node C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\mitm_443.js
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CERT_DIR = __dirname;
const PROXY_TARGET = process.env.AG_PROXY_TARGET || 'http://127.0.0.1:50999';
const LISTEN_HOST = process.env.AG_MITM_HOST || '127.0.0.1';
const LISTEN_PORT = parseInt(process.env.AG_MITM_PORT || '443', 10);

const serverKey = fs.readFileSync(path.join(CERT_DIR, 'certs', 'server-key.pem'));
const serverCert = fs.readFileSync(path.join(CERT_DIR, 'certs', 'server-cert.pem'));

const target = new URL(PROXY_TARGET);

function forwardToProxy(clientReq, clientRes) {
  const fwdOptions = {
    hostname: target.hostname,
    port: target.port,
    path: clientReq.url,
    method: clientReq.method,
    headers: { ...clientReq.headers },
  };

  // Preserve the original Google host so the proxy knows which upstream to use.
  fwdOptions.headers['host'] = clientReq.headers.host || target.host;
  fwdOptions.headers['x-forwarded-proto'] = 'https';

  const proxyReq = http.request(fwdOptions, (proxyRes) => {
    clientRes.writeHead(proxyRes.statusCode || 200, proxyRes.headers);
    proxyRes.pipe(clientRes);
  });

  proxyReq.on('error', (err) => {
    console.error('[MITM-443] Forward error:', err.message);
    if (!clientRes.headersSent) {
      clientRes.writeHead(502, { 'Content-Type': 'application/json' });
      clientRes.end(JSON.stringify({ error: 'MITM forward failed: ' + err.message }));
    }
  });

  clientReq.pipe(proxyReq);
}

const server = https.createServer({ key: serverKey, cert: serverCert }, forwardToProxy);

server.on('error', (err) => {
  console.error('[MITM-443] Server error:', err.message);
  if (err.code === 'EACCES') {
    console.error('[MITM-443] Permission denied. Run as Administrator to bind port 443.');
  }
  process.exit(1);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`[MITM-443] Listening on https://${LISTEN_HOST}:${LISTEN_PORT}`);
  console.log(`[MITM-443] Forwarding to ${PROXY_TARGET}`);
});
