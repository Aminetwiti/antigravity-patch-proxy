// probe_ls8.js — reproduce daemon's EXACT BuildSendMessage bytes and test against real LS
const http = require("http");

const PORT = 50634;
const CSRF = "33403c54-8ec7-4ae3-82b5-2ce290a13da2";
const CASCADE_ID = "0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f";
const PROMPT = "Dis bonjour en un seul mot";
const MODEL_UID = "gemini-3.0-flash-high";

// 1:1 port of daemon pkg/connectrpc/protobuf.go writer + BuildCascadeConfig
function w() {
  const b = [];
  const varint = (v) => {
    while (v >= 0x80) {
      b.push((v & 0x7f) | 0x80);
      v = Math.floor(v / 128);
    }
    b.push(v & 0x7f);
  };
  const key = (f, wt) => varint((f << 3) | wt);
  const vf = (f, v) => { key(f, 0); varint(v); };
  const sf = (f, s) => { key(f, 2); varint(Buffer.byteLength(s)); b.push(...Buffer.from(s, "utf8")); };
  const bf = (f, d) => { key(f, 2); varint(d.length); b.push(...d); };
  return { b, varint, key, vf, sf, bf };
}

function buildCascadeConfig(modelUID, modelEnum) {
  const planner = w();
  if (modelEnum === 0) modelEnum = 246;
  planner.vf(1, modelEnum);
  const conv = w();
  conv.vf(1, 3); // planner_mode 3 = NO_TOOL
  planner.bf(2, conv.b);
  if (modelUID !== "") {
    const alias = w();
    alias.sf(1, modelUID);
    planner.bf(15, alias.b);
  }
  return planner.b;
}

function buildMetadata(apiKey, sessionID) {
  const m = w();
  m.sf(1, "Antigravity");
  m.sf(2, "2.5.0");
  m.sf(3, apiKey);
  m.sf(7, "2.5.0");
  m.sf(8, "x86_64");
  m.sf(12, "antigravity.remote");
  m.sf(10, sessionID);
  return m.b;
}

function buildSendMessage(cid, text, apiKey, sessionID, modelUID, modelEnum) {
  const item = w();
  item.sf(1, text);
  const out = w();
  out.sf(1, cid);
  out.bf(2, item.b);
  if (apiKey !== "") out.bf(3, buildMetadata(apiKey, sessionID));
  out.bf(5, buildCascadeConfig(modelUID, modelEnum));
  return out.b;
}

function request(port, method, payloadHex, timeoutMs) {
  return new Promise((resolve) => {
    const body = Buffer.from(payloadHex, "hex");
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path: `/exa.language_server_pb.LanguageServerService/${method}`,
        method: "POST",
        headers: {
          "Content-Type": "application/grpc-web+proto",
          Accept: "application/grpc-web+proto,application/grpc-web-text",
          "x-codeium-csrf-token": CSRF,
          "Connect-Protocol-Version": "1",
          "X-Grpc-Web": "1",
          "Content-Length": body.length,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, buf: Buffer.concat(chunks) }));
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error("timeout")));
    req.on("error", (e) => resolve({ status: 0, buf: Buffer.alloc(0), err: e.message }));
    req.write(body);
    req.end();
  });
}

(async () => {
  const payload = Buffer.from(buildSendMessage(CASCADE_ID, PROMPT, "api-key-placeholder", "probe-session-0001", MODEL_UID, 0));
  console.log("payload hex:", payload.toString("hex"));
  const frame = Buffer.concat([Buffer.from([0]), Buffer.alloc(4), payload]);
  frame.writeUInt32BE(payload.length, 1);
  const resp = await request(PORT, "SendUserCascadeMessage", frame.toString("hex"), 120000);
  console.log(`-> HTTP ${resp.status}, body ${resp.buf.length} bytes${resp.err ? " err=" + resp.err : ""}`);
  if (resp.buf.length > 0) console.log("head:", resp.buf.subarray(0, 60).toString("hex"));
  const s = resp.buf.toString("latin1");
  const m = s.match(/grpc-status[=:]\s*(\d+)/i);
  if (m) console.log("grpc-status:", m[1]);
  console.log("trailers:", JSON.stringify(resp.headers["grpc-status"] || resp.headers["grpc-status-text"] || "(none)"));
})().catch((e) => console.error(e));
