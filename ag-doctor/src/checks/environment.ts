/**
 * Environment check — Node version, OS, arch, npm presence.
 */
import { execSync } from 'child_process';
import type { CheckResult } from '../types';
import { getNodeMajor, getSystemInfo } from '../core/platform';

export function checkEnvironment(): CheckResult {
  const info = getSystemInfo();
  const nodeMajor = getNodeMajor();
  if (nodeMajor < 18) {
    return {
      id: 'env.node',
      title: 'Node.js version',
      status: 'error',
      message: `Node ${info.nodeVersion} found, but >= 18 is required`,
      fixable: false,
    };
  }
  let npmVersion = 'unknown';
  try {
    npmVersion = execSync('npm --version', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
  } catch {
    // npm not found
  }
  const supported = ['win32', 'darwin', 'linux'];
  if (!supported.includes(info.platform)) {
    return {
      id: 'env.platform',
      title: 'Operating system',
      status: 'error',
      message: `Unsupported platform: ${info.platform}`,
      fixable: false,
    };
  }
  return {
    id: 'env',
    title: 'Environment',
    status: 'ok',
    message: `Node ${info.nodeVersion}, npm ${npmVersion}, ${info.platform}/${info.arch}`,
    data: info,
  };
}
