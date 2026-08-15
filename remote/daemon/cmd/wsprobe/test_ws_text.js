// test_ws_text.js — WS E2E: send prompt WITHOUT model selection + dump raw text deltas
const WebSocket = require("ws");
const url = process.argv[2] || "ws://localhost:8090/ws";
const token = process.argv[3] || "aa";
const cascadeId = process.argv[4]; // optional, else first from list_sessions

let nextId = 0;
const pending = new Map();
const deltas = [];

function send(ws, msg) {
  const id = msg.requestId || `req-${++nextId}`;
  ws.send(JSON.stringify({ ...msg, requestId: id }));
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { pending.delete(id); reject(new Error(`timeout ${msg.type}`)); }, 20000);
    pending.set(id, { resolve, reject, timer: t });
  });
}

async function main() {
  const ws = await connect(url, token);
  ws.on("message", (d) => {
    const m = JSON.parse(d.toString());
    if (m.requestId && pending.has(m.requestId)) {
      const p = pending.get(m.requestId);
      clearTimeout(p.timer);
      pending.delete(m.requestId);
      m.error ? p.reject(new Error(m.error)) : p.resolve(m);
    } else if (m.type === "stream_delta") {
      deltas.push(m);
      const evs = (m.data && m.data.events) || [];
      console.log(`📡 stream_delta #${m.data.frameIndex}: ${evs.length} events`, JSON.stringify(evs).slice(0, 400));
    } else if (m.type === "stream_end") {
      console.log(`🏁 stream_end:`, JSON.stringify(m.data || m.error || {}).slice(0, 300));
    }
  });

  let cid = cascadeId;
  if (!cid) {
    const r = await send(ws, { type: "list_sessions" });
    cid = (r.data.sessions && r.data.sessions[0] && r.data.sessions[0].cascadeId) || null;
    console.log("using session:", cid);
  }

  if (!cid) { console.log("❌ no session"); process.exit(1); }

  // NO modelEnum/modelUID → LS uses cascade's own model
  const r = await send(ws, { type: "send_prompt", cascadeId: cid, prompt: "Réponds UNIQUEMENT avec le mot OK." });
  console.log("✅ send_prompt unary →", JSON.stringify(r.data || r.error || "").slice(0, 200));

  await new Promise((res) => setTimeout(res, 15000));
  console.log(`\n📊 total deltas: ${deltas.length}`);
  ws.close();
  process.exit(0);
}

function connect(url, token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${url}?auth_token=${encodeURIComponent(token)}`);
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

main().catch((e) => { console.error("FATAL:", e); process.exit(1); });
