// probe_ls2.js — try https with rejectUnauthorized=false + alternate paths
const https = require("https");
const http = require("http");

function probe(proto, port, csrf, method, payloadHex) {
  return new Promise((resolve) => {
    const body = Buffer.from(payloadHex, "hex");
    const lib = proto === "https" ? https : http;
    const req = lib.request(
      {
        host: "127.0.0.1",
        port,
        path: `/exa.language_server_pb.LanguageServerService/${method}`,
        method: "POST",
        rejectUnauthorized: false,
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
          const buf = Buffer.concat(chunks);
          console.log(`== ${method} @${proto}://${port} -> HTTP ${res.statusCode}, ${buf.length} bytes`);
          console.log("   hex:", buf.subarray(0, 200).toString("hex"));
          console.log("   text:", buf.subarray(0, 120).toString("utf8"));
          resolve({ status: res.statusCode, buf });
        });
      }
    );
    req.on("error", (e) => {
      console.log(`== ${method} @${proto}://${port} -> ERR ${e.message}`);
      resolve({ status: 0, buf: Buffer.alloc(0) });
    });
    req.write(body);
    req.end();
  });
}

(async () => {
  // Hub LS: try all candidate ports/protocols
  await probe("https", 50634, "33403c54-8ec7-4ae3-82b5-2ce290a13da2", "GetAllCascadeTrajectories", "0000000000");
  await probe("http", 50633, "33403c54-8ec7-4ae3-82b5-2ce290a13da2", "GetAllCascadeTrajectories", "0000000000");
  // IDE LS 2.8 (hub subtype - the one the daemon's discovery found with CSRF aece2760)
  await probe("https", 58701, "aece2760-af5f-4348-a514-afb53edf13af", "GetAllCascadeTrajectories", "0000000000");
  await probe("http", 58701, "aece2760-af5f-4348-a514-afb53edf13af", "GetAllCascadeTrajectories", "0000000000");
})().catch((e) => console.error(e));
