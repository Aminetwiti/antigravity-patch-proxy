const asar = require('@electron/asar');
const fs = require('fs');

// Extract preload to find all channels it invokes
const preload = Buffer.from(asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/preload.js')).toString('utf8');
const invokeRe = /ipcRenderer\.invoke\(\s*['"]([^'"]+)['"]/g;
let m;
const invoked = new Set();
while ((m = invokeRe.exec(preload)) !== null) invoked.add(m[1]);

// Get all ipcMain handlers
const ipc = Buffer.from(asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', 'dist/ipcHandlers.js')).toString('utf8');
const handleRe = /ipcMain\.handle\(\s*['"]([^'"]+)['"]/g;
const handled = new Set();
while ((m = handleRe.exec(ipc)) !== null) handled.add(m[1]);

console.log('--- Channels preload INVOKES but ipcHandlers does NOT HANDLE ---');
const missing = Array.from(invoked).filter(c => !handled.has(c)).sort();
missing.forEach(c => console.log('  ❌ ' + c));
console.log('\nTotal invoked: ' + invoked.size + ', missing: ' + missing.length);