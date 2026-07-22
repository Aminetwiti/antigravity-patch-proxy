// Send Chrome DevTools Protocol commands to Antigravity's renderer
// Uses built-in Node WebSocket (Node 22+) — no dependencies.
const WS_URL = process.argv[2] || 'ws://127.0.0.1:64585/devtools/page/B4748A85145D923267F968F1554BA91A';

(async () => {
  // WebSocket is global in Node 22+; if not, dynamically import.
  let WS;
  try { WS = (await import('ws')).default || (await import('ws')); }
  catch { WS = globalThis.WebSocket; }

  const ws = new WS(WS_URL);
  let id = 0;
  const pending = new Map();
  const events = [];

  ws.addEventListener('open', async () => {
    const send = (method, params) => new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
    });

    // Enable domains
    await send('Runtime.enable');
    await send('Log.enable');
    await send('Network.enable');
    await send('Page.enable');

    // Collect events for a short window
    const stopAt = Date.now() + 4000;
    const isOpen = true;

    // Trigger failed-resource events
    setTimeout(async () => {
      try {
        const r = await send('Runtime.evaluate', {
          expression: 'JSON.stringify({ title: document.title, url: location.href, readyState: document.readyState, bodyText: document.body && document.body.innerText.slice(0, 200), childCount: document.body && document.body.childElementCount, bgColor: getComputedStyle(document.body).backgroundColor, hasReact: !!window.React, hasJSBundle: !!document.querySelector("script[src]") })',
          returnByValue: true,
        });
        console.log('PAGE STATE:', r.result?.result?.value);
      } catch (e) { console.log('EVAL ERR:', e.message); }
    }, 1000);

    // Get console messages collected so far
    setTimeout(async () => {
      try {
        const r = await send('Runtime.evaluate', {
          expression: '(async () => { try { const f = await fetch("/jetbox.css", {cache:"no-store"}); return `jetbox.css: ${f.status} ${f.headers.get("content-type") || ""}`; } catch(e) { return `jetbox.css ERR: ${e.message}`; } })()',
          awaitPromise: true,
          returnByValue: true,
        });
        console.log('JETBOX CSS:', r.result?.result?.value);
      } catch (e) { console.log('JETBOX ERR:', e.message); }
    }, 1500);

    setTimeout(async () => {
      try {
        const r = await send('Runtime.evaluate', {
          expression: '(async () => { const tags = [...document.querySelectorAll("script[src],link[href]")].map(t => (t.src || t.href || "").slice(0,180)); return JSON.stringify(tags); })()',
          awaitPromise: true,
          returnByValue: true,
        });
        console.log('ASSETS:', r.result?.result?.value);
      } catch (e) { console.log('ASSETS ERR:', e.message); }
    }, 1800);

    setTimeout(async () => {
      try {
        const r = await send('Runtime.evaluate', {
          expression: '(async () => { try { const r = await fetch("/"); const txt = await r.text(); const scripts = (txt.match(/<script[^>]*src="([^"]+)"/g) || []).concat((txt.match(/<link[^>]*href="([^"]+)"/g) || [])); return scripts.join("\\n"); } catch(e) { return "ERR: " + e.message; } })()',
          awaitPromise: true,
          returnByValue: true,
        });
        console.log('SCRIPTS IN HTML:', r.result?.result?.value);
      } catch (e) { console.log('SCRIPT ERR:', e.message); }
    }, 2200);

    setTimeout(async () => {
      try {
        const shot = await send('Page.captureScreenshot', { format: 'png' });
        if (shot.result?.data) {
          require('fs').writeFileSync('diag/black-screen.png', Buffer.from(shot.result.data, 'base64'));
          console.log('SCREENSHOT saved: diag/black-screen.png');
        }
      } catch (e) { console.log('SCREENSHOT ERR:', e.message); }
    }, 2500);

    setTimeout(async () => {
      try {
        const r = await send('Runtime.getProperties', { objectId: undefined, ownProperties: false, accessorPropertiesOnly: false });
      } catch {}
      console.log('\n=== EVENTS COLLECTED ===');
      const failed = events.filter(e => e.method === 'Network.loadingFailed');
      const consol = events.filter(e => e.method === 'Runtime.consoleAPICalled' || e.method === 'Log.entryAdded' || e.method === 'Runtime.exceptionThrown');
      console.log(`Failed requests (${failed.length}):`);
      failed.slice(-10).forEach((e) => {
        const p = e.params || {};
        console.log('  -', p.errorText || p.blockedReason || '?', p.requestId, p.type);
      });
      console.log(`Console/Exceptions (${consol.length}):`);
      consol.slice(-15).forEach((e) => console.log('  ', JSON.stringify(e.params).slice(0, 400)));
      ws.close();
      process.exit(0);
    }, 4500);
  });

  ws.addEventListener('message', (ev) => {
    try {
      const msg = JSON.parse(ev.data);
      if (msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      } else if (msg.method) {
        events.push(msg);
      }
    } catch {}
  });

  ws.addEventListener('error', (e) => { console.log('WS ERR:', e.message); process.exit(2); });

  setTimeout(() => { console.log('timeout'); process.exit(3); }, 9000);
})();
