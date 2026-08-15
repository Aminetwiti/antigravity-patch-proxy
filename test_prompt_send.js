const ws = new WebSocket('ws://127.0.0.1:8090/ws?token=11');
const targetCascade = 'a700c4a7-97fb-4ab7-be4a-0d55f0f9fff8';
const t0 = Date.now();

ws.onopen = () => {
  console.log('WS OPEN, sending test prompt...');
  ws.send(JSON.stringify({
    type: 'send_prompt',
    requestId: 'test-prompt-1',
    cascadeId: targetCascade,
    prompt: 'test direct node prompt 123'
  }));
};

ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  console.log('[' + (Date.now() - t0) + 'ms] TYPE:', msg.type, 'reqId:', msg.requestId, 'err:', msg.error, 'data:', JSON.stringify(msg.data || {}).slice(0, 120));
  if (msg.type === 'stream_end') {
    console.log('STREAM END reached!');
    ws.close();
    process.exit(0);
  }
};

ws.onerror = (e) => {
  console.error('WS ERROR:', e);
  process.exit(1);
};

setTimeout(() => {
  console.log('TIMEOUT 20s');
  ws.close();
  process.exit(1);
}, 20000);
