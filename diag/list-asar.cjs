const asar = require('@electron/asar');
const list = asar.listPackage('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar');
console.log('Total entries:', list.length);
// Filter proxy files
const proxyFiles = list.filter(p => p.toLowerCase().includes('proxy') || p.toLowerCase().includes('shared') || p.toLowerCase().includes('crypto') || p.toLowerCase().includes('custom') || p.toLowerCase().includes('schema'));
console.log('Proxy-related files:');
proxyFiles.forEach(p => console.log('  ' + p));
