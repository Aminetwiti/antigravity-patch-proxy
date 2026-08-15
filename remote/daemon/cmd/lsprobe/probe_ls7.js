// probe_ls7.js — create a NEW cascade from scratch: send SendUserCascadeMessage with a fresh UUID
const http = require("http");
const crypto = require("crypto");

const PORT = 50634;
const CSRF = "33403c54-8ec7-4ae3-82b5-2ce290a13da2";
const NEW_CASCADE = crypto.randomUUID();
const PROMPT = "Bonjour depuis le test E2E mobile - reponds en un mot";

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

function buildMetadata() {
  const parts = [];
  const put = (f, s) => {
    const b = Buffer.from(s, "utf8");
    parts.push(Buffer.from([f * 8 + 2, b.length]), b);
  };
  put(1, "Antigravity");
  put(2, "2.5.0");
  put(3, "api-key-placeholder");
  put(7, "2.5.0");
  put(8, "x86_64");
  put(12, "antigravity.remote");
  put(10, "probe-session-0001");
  return Buffer.concat(parts);
}

function buildSendMessage(cid, text) {
  const item = Buffer.concat([Buffer.from([0x0a, text.length]), Buffer.from(text, "utf8")]);
  const meta = buildMetadata();
  const cidB = Buffer.from(cid, "utf8");
  const config = Buffer.from([0x0a, 0x04, 0x08, 0xf6, 0x01, 0x12, 0x02, 0x08, 0x03]);
  const body = Buffer.concat([
    Buffer.from([0x0a, cidB.length]), cidB,
    Buffer.from([0x12, item.length]), item,
    Buffer.from([0x1a, meta.length]), meta,
    Buffer.from([0x2a, config.length]), config,
  ]);
  const frame = Buffer.concat([Buffer.from([0]), Buffer.alloc(4), body]);
  frame.writeUInt32BE(body.length, 1);
  return frame;
}

(async () => {
  console.log("new cascade:", NEW_CASCADE);
  const frame = buildSendMessage(NEW_CASCADE, PROMPT);
  const resp = await request(PORT, "SendUserCascadeMessage", frame.toString("hex"), 120000);
  console.log(`-> HTTP ${resp.status}${resp.err ? " err=" + resp.err : ""}`);
  console.log("trailer grpc-status:", resp.headers["grpc-status"] || resp.headers["grpc-status-text"] || "(none)");
  const body = resp.buf;
  console.log("body bytes:", body.length);
  if (body.length > 0) {
    console.log("head hex:", body.subarray(0, 80).toString("hex"));
    // find grpc-status trailer if present
    const s = body.toString("latin1");
    const m = s.match(/grpc-status: ?(\d+)/i) || s.match(/grpc-status=(\d+)/i);
    if (m) console.log("embedded grpc-status:", m[1]);
  }
})().catch((e) => console.error(e));
