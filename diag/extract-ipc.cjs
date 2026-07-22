const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/ipcHandlers.js');
fs.writeFileSync('diag/extracted-ipc.js', buf);
const txt = buf.toString('utf8');
console.log('ipcHandlers.js:', buf.length, 'bytes');
const lines = txt.split('\n');
console.log('Total lines:', lines.length);

// Find all ipcMain.handle references
console.log('\n=== ipcMain.handle occurrences ===');
const matches = [...txt.matchAll(/ipcMain\.handle\([^)]+,/g)];
console.log('Total matches:', matches.length);
matches.forEach((m, i) => {
  const lineNum = txt.substring(0, m.index).split('\n').length;
  console.log(`  ${i + 1}. line ${lineNum}: ${txt.substring(m.index, Math.min(m.index + 120, txt.length)).replace(/\n/g, '\\n')}`);
});

// Look for "stripped" comments to see if dedupe ran
const stripped = (txt.match(/v2\.3\.x patch[^\\n]*stripped/gi) || []).length;
console.log('\nStripped comments found:', stripped);

// Check if there's any obvious syntax issue
console.log('\n=== End of file ===');
console.log(lines.slice(-10).join('\n'));
