const fs = require('fs');
const asar = require('@electron/asar');
const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/constants.js');
fs.writeFileSync('diag/extracted-constants.js', buf);
console.log(buf.toString('utf8'));
