// probe_ls9.js — real-format cascade_config: flat #11 model + #13 ModelOrAlias
const http = require("http");

const PORT = 50634;
const CSRF = "33403c54-8ec7-4ae3-82b5-2ce290a13da2";
const CASCADE_ID = "0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f";
const PROMPT = "Dis bonjour en un seul mot";
const MODEL_ENUM = 1196; // real IDE enum seen in sessions
const MODEL_UID = "";    // empty → ModelOrAlias {1: model}

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

// REAL-format cascade config (flat): #11 plan_model varint, #13 ModelOrAlias
function buildCascadeConfigReal(modelEnum) {
  const cc = w();
  cc.vf(11, modelEnum);          // plan_model
  const alias = w();
  alias.vf(1, modelEnum);        // ModelOrAlias {1: model}
  cc.bf(13, alias.b);            // requested_model
  return cc.b;
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

function buildSendMessage(cid, text, apiKey, sessionID, config) {
  const item = w();
  item.sf(1, text);
  const out = w();
  out.sf(1, cid);
  out.bf(2, item.b);
  if (apiKey !== "") out.bf(3, buildMetadata(apiKey, sessionID));
  out.bf(5, config);
  return out.b;
}

function request(port, method, payload, timeoutMs) {
  return new Promise((resolve) => {
    const frame = Buffer.concat([Buffer.from([0]), Buffer.alloc(4), payload]);
    frame.writeUInt32BE(payload.length, 1);
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
          "Content-Length": frame.length,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve({ status: res.statusCode, buf: Buffer.concat(chunks) }));
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error("timeout")));
    req.on("error", (e) => resolve({ status: 0, buf: Buffer.alloc(0), err: e.message }));
    req.write(frame);
    req.end();
  });
}

(async () => {
  const payload = Buffer.from(buildSendMessage(CASCADE_ID, PROMPT, "api-key-placeholder", "probe-session-0002", buildCascadeConfigReal(MODEL_ENUM)));
  console.log("payload hex:", payload.toString("hex"));
  const t0 = Date.now();
  const resp = await request(PORT, "SendUserCascadeMessage", payload, 120000);
  console.log(`-> HTTP ${resp.status}, body ${resp.buf.length} bytes, ${Date.now() - t0}ms${resp.err ? " err=" + resp.err : ""}`);
  if (resp.buf.length > 0) console.log("head hex:", resp.buf.subarray(0, 40).toString("hex"));
  const s = resp.buf.toString("latin1");
  const m = s.match(/grpc-status[=:]\s*(\d+)/i);
  if (m) console.log("grpc-status:", m[1]);
})().catch((e) => console.error(e));
