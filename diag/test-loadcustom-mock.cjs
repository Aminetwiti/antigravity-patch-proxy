// Mock the 'electron' module so dist code can be loaded standalone
const Module = require('module');
const origResolve = Module._resolveFilename;
const path = require('path');

const mocks = {
  electron: {
    app: {
      getPath: (key) => {
        if (key === 'home') return require('os').homedir();
        if (key === 'userData') return path.join(require('os').homedir(), '.gemini', 'antigravity');
        return require('os').homedir();
      },
      isPackaged: false,
    },
    safeStorage: {
      isEncryptionAvailable: () => false,  // Disable safeStorage so it falls back to base64
      encryptString: (s) => Buffer.from(s, 'utf-8'),
      decryptString: (b) => b.toString('utf-8'),
    },
  },
  'electron-log/main': () => ({
    info: (...a) => console.log('[info]', ...a),
    warn: (...a) => console.log('[warn]', ...a),
    error: (...a) => console.log('[error]', ...a),
    debug: (...a) => console.log('[debug]', ...a),
  }),
};

Module._resolveFilename = function (req, ...rest) {
  if (req in mocks) return req;
  return origResolve.call(this, req, ...rest);
};
const origLoad = Module._load;
Module._load = function (req, parent, ...rest) {
  if (req in mocks) return mocks[req];
  return origLoad.call(this, req, parent, ...rest);
};

// Now require the compiled modules
process.chdir(__dirname);
const distRoot = path.join(__dirname, '..', 'dist');
const constants = require(path.join(distRoot, 'constants.js'));
const schemaValidator = require(path.join(distRoot, 'schemaValidator.js'));
const cryptoStore = require(path.join(distRoot, 'cryptoStore.js'));
const modelLoader = require(path.join(distRoot, 'proxy', 'modelLoader.js'));

console.log('ALL_PROVIDERS:', JSON.stringify(constants.ALL_PROVIDERS));

let result;
try {
  result = modelLoader.loadCustomModels();
  console.log('\nloadCustomModels() returned', Array.isArray(result) ? result.length : 'NOT AN ARRAY', 'models');
  if (Array.isArray(result)) {
    result.forEach((m, i) => {
      console.log('  ' + (i+1) + '.', m.name, '[' + m.provider + ']', 'url=' + m.apiUrl);
    });
  } else {
    console.log('Result:', JSON.stringify(result, null, 2));
  }
} catch (e) {
  console.error('ERROR:', e.message);
  console.error(e.stack);
}