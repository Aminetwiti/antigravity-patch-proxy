const ws = new WebSocket('ws://127.0.0.1:8090/ws?token=11');
let pending = 0;
const t0 = Date.now();
function send(obj) { ws.send(JSON.stringify(obj)); pending++; }
ws.onopen = () => {
  send({ type: 'heartbeat', requestId: 'diag-hb' });
};
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.requestId === 'diag-hb') {
    console.log('HEARTBEAT in', (Date.now() - t0) + 'ms =>', JSON.stringify(msg).slice(0, 200));
    send({ type: 'list_sessions', requestId: 'diag-ls' });
  } else if (msg.requestId === 'diag-ls') {
    const list = msg.data?.sessions || [];
    console.log('LIST_SESSIONS in', (Date.now() - t0) + 'ms =>', list.length, 'sessions');
    send({ type: 'get_context', requestId: 'diag-gc' });
  } else if (msg.requestId === 'diag-gc') {
    console.log('GET_CONTEXT in', (Date.now() - t0) + 'ms =>', JSON.stringify(msg).slice(0, 200));
    ws.close(); process.exit(0);
  }
};
ws.onerror = (e) => { console.error('WS Error:', e.message); process.exit(1); };
setTimeout(() => { console.error('GLOBAL TIMEOUT after', Date.now() - t0, 'ms'); process.exit(1); }, 45000);
