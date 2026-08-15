// test_ws_features.js — E2E test ALL daemon WS features: auth → list_sessions → get_trajectory → send_prompt → sync_session → list_models → get_session_history
// Usage: node test_ws_features.js <ws-url> <auth-token>
const WebSocket = require("ws");
const url = process.argv[2] || "ws://localhost:8090/ws";
const token = process.argv[3] || "aa";

let nextId = 0;
const pending = new Map();
const events = [];

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${url}?auth_token=${encodeURIComponent(token)}`);
    ws.on("open", () => resolve(ws));
    ws.on("error", (e) => reject(e));
  });
}

function send(ws, msg) {
  const id = msg.requestId || `req-${++nextId}`;
  const payload = { ...msg, requestId: id };
  ws.send(JSON.stringify(payload));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`timeout for ${msg.type}`));
    }, 15000);
    pending.set(id, { resolve, reject, timer });
  });
}

async function main() {
  const ws = await connect();
  console.log("✅ connected");
  ws.on("message", (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.requestId && pending.has(msg.requestId)) {
      const { resolve, reject, timer } = pending.get(msg.requestId);
      clearTimeout(timer);
      pending.delete(msg.requestId);
      msg.error ? reject(new Error(msg.error)) : resolve(msg);
    } else {
      events.push(msg);
      if (msg.type === "stream_delta" || msg.type === "stream_end") {
        console.log(`📡 ${msg.type}:`, JSON.stringify(msg.data || {}).slice(0, 300));
      }
    }
  });

  // 1. ping
  const pong = await send(ws, { type: "ping" });
  console.log("✅ ping → pong", JSON.stringify(pong.data));

  // 2. heartbeat
  try {
    const hb = await send(ws, { type: "heartbeat" });
    console.log("✅ heartbeat", JSON.stringify(hb.data || hb.error || "").slice(0, 200));
  } catch (e) {
    console.log("⚠️ heartbeat failed:", e.message);
  }

  // 3. list_sessions
  let cascadeId = null;
  let sessions = [];
  try {
    const resp = await send(ws, { type: "list_sessions" });
    sessions = (resp.data && resp.data.sessions) || [];
    console.log(`✅ list_sessions → ${sessions.length} sessions`);
    sessions.slice(0, 5).forEach((s) => console.log("   -", s.cascadeId, "|", s.title, "|", s.status));
    if (sessions.length > 0) cascadeId = sessions[0].cascadeId;
  } catch (e) {
    console.log("⚠️ list_sessions failed:", e.message);
  }

  // 4. list_models
  try {
    const resp = await send(ws, { type: "list_models" });
    const models = (resp.data && resp.data.models) || [];
    console.log(`✅ list_models → ${models.length} models`);
    models.slice(0, 10).forEach((m) => console.log("   -", JSON.stringify(m).slice(0, 150)));
  } catch (e) {
    console.log("⚠️ list_models failed:", e.message);
  }

  // 5. get_trajectory (active session)
  if (cascadeId) {
    try {
      const resp = await send(ws, { type: "get_trajectory", cascadeId, data: { verbosity: 3 } });
      const d = resp.data || {};
      console.log("✅ get_trajectory →", JSON.stringify(d).slice(0, 500));
    } catch (e) {
      console.log("⚠️ get_trajectory failed:", e.message);
    }

    // 6. get_session_history (transcript-based)
    try {
      const resp = await send(ws, { type: "get_session_history", cascadeId });
      console.log("✅ get_session_history →", JSON.stringify(resp.data || {}).slice(0, 300));
    } catch (e) {
      console.log("⚠️ get_session_history failed:", e.message);
    }
  } else {
    console.log("⚠️ no active session — creating one…");
    try {
      const resp = await send(ws, {
        type: "create_cascade",
        workspaceUri: "file:///c:/Users/amine/Downloads/antigravity-add-model-main",
      });
      console.log("✅ create_cascade →", JSON.stringify(resp.data || resp.error || "").slice(0, 300));
      const sessions2 = (await send(ws, { type: "list_sessions" })).data.sessions;
      if (sessions2.length > 0) cascadeId = sessions2[0].cascadeId;
    } catch (e) {
      console.log("⚠️ create_cascade failed:", e.message);
    }
  }

  // 7. send_prompt on the active session
  if (cascadeId) {
    console.log(`\n🚀 send_prompt on ${cascadeId} …`);
    try {
      const resp = await send(ws, { type: "send_prompt", cascadeId, prompt: "Dis bonjour en un seul mot", modelEnum: 312 });
      console.log("✅ send_prompt unary →", JSON.stringify(resp.data || resp.error || "").slice(0, 300));
    } catch (e) {
      console.log("⚠️ send_prompt failed:", e.message);
    }
    // wait for stream deltas/end
    await new Promise((r) => setTimeout(r, 8000));
    const ends = events.filter((e) => e.type === "stream_end");
    console.log(`📡 stream events: ${events.length} (${events.filter((e) => e.type === "stream_delta").length} deltas, ${ends.length} ends)`);
    if (ends.length > 0) console.log("   stream_end:", JSON.stringify(ends[0].data || {}));
  } else {
    console.log("❌ no cascadeId available — cannot send_prompt");
  }

  ws.close();
  process.exit(0);
}

main().catch((e) => { console.error("FATAL:", e); process.exit(1); });
