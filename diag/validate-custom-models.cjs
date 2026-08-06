// Run actual schema validation on flattened custom_models.json
const fs = require('fs');
const path = require('path');
const home = require('os').homedir();
const filePath = path.join(home, '.gemini', 'antigravity', 'custom_models.json');
let content = fs.readFileSync(filePath, 'utf-8');
if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);
const parsed = JSON.parse(content);

// Read ALL_PROVIDERS from compiled constants
const constantsJs = path.join(__dirname, '..', 'dist', 'constants.js');
let ALL_PROVIDERS = ['anthropic', 'google', 'openai', 'ollama', 'custom']; // fallback
try {
  delete require.cache[require.resolve(constantsJs)];
  const c = require(constantsJs);
  if (c.ALL_PROVIDERS) ALL_PROVIDERS = c.ALL_PROVIDERS;
  console.log('ALL_PROVIDERS (from compiled dist/constants.js):', JSON.stringify(ALL_PROVIDERS));
} catch (e) {
  console.log('Could not require constants, using fallback:', e.message);
}

const flatModels = [];
for (const p of parsed.providers || []) {
  if (!p.enabled) continue;
  for (const m of p.models || []) {
    if (!m.enabled) continue;
    flatModels.push({
      name: 'models/MODEL_PLACEHOLDER_M' + p.provider + '_' + m.id.replace(/[^a-zA-Z0-9_-]/g,'_'),
      displayName: m.displayName || m.id,
      provider: p.provider,
      apiKey: p.apiKey,
      encrypted: p.encrypted,
      apiUrl: p.apiUrl,
      externalModelName: m.id,
      allowUnauthorized: p.allowUnauthorized,
    });
  }
}
console.log('Flattened', flatModels.length, 'models');

function validateCustomModel(model) {
  if (!model || typeof model !== 'object') return { valid: false, error: 'Model is null or not an object' };
  const m = model;
  const required = ['name', 'provider', 'apiUrl'];
  for (const field of required) {
    if (!m[field] || typeof m[field] !== 'string') return { valid: false, error: `Missing or invalid required field: ${field}` };
  }
  const name = m.name;
  if (!name.startsWith('models/') && !name.includes('/')) {
    return { valid: false, error: 'Model name must start with "models/"' };
  }
  const provider = m.provider;
  if (!ALL_PROVIDERS.includes(provider)) return { valid: false, error: `Unsupported provider: ${provider}` };
  try {
    const url = new URL(m.apiUrl);
    if (!['http:','https:'].includes(url.protocol)) return { valid: false, error: 'API URL must use http or https' };
  } catch (e) {
    return { valid: false, error: 'Invalid API URL: ' + e.message };
  }
  return { valid: true };
}

console.log('=== Validation ===');
let valid = 0;
flatModels.forEach((m, i) => {
  const r = validateCustomModel(m);
  console.log((i+1) + '.', m.displayName, '[' + m.provider + ']', '->', r.valid ? 'OK' : 'FAIL: ' + r.error);
  if (r.valid) valid++;
});
console.log('\n' + valid + '/' + flatModels.length + ' valid');
