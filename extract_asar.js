const a = require('@electron/asar');
const src = '/mnt/c/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar';
const dest = '/tmp/asar_inspect/current';
require('fs').rmSync(dest, { recursive: true, force: true });
require('fs').mkdirSync(dest, { recursive: true });
const files = a.extractAll(src, dest);
console.log('Extracted', files.length, 'files to', dest);
console.log('Version:', require(dest + '/package.json').version);
