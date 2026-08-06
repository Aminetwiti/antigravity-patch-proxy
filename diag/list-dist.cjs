const fs = require('fs');
const asar = require('@electron/asar');
const list = asar.listPackage('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar');
const proxyFiles = list.filter(p => p.includes('proxy')).slice(0, 20);
console.log('Sample proxy paths from list:');
proxyFiles.forEach(p => console.log(JSON.stringify(p)));
// Try different path formats
const paths = ['\\dist\\proxy\\registry.js', 'dist/proxy/registry.js', 'dist\\proxy\\registry.js'];
for (const p of paths) {
  try {
    const buf = asar.extractFile('C:/Users/amine/AppData/Local/Programs/Antigravity/resources/app.asar', p);
    console.log(`OK with path ${JSON.stringify(p)}: ${buf.length} bytes`);
    fs.writeFileSync('diag/extracted-registry.js', buf);
    break;
  } catch (e) {
    console.log(`FAIL ${JSON.stringify(p)}: ${e.message.split('\n')[0]}`);
  }
}
