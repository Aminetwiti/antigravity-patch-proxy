const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/proxy/shared.js');
fs.writeFileSync('diag/extracted-shared.js', buf);
console.log('shared.js:', buf.length, 'bytes');
const txt = buf.toString('utf8');
const lines = txt.split('\n');
console.log('Total lines:', lines.length);
// Find cleanup-related code
const idx = lines.findIndex(l => l.includes('CleanupInterval') || l.includes('setInterval'));
console.log('First cleanup-related line:', idx + 1);
if (idx >= 0) {
  for (let i = Math.max(0, idx - 2); i < Math.min(lines.length, idx + 30); i++) {
    console.log((i + 1) + ': ' + lines[i]);
  }
}
