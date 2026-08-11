import { discoverLocalHarness } from './discovery.js';
import { ConnectRpcClient } from './client.js';

async function main() {
  console.log('🔍 Scanning local environment for localharness process...');
  const info = await discoverLocalHarness();
  if (!info) {
    console.error('❌ Discovery failed.');
    process.exit(1);
  }

  console.log(`✅ Connected to localharness (Port: ${info.connectRpcPort})`);
  const client = new ConnectRpcClient(info.connectRpcPort, info.csrfToken);

  console.log('\n--- 1. Testing GetAllCascades ---');
  try {
    const cascades = await client.getAllCascades();
    console.log('Active Cascades:', JSON.stringify(cascades, null, 2));
  } catch (err: any) {
    console.error('Error fetching cascades:', err.message);
  }
}

main().catch(console.error);
