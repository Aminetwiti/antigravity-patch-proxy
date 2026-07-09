// Standalone proxy runner — loaded by Antigravity.exe (electron) to start
// the local proxy (dist/proxy.js) on 127.0.0.1:50999.
const fs = require('fs');
const path = require('path');

// HARD-CODED log path so we always get a log, even if electron/app fails early.
const LOG_PATH = 'C:\\Users\\Admin\\AppData\\Local\\Temp\\ag-proxy-runner.log';
const PORT_FILE = 'C:\\Users\\Admin\\AppData\\Local\\Temp\\ag-proxy-runner.port';
function w(line) {
  try {
    fs.appendFileSync(LOG_PATH, '[' + new Date().toISOString() + '] ' + line + '\n');
  } catch (e) {
    // last-resort: try writing to CWD
    try { fs.appendFileSync('ag-proxy-runner.log', line + '\n'); } catch (_) {}
  }
}
// Clear previous log
try { fs.writeFileSync(LOG_PATH, ''); } catch (_) {}
w('runner: top of file, node=' + process.version + ' pid=' + process.pid);

let app;
try {
  ({ app } = require('electron'));
  w('runner: electron require OK, app.isReady=' + app.isReady());
} catch (e) {
  w('runner: FATAL electron require failed: ' + e.message);
  process.exit(2);
}

app.setName('Antigravity');
w('runner: setName(Antigravity), getName=' + app.getName());

// Configure electron-log to write to our hardcoded file
let log;
try {
  log = require('electron-log');
  log.transports.file.file = LOG_PATH;
  log.transports.file.level = 'info';
  log.transports.console.level = 'info';
  log.initialize({ preload: true });
  w('runner: electron-log initialised, file=' + log.transports.file.file);
} catch (e) {
  w('runner: electron-log init failed (continuing with fs log): ' + e.message);
}

process.on('uncaughtException', (e) => w('runner: uncaughtException: ' + (e && e.stack || e)));
process.on('unhandledRejection', (e) => w('runner: unhandledRejection: ' + (e && e.stack || e)));

let home = '?', userData = '?';
try { home = app.getPath('home'); } catch (e) { w('runner: getPath(home) failed: ' + e.message); }
try { userData = app.getPath('userData'); } catch (e) { w('runner: getPath(userData) failed: ' + e.message); }
w('runner: home=' + home + ' userData=' + userData + ' isPackaged=' + app.isPackaged);

app.whenReady().then(async () => {
  w('runner: app ready');
  try {
    const proxyMod = require('./dist/proxy');
    w('runner: proxy module loaded; calling startProxy()');
    const port = await proxyMod.startProxy();
    w('runner: Proxy listening on http://127.0.0.1:' + port);
    try { fs.writeFileSync(PORT_FILE, String(port)); } catch (_) {}
  } catch (e) {
    w('runner: startProxy FAILED: ' + (e && e.stack || e));
    setTimeout(() => app.exit(3), 500);
  }
}).catch((e) => w('runner: whenReady error: ' + (e && e.stack || e)));

app.on('window-all-closed', () => { /* keep alive */ });
w('runner: listeners registered, awaiting app ready...');
