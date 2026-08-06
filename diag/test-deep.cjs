// Patch modelLoader to log exact names being validated
const Module = require('module');
const origLoad = Module._load;
const mocks = {
  electron: {
    app: {
      getPath: (k) => k === 'home' ? require('os').homedir() : require('os').homedir(),
      isPackaged: false,
    },
    safeStorage: {
      isEncryptionAvailable: () => false,
      encryptString: (s) => Buffer.from(s, 'utf-8'),
      decryptString: (b) => b.toString('utf-8'),
    },
  },
  'electron-log/main': () => ({ info: console.log, warn: console.log, error: console.log, debug: console.log }),
};
Module._load = function (req, parent, ...rest) {
  if (req in mocks) return mocks[req];
  return origLoad.call(this, req, parent, ...rest);
};

process.chdir(__dirname);
const path = require('path');
const distRoot = path.join(__dirname, '..', 'dist');
const modelLoaderPath = path.join(distRoot, 'proxy', 'modelLoader.js');

// Read source to patch
const fs = require('fs');
let src = fs.readFileSync(modelLoaderPath, 'utf-8');

// Inject log: print the name BEFORE validateCustomModel
src = src.replace(
  'const validation = (0, schemaValidator_1.validateCustomModel)(m);',
  'console.log("VALIDATING:", JSON.stringify({name: m.name, provider: m.provider, len: (m.name||"").length, startsWithModels: m.name && m.name.startsWith("models/"), includesSlash: m.name && m.name.includes("/"), typeOfName: typeof m.name})); const validation = (0, schemaValidator_1.validateCustomModel)(m);'
);
fs.writeFileSync(modelLoaderPath, src);

const modelLoader = require(modelLoaderPath);
const result = modelLoader.loadCustomModels();
console.log('\nFINAL:', result.length, 'models');