const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/languageServer.js');
fs.writeFileSync('diag/extracted-ls.js', buf);
console.log('languageServer.js:', buf.length, 'bytes');
const txt = buf.toString('utf8');
// Find getLsCL and LS_BINARY
const lsBinaryMatch = txt.match(/LS_BINARY\s*=\s*[^;]+;/);
console.log('LS_BINARY def:', lsBinaryMatch ? lsBinaryMatch[0] : 'NOT FOUND');
const lsBinaryLine = txt.split('\n').findIndex(l => l.includes('LS_BINARY ='));
console.log('LS_BINARY at line:', lsBinaryLine + 1);
const getLsCLMatch = txt.match(/function getLsCL\([\s\S]*?^\}/m);
console.log('getLsCL:', getLsCLMatch ? getLsCLMatch[0].slice(0, 400) : 'NOT FOUND');
