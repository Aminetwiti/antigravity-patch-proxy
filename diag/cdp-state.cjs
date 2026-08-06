// Quick state inspector for Antigravity renderer.
const WS = require('ws');
const fs = require('fs');

const WS_URL = process.argv[2];
if (!WS_URL) { console.error('usage: cdp-state.cjs <ws-url>'); process.exit(1); }

const ws = new WS(WS_URL, { handshakeTimeout: 5000 });
let id = 0;
const pending = new Map();
const consoles = [];

ws.on('open', async () => {
  const send = (method, params) => new Promise((resolve, reject) => {
    const mid = ++id;
    pending.set(mid, { resolve, reject });
    const t = setTimeout(() => { pending.delete(mid); reject(new Error('timeout: ' + method)); }, 20000);
    ws.send(JSON.stringify({ id: mid, method, params: params || {} }), (err) => {
      if (err) { clearTimeout(t); pending.delete(mid); reject(err); }
    });
  });

  await send('Runtime.enable');
  await send('Page.enable');

  // 1) State of the page
  const stateRes = await send('Runtime.evaluate', {
    expression: 'JSON.stringify({url: location.href, title: document.title, ready: document.readyState, viewport: {w: innerWidth, h: innerHeight}, bodyEl: document.body?.childElementCount, bodyBg: getComputedStyle(document.body).backgroundColor, htmlBg: getComputedStyle(document.documentElement).backgroundColor, bodyInnerTextPreview: document.body?.innerText?.slice(0, 300)})',
    returnByValue: true,
  });
  console.log('STATE:', stateRes.result?.result?.value);

  // 2) What is in the DOM right now
  const domRes = await send('Runtime.evaluate', {
    expression: 'JSON.stringify({rootHTMLLen: document.documentElement.outerHTML.length, scripts: [...document.querySelectorAll("script[src]")].map(s => s.src.slice(0, 120)), links: [...document.querySelectorAll("link[rel=stylesheet]")].map(l => l.href.slice(0, 120))})',
    returnByValue: true,
  });
  console.log('DOM:', domRes.result?.result?.value);

  // 3) Check if any visible React/DOM content exists
  const visRes = await send('Runtime.evaluate', {
    expression: 'JSON.stringify((function() { const all = [...document.querySelectorAll("*")]; const visible = all.filter(el => { const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return cs.display !== "none" && cs.visibility !== "hidden" && parseFloat(cs.opacity) > 0 && r.width > 0 && r.height > 0; }); const tags = {}; visible.forEach(v => { tags[v.tagName] = (tags[v.tagName] || 0) + 1; }); return { totalVisible: visible.length, byTag: tags, firstVisible: visible.slice(0, 10).map(v => v.tagName + (v.id ? "#"+v.id : "")) }; })())',
    returnByValue: true,
  });
  console.log('VISIBLE:', visRes.result?.result?.value);

  // 4) Take screenshot
  try {
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    if (shot.result?.data) {
      const buf = Buffer.from(shot.result.data, 'base64');
      fs.writeFileSync('diag/black-screen-now.png', buf);
      console.log('SCREENSHOT: diag/black-screen-now.png (' + buf.length + ' bytes)');
    }
  } catch (e) {
    console.log('SCREENSHOT_ERR:', e.message);
  }

  ws.close();
  process.exit(0);
});

ws.on('message', (data) => {
  try {
    const msg = JSON.parse(data.toString());
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(msg.error.message));
      else resolve(msg.result);
    }
  } catch {}
});

ws.on('error', (e) => { console.error('WS_ERR:', e.message); process.exit(2); });
setTimeout(() => { console.error('script_timeout'); process.exit(3); }, 30000);
