// probe_ls4.js — fetch hub LS sessions + per-session trajectory, decode summaries
const http = require("http");

function probe(port, csrf, method, payloadHex, timeoutMs = 15000) {
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
          "x-codeium-csrf-token": csrf,
          "Connect-Protocol-Version": "1",
          "X-Grpc-Web": "1",
          "Content-Length": body.length,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          resolve({ status: res.statusCode, buf: Buffer.concat(chunks) });
        });
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error("timeout")));
    req.on("error", (e) => resolve({ status: 0, buf: Buffer.alloc(0), err: e.message }));
    req.write(body);
    req.end();
  });
}

// decode a gRPC-Web response: frames of [flags(1) len(4) payload]
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

(async () => {
  const PORT = 50634;
  const CSRF = "33403c54-8ec7-4ae3-82b5-2ce290a13da2";
  const r = await probe(PORT, CSRF, "GetAllCascadeTrajectories", "0000000000");
  const fr = frames(r.buf);
  console.log("frames:", fr.length, "first frame len:", fr[0]?.length);
  const top = fields(fr[0]);
  console.log("top-level fields:", top.map((f) => `#${f.fnum}:${f.wt}=${f.wt === 0 ? f.v : f.bytes.length}B`).join(" "));
  let n = 0;
  for (const f of top) {
    if (f.fnum === 1 && f.wt === 2) {
      n++;
      const s = fields(f.bytes);
      let cid = "", title = "", ws = "";
      for (const sf of s) {
        if (sf.fnum === 1 && sf.wt === 2) cid = sf.bytes.toString("utf8");
        if (sf.fnum === 2 && sf.wt === 2) {
          for (const mf of fields(sf.bytes)) {
            if (mf.wt === 2 && mf.bytes.length > 2 && mf.bytes.length < 300) {
              const t = mf.bytes.toString("utf8");
              if (/^[A-Za-zÀ-ÿ]/.test(t) && !t.includes("file:///")) title = t;
            }
            if (mf.wt === 2 && mf.bytes.toString("utf8").startsWith("file:///")) ws = mf.bytes.toString("utf8");
          }
        }
      }
      console.log(`\n=== Session ${n}: cid=${cid} title=${title || "?"} ws=${ws || "?"}`);
      if (n >= 15) break;
    }
  }
  // pick the FIRST session and fetch its trajectory
  for (const f of top) {
    if (f.fnum === 1 && f.wt === 2) {
      const cid = fields(f.bytes).find((sf) => sf.fnum === 1)?.bytes.toString("utf8");
      if (cid) {
        // BuildGetCascadeTrajectory: {1: cascade_id, 2: verbosity=3, 3: trajectory_verbosity=3}
        const cidB = Buffer.from(cid, "utf8");
        const body = Buffer.concat([
          Buffer.from([0x0a, cidB.length]), cidB,
          Buffer.from([0x10, 0x03, 0x18, 0x03]),
        ]);
        const frame = Buffer.concat([Buffer.from([0]), Buffer.alloc(4), body]);
        frame.writeUInt32BE(body.length, 1);
        const tr = await probe(PORT, CSRF, "GetCascadeTrajectory", frame.toString("hex"), 20000);
        const trFrames = frames(tr.buf);
        console.log(`\n== GetCascadeTrajectory(${cid}) -> HTTP ${tr.status}, frames ${trFrames.length}`);
        if (trFrames.length) {
          console.log("   first frame len:", trFrames[0].length, "hex head:", trFrames[0].subarray(0, 100).toString("hex"));
        }
        break;
      }
    }
  }
})().catch((e) => console.error(e));
