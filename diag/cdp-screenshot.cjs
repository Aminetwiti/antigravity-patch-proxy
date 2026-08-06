// One-shot snapshot of the current Antigravity renderer.
const WS = require('ws');
const fs = require('fs');

const WS_URL = process.argv[2];
if (!WS_URL) { console.error('usage: cdp-screenshot.cjs <ws-url>'); process.exit(1); }

const ws = new WS(WS_URL);
let id = 0;
const pending = new Map();
const events = [];
const consoleMessages = [];

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
  await send('DOM.enable');

  // After enabling, wait 5s for events, then dump.
  setTimeout(async () => {
    try {
      // Screenshot
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      if (shot.result?.data) {
        const buf = Buffer.from(shot.result.data, 'base64');
        fs.writeFileSync('diag/black-screen-now.png', buf);
        console.log('SCREENSHOT: diag/black-screen-now.png (' + buf.length + ' bytes)');
      }

      // Page state introspection
      const stateRes = await send('Runtime.evaluate', {
        expression: 'JSON.stringify({url: location.href, ready: document.readyState, title: document.title, bodyChildren: document.body?.childElementCount, bodyHTMLPreview: document.body?.outerHTML?.slice(0, 1500), rootHTMLPreview: document.documentElement?.outerHTML?.slice(0, 800), bodyBg: getComputedStyle(document.body).backgroundColor, htmlBg: getComputedStyle(document.documentElement).backgroundColor, viewport: {w: innerWidth, h: innerHeight}, devicePixelRatio})',
        returnByValue: true,
      });
      console.log('STATE:', stateRes.result?.result?.value);

      // Check for visible content
      const visRes = await send('Runtime.evaluate', {
        expression: 'JSON.stringify((function() { const all = [...document.querySelectorAll("*")]; const visible = all.filter(el => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return cs.display !== "none" && cs.visibility !== "hidden" && parseFloat(cs.opacity) > 0 && r.width > 0 && r.height > 0; }); return { totalElements: all.length, visibleElements: visible.length, sampleTags: visible.slice(0, 30).map(el => el.tagName + (el.id ? "#"+el.id : "") + (el.className ? "."+String(el.className).split(" ").slice(0,3).join(".") : "")) }; })())',
        returnByValue: true,
      });
      console.log('VISIBLE_ELEMENTS:', visRes.result?.result?.value);

      // Recent console messages
      console.log('CONSOLE_MSGS (' + consoleMessages.length + '):');
      consoleMessages.slice(-20).forEach(m => console.log(' -', m));

      ws.close();
      process.exit(0);
    } catch (e) {
      console.error('ERR:', e.message);
      process.exit(2);
    }
  }, 5000);
});

ws.on('message', (data) => {
  try {
    const msg = JSON.parse(data.toString());
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    else if (msg.method === 'Runtime.consoleAPICalled') {
      const p = msg.params;
      consoleMessages.push(`[${p.type}] ` + (p.args || []).map(a => a.value || a.description || JSON.stringify(a)).join(' '));
    } else if (msg.method === 'Runtime.exceptionThrown') {
      consoleMessages.push(`[exception] ${msg.params.exceptionDetails?.text} ${msg.params.exceptionDetails?.exception?.description || ''}`);
    } else if (msg.method === 'Log.entryAdded') {
      const e = msg.params.entry;
      consoleMessages.push(`[log:${e.level}] ${e.text}`);
    } else if (msg.method) {
      events.push(msg);
    }
  } catch {}
});

ws.on('error', (e) => { console.error('WS_ERR:', e.message); process.exit(3); });
setTimeout(() => { console.error('timeout'); process.exit(4); }, 12000);
