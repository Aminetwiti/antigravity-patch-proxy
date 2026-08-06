// Watch for the Antigravity DevTools port to appear, then attach and dump
// every event for 12 seconds. Designed to be invoked in the background while
// the user manually launches Antigravity, OR launched alongside it.
const WS = require('ws');

(async () => {
  const scan = async () => {
    // Port range matches known Antigravity pattern (random).
    const targets = [];
    for (let port = 45000; port < 65535; port += 1) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: AbortSignal.timeout(150) });
        if (!res.ok) continue;
        const json = await res.json();
        if (Array.isArray(json) && json.some(t => t.type === 'page')) {
          return { port, targets: json };
        }
      } catch {}
    }
    return null;
  };

  const start = Date.now();
  let found = null;
  while (Date.now() - start < 90000 && !found) {
    found = await scan();
    if (!found) await new Promise(r => setTimeout(r, 800));
  }
  if (!found) { console.log('NO_DEVTOOLS'); process.exit(1); }

  const page = found.targets.find(t => t.type === 'page');
  console.log('DEVTOOLS_PORT:', found.port);
  console.log('PAGE:', page.id, page.url, page.title);

  const ws = new WS(page.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const events = [];

  ws.on('open', async () => {
    const send = (method, params) => new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
    });

    await send('Runtime.enable');
    await send('Log.enable');
    await send('Network.enable');
    await send('Page.enable');
    console.log('DOMAINS_ENABLED');

    // First pass: introspect page state
    setTimeout(async () => {
      try {
        const r = await send('Runtime.evaluate', {
          expression: 'JSON.stringify({title: document.title, url: location.href, ready: document.readyState, bodyEl: document.body?.childElementCount, bodyText: document.body?.innerText?.slice(0,200), bg: getComputedStyle(document.body).backgroundColor, html: getComputedStyle(document.documentElement).backgroundColor})',
          returnByValue: true,
        });
        console.log('STATE_1:', r.result?.result?.value);
      } catch (e) { console.log('STATE_1_ERR:', e.message); }
    }, 1500);

    // Wait 10s for events to accumulate
    setTimeout(async () => {
      console.log('\n=== EVENTS ===');
      const failed = events.filter(e => e.method === 'Network.loadingFailed');
      const conns = events.filter(e => e.method === 'Network.requestWillBeSent' || e.method === 'Network.responseReceived');
      const logs = events.filter(e => e.method === 'Log.entryAdded' || e.method === 'Runtime.consoleAPICalled' || e.method === 'Runtime.exceptionThrown');

      console.log(`Failed (${failed.length}):`);
      failed.forEach((e) => {
        const p = e.params || {};
        console.log(' -', p.errorText || p.blockedReason, p.type, p.requestId);
      });
      console.log(`Requests (${conns.length}):`);
      conns.slice(-12).forEach((e) => {
        const p = e.params || {};
        if (e.method === 'Network.responseReceived') {
          console.log(' -', p.response?.status, p.response?.url?.slice(0, 80));
        } else {
          console.log(' ->', p.request?.method, p.request?.url?.slice(0, 80));
        }
      });
      console.log(`Console/Errors (${logs.length}):`);
      logs.slice(-20).forEach((e) => {
        const p = e.params || {};
        const text = JSON.stringify(p).slice(0, 500);
        console.log(' -', e.method, text);
      });

      // Screenshot
      try {
        const s = await send('Page.captureScreenshot', { format: 'png' });
        if (s.result?.data) {
          require('fs').writeFileSync('diag/black-screen.png', Buffer.from(s.result.data, 'base64'));
          console.log('SCREENSHOT: diag/black-screen.png');
        }
      } catch (e) { console.log('SCREEN_ERR:', e.message); }

      ws.close();
      process.exit(0);
    }, 12000);
  });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
      else if (msg.method) events.push(msg);
    } catch {}
  });

  ws.on('error', (e) => { console.log('WS_ERR:', e.message); process.exit(2); });
})();
