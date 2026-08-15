// probe_ls.js — raw gRPC-Web probe against the standalone Hub LS (no deps)
const http = require("http");

function probe(port, csrf, method, payloadHex) {
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
          const buf = Buffer.concat(chunks);
          console.log(`== ${method} @${port} -> HTTP ${res.statusCode}, ${buf.length} bytes`);
          console.log("   hex:", buf.subarray(0, 160).toString("hex"));
          resolve({ status: res.statusCode, buf });
        });
      }
    );
    req.on("error", (e) => {
      console.log(`== ${method} @${port} -> ERR ${e.message}`);
      resolve({ status: 0, buf: Buffer.alloc(0) });
    });
    req.write(body);
    req.end();
  });
}

(async () => {
  // Hub LS on 50633 (port 0 https → plain HTTP gRPC-Web)
  await probe(50633, "33403c54-8ec7-4ae3-82b5-2ce290a13da2", "GetAllCascadeTrajectories", "0000000000");
})().catch((e) => console.error(e));
