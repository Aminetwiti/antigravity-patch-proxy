// Run the REAL modelLoader.loadCustomModels() as compiled in dist/
const path = require('path');
process.chdir(__dirname);
const distRoot = path.join(__dirname, '..', 'dist');

// Polyfill what modelLoader needs
const home = require('os').homedir();
process.env.HOME = home;
process.env.USERPROFILE = home;

// Patch the path it uses
const constants = require(path.join(distRoot, 'constants.js'));
const schemaValidator = require(path.join(distRoot, 'schemaValidator.js'));
const cryptoStore = require(path.join(distRoot, 'cryptoStore.js'));
const modelLoader = require(path.join(distRoot, 'proxy', 'modelLoader.js'));

console.log('Home:', home);
console.log('custom_models path:', path.join(home, '.gemini', 'antigravity', 'custom_models.json'));

let result;
try {
  result = modelLoader.loadCustomModels();
  console.log('loadCustomModels() returned', Array.isArray(result) ? result.length : 'NOT AN ARRAY', 'models');
  if (Array.isArray(result)) {
    result.forEach((m, i) => {
      console.log('  ' + (i+1) + '.', m.name, '[' + m.provider + ']', 'url=' + m.apiUrl, 'key=' + (m.apiKey ? m.apiKey.slice(0, 30) : 'NONE'));
    });
  } else {
    console.log('Result:', result);
  }
} catch (e) {
  console.error('ERROR:', e.message);
  console.error(e.stack);
}

// Also re-run the validator directly
const flatModels = require('fs').readFileSync(path.join(home, '.gemini', 'antigravity', 'custom_models.json'), 'utf-8');
const parsed = JSON.parse(flatModels.charCodeAt(0) === 0xFEFF ? flatModels.slice(1) : flatModels);
const allFlat = [];
for (const p of parsed.providers || []) {
  if (!p.enabled) continue;
  for (const m of p.models || []) {
    if (!m.enabled) continue;
    const det = `models/MODEL_PLACEHOLDER_M${p.provider}_${m.id}`.replace(/[^a-zA-Z0-9_-]/g, '_');
    allFlat.push({
      name: det, displayName: m.displayName || m.id, provider: p.provider,
      apiKey: p.apiKey, encrypted: p.encrypted, apiUrl: p.apiUrl,
      externalModelName: m.id, allowUnauthorized: p.allowUnauthorized,
    });
  }
}
console.log('\n--- After simulate cryptoStore.decryptModels ---');
let decrypted = null;
try {
  decrypted = cryptoStore.decryptModels(allFlat);
  console.log('decrypt returned', decrypted.length, 'models');
  decrypted.forEach((m, i) => {
    console.log('  ' + (i+1) + '.', 'name=' + m.name, 'provider=' + m.provider, 'apiKey=' + (m.apiKey ? m.apiKey.slice(0,30)+'...' : 'NULL'));
    const v = schemaValidator.validateCustomModel(m);
    console.log('    →', v.valid ? 'VALID' : 'INVALID: ' + v.error);
  });
} catch (e) {
  console.log('decryptModels threw:', e.message);
}
