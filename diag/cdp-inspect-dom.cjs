const WS = require('ws');
const fs = require('fs');

const WS_URL = process.argv[2];
const ws = new WS(WS_URL);
let id = 0;
const pending = new Map();
const allEvents = [];

ws.on('message', d => {
  try {
    const m = JSON.parse(d.toString());
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
    } else if (m.method) {
      allEvents.push(m);
    }
  } catch {}
});

ws.on('open', async () => {
  const send = (method, params) => new Promise((resolve, reject) => {
    const mid = ++id;
    pending.set(mid, { resolve, reject });
    ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
    setTimeout(() => { if (pending.has(mid)) { pending.delete(mid); reject(new Error('timeout: ' + method)); } }, 15000);
  });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Network.enable');
  console.log('DOMAINS_ENABLED');

  // 1) Check scripts
  const r = await send('Runtime.evaluate', {
    expression: `JSON.stringify({
      headHTML: document.head.outerHTML.slice(0, 2500),
      bodyHTML: document.body.outerHTML.slice(0, 2500),
      scripts: [...document.querySelectorAll('script')].map(s => ({src: (s.src||'').slice(0,150), type: s.type, inline: s.textContent.length})),
      links: [...document.querySelectorAll('link')].map(l => ({rel: l.rel, href: (l.href||'').slice(0,150)}))
    })`,
    returnByValue: true,
  });
  fs.writeFileSync('diag/dom-state.json', r.result?.result?.value || 'null');
  console.log('DOM STATE WRITTEN to diag/dom-state.json');

  // 2) Wait 6s and dump events
  setTimeout(() => {
    const failed = allEvents.filter(e => e.method === 'Network.loadingFailed');
    const responses = allEvents.filter(e => e.method === 'Network.responseReceived');
    const consoles = allEvents.filter(e => e.method === 'Runtime.consoleAPICalled' || e.method === 'Runtime.exceptionThrown' || e.method === 'Log.entryAdded');

    console.log('\n=== EVENTS COLLECTED ===');
    console.log('Failed (' + failed.length + '):');
    failed.forEach(e => { const p = e.params || {}; console.log(' -', p.errorText || p.blockedReason, p.type, p.requestId); });

    console.log('\nResponses (' + responses.length + '):');
    responses.slice(-25).forEach(e => {
      const p = e.params || {};
      console.log(' -', p.response?.status, p.response?.url?.slice(0, 100));
    });

    console.log('\nConsole/Errors (' + consoles.length + '):');
    consoles.forEach(e => {
      const p = e.params || {};
      if (e.method === 'Runtime.exceptionThrown') {
        console.log(' [exception]', p.exceptionDetails?.text, p.exceptionDetails?.exception?.description?.slice(0, 500) || '');
      } else if (e.method === 'Log.entryAdded') {
        const ent = p.entry || {};
        console.log(' [log:' + ent.level + ']', ent.text, ent.url?.slice(0, 100) || '');
      } else {
        const args = (p.args || []).map(a => a.value || a.description || JSON.stringify(a)).join(' ');
        console.log(' [' + p.type + ']', args.slice(0, 500));
      }
    });

    fs.writeFileSync('diag/all-events.json', JSON.stringify(allEvents, null, 2));
    console.log('\nFull events saved to diag/all-events.json');

    ws.close();
    process.exit(0);
  }, 6000);
});

ws.on('error', e => { console.error('WS_ERR:', e.message); process.exit(1); });
setTimeout(() => { console.error('script_timeout'); process.exit(2); }, 20000);
