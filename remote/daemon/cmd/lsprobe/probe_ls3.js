// probe_ls3.js — HTTP on 50634 (hub LS other port) + 58701 with metadata body
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
  // hub LS plaintext port 50634
  await probe("http", 50634, "33403c54-8ec7-4ae3-82b5-2ce290a13da2", "GetAllCascadeTrajectories", "0000000000");
  // IDE LS 2.8 on 58701 with the OTHER csrf (extension server one)
  await probe("http", 58701, "a80d4de5-62d1-4c77-81f6-c6b87782970b", "GetAllCascadeTrajectories", "0000000000");
  // and its https_server_port 49393
  await probe("https", 49393, "aece2760-af5f-4348-a514-afb53edf13af", "GetAllCascadeTrajectories", "0000000000");
})().catch((e) => console.error(e));
