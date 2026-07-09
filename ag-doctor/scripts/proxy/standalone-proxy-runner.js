const path = require('path');
const fs = require('fs');

// Attempt to find the built proxy.js in app.asar or locally in the root dist/
let proxyPath = process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Programs', 'antigravity', 'resources', 'app.asar', 'dist', 'proxy.js') : '';

if (!fs.existsSync(proxyPath)) {
  // Fallback to local root dist
  proxyPath = path.resolve(__dirname, '..', '..', '..', 'dist', 'proxy.js');
}

if (!fs.existsSync(proxyPath)) {
  console.error(`[StandaloneProxy] Could not find proxy.js at ${proxyPath}`);
  process.exit(1);
}

console.log(`[StandaloneProxy] Loading proxy from ${proxyPath}`);

// Setup minimal Electron app mock if we are running in pure node
if (!process.versions.electron) {
  // Mock electron app for the proxy since it expects it
  const mockApp = {
    isPackaged: true,
    getVersion: () => '2.1.0',
    getPath: (name) => {
      if (name === 'userData') {
        const p = path.join(process.env.APPDATA || process.env.HOME || '', 'Antigravity');
        if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
        return p;
      }
      return '';
    }
  };

  const electronMock = {
    app: mockApp,
    safeStorage: {
      isEncryptionAvailable: () => false,
      encryptString: (s) => Buffer.from(s),
      decryptString: (b) => b.toString()
    }
  };

  const Module = require('module');
  const originalRequire = Module.prototype.require;
  Module.prototype.require = function(mod) {
    if (mod === 'electron') return electronMock;
    return originalRequire.apply(this, arguments);
  };
}

const proxy = require(proxyPath);

proxy.startProxy().then((port) => {
  console.log(`[StandaloneProxy] Proxy started successfully on port ${port}`);
}).catch(err => {
  console.error('[StandaloneProxy] Failed to start proxy:', err);
  process.exit(1);
});
