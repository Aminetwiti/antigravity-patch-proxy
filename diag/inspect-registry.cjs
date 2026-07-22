const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', '/dist/proxy/registry.js');
fs.writeFileSync('diag/extracted-registry.js', buf);
const txt = buf.toString('utf8');
const lines = txt.split('\n');
console.log('registry.js:', lines.length, 'lines');
// Show the constructor and initial code
console.log('\n=== First 50 lines ===');
lines.slice(0, 50).forEach((l, i) => console.log((i + 1) + ': ' + l));
console.log('\n=== Where "Loaded provider translator" comes from ===');
lines.forEach((l, i) => {
  if (l.includes('Loaded provider translator')) console.log((i + 1) + ': ' + l);
});
