// probe_raw_send.js — raw gRPC-Web dump of SendUserCascadeMessage (no parsing, no WS gateway)
// Usage: node probe_raw_send.js <lsPort> <csrf> <cascadeId>
const http = require("http");
const port = parseInt(process.argv[2] || "50634", 10);
const csrf = process.argv[3] || "";
const cascadeId = process.argv[4] || "";

function varint(v) { const out = []; while (v >= 0x80) { out.push((v & 0x7f) | 0x80); v >>>= 7; } out.push(v); return Buffer.from(out); }
function key(n, w) { return varint((n << 3) | w); }
function fieldVarint(n, v) { return Buffer.concat([key(n, 0), varint(v)]); }
function fieldStr(n, s) { const b = Buffer.from(s); return Buffer.concat([key(n, 2), varint(b.length), b]); }
function fieldBytes(n, b) { return Buffer.concat([key(n, 2), varint(b.length), b]); }

// SendUserCascadeMessageRequest: {1: cascade_id, 2: items[{1: text}], 5: cascade_config}
function buildSend(cid, text, modelEnum) {
  const item = fieldStr(1, text);
  // CascadeConfig {1: planner_config {1: plan_model, 2: conv{1: planner_mode=3}, 15: requested_model{1: model}}}
  const conv = fieldVarint(1, 3);
  const reqModel = fieldVarint(1, modelEnum);
  const planner = Buffer.concat([fieldVarint(1, modelEnum), fieldBytes(2, conv), fieldBytes(15, reqModel)]);
  const cfg = fieldBytes(1, planner);
  return Buffer.concat([fieldStr(1, cid), fieldBytes(2, item), fieldBytes(5, cfg)]);
}

function frame(payload) {
  const hdr = Buffer.alloc(5); hdr[0] = 0; hdr.writeUInt32BE(payload.length, 1);
  return Buffer.concat([hdr, payload]);
}

const payload = buildSend(cascadeId, "Dis UNIQUEMENT le mot OK.", 312);
console.log("payload bytes:", payload.length);

const req = http.request({
  host: "127.0.0.1", port, method: "POST",
  path: "/exa.language_server_pb.LanguageServerService/SendUserCascadeMessage",
  headers: {
    "Content-Type": "application/grpc-web+proto",
    "Accept": "application/grpc-web+proto,application/grpc-web-text",
    "x-codeium-csrf-token": csrf,
    "Connect-Protocol-Version": "1",
    "X-Grpc-Web": "1",
    "Content-Length": frame(payload).length,
  },
  timeout: 20000,
}, (res) => {
  const chunks = [];
  res.on("data", (c) => chunks.push(c));
  res.on("end", () => {
    const raw = Buffer.concat(chunks);
    console.log("HTTP", res.statusCode, "| headers:", JSON.stringify(res.headers));
    console.log("raw bytes:", raw.length);
    // hex dump
    for (let i = 0; i < Math.min(raw.length, 512); i += 16) {
      const hex = [...raw.slice(i, i + 16)].map((b) => b.toString(16).padStart(2, "0")).join(" ");
      const ascii = [...raw.slice(i, i + 16)].map((b) => (b >= 32 && b < 127 ? String.fromCharCode(b) : ".")).join("");
      console.log(i.toString(16).padStart(4, "0") + "  " + hex.padEnd(47) + "  " + ascii);
    }
    // grpc-status trailer?
    const body = raw.toString("latin1");
    const st = body.match(/grpc-status: (\d+)/);
    const msg = body.match(/grpc-message: ([^\r\n]+)/);
    console.log("grpc-status:", st ? st[1] : "none", "| grpc-message:", msg ? decodeURIComponent(msg[1]) : "none");
    process.exit(0);
  });
});
req.on("error", (e) => { console.error("ERR:", e.message); process.exit(1); });
req.on("timeout", () => { console.error("TIMEOUT"); req.destroy(); process.exit(1); });
req.write(frame(payload));
req.end();
