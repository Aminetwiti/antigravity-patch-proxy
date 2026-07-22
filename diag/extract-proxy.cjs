const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/proxy.js');
fs.writeFileSync('diag/extracted-proxy.js', buf);
console.log('proxy.js:', buf.length, 'bytes saved');
