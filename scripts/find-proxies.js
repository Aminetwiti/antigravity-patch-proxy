const { execSync } = require('child_process');
const out = execSync(
  'powershell -NoProfile -Command "Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { [int]$_.LocalPort -in @(51074,49672,51999,50999,51075) } | Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json -Compress"',
  { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 },
);
let data;
try { data = JSON.parse(out.trim() || '[]'); } catch { data = []; }
const list = Array.isArray(data) ? data : [data];
console.log('=== LISTENERS ===');
for (const p of list) {
  if (!p) continue;
  console.log(p.LocalAddress + ':' + p.LocalPort + ' (pid ' + p.OwningProcess + ')');
}

console.log('\n=== PROXY PROCESSES ===');
const out2 = execSync(
  'powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \'Name=\\\'electron.exe\\\'\' | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"',
  { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 },
);
let data2;
try { data2 = JSON.parse(out2.trim() || '[]'); } catch { data2 = []; }
const list2 = Array.isArray(data2) ? data2 : [data2];
for (const p of list2) {
  const cl = (p?.CommandLine || '').toString();
  if (cl.includes('standalone-proxy-runner') || cl.includes('proxy-stub') || cl.includes('ag-doctor.js --worker') || cl.includes('ag-doctor-ui')) {
    console.log('pid=' + p.ProcessId + '\n  ' + cl.slice(0, 300));
  }
}
