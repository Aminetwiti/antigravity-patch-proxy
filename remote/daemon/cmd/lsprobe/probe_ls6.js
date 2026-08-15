// probe_ls6.js — send prompt and check the conversations DB + transcript for a new step
const http = require("http");
const fs = require("fs");
const { execSync } = require("child_process");

const PORT = 50634;
const CSRF = "33403c54-8ec7-4ae3-82b5-2ce290a13da2";
const CASCADE_ID = "0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f";
const PROMPT = "Dis bonjour en un seul mot";
const DB = "C:\\Users\\amine\\.gemini\\antigravity\\conversations\\" + CASCADE_ID + ".db";

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
        res.on("end", () => resolve({ status: res.statusCode, buf: Buffer.concat(chunks) }));
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error("timeout")));
    req.on("error", (e) => resolve({ status: 0, buf: Buffer.alloc(0), err: e.message }));
    req.write(body);
    req.end();
  });
}

function frames(buf) {
  if (!buf || buf.length === 0) return [];
  const out = [];
  let o = 0;
  while (o + 5 <= buf.length) {
    const flags = buf[o];
    const len = buf.readUInt32BE(o + 1);
    o += 5;
    if (o + len > buf.length) break;
    if ((flags & 0x80) === 0) out.push(buf.subarray(o, o + len));
    o += len;
  }
  return out;
}

function readVarint(b, i) {
  let val = 0n, shift = 0n;
  while (true) {
    const x = b[i++];
    val |= BigInt(x & 0x7f) << shift;
    if (!(x & 0x80)) return [val, i];
    shift += 7n;
  }
}

function fields(b) {
  const out = [];
  let i = 0;
  while (i < b.length) {
    const [key, ni] = readVarint(b, i);
    i = ni;
    const fnum = Number(key >> 3n);
    const wt = Number(key & 7n);
    if (wt === 0) {
      const [v, nv] = readVarint(b, i);
      out.push({ fnum, wt, v });
      i = nv;
    } else if (wt === 2) {
      const [len, nl] = readVarint(b, i);
      i = nl;
      out.push({ fnum, wt, bytes: b.subarray(i, i + Number(len)) });
      i += Number(len);
    } else break;
  }
  return out;
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
  // step 0: read DB step count BEFORE
  const before = execSync(`python -c "import sqlite3; print(sqlite3.connect('${DB.replace(/\\/g, '\\\\')}').execute('SELECT COUNT(*) FROM steps').fetchone()[0])"`).toString().trim();
  console.log("steps before:", before);
  const frame = buildSendMessage(CASCADE_ID, PROMPT);
  const resp = await request(PORT, "SendUserCascadeMessage", frame.toString("hex"), 120000);
  const fr = frames(resp.buf);
  console.log(`-> HTTP ${resp.status}, ${resp.buf.length} bytes, ${fr.length} data frames${resp.err ? " err=" + resp.err : ""}`);
  // wait 2s for flush, then check db
  await new Promise((r) => setTimeout(r, 2000));
  const after = execSync(`python -c "import sqlite3; print(sqlite3.connect('${DB.replace(/\\/g, '\\\\')}').execute('SELECT COUNT(*) FROM steps').fetchone()[0])"`).toString().trim();
  console.log("steps after:", after);
  if (fr.length) {
    fr.slice(0, 4).forEach((f, i) => console.log(`  frame[${i}] len=${f.length} hex=${f.subarray(0, 100).toString("hex")}`));
  }
})().catch((e) => console.error(e));
