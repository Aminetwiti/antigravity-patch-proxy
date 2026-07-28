import { describe, expect, it } from 'vitest';

/**
 * Unit tests for CheckResult status mapping and Objective state calculation.
 */

type CheckStatus = 'ok' | 'warn' | 'error' | 'info';

interface CheckResult {
  id: string;
  name: string;
  status: CheckStatus;
  message: string;
}

type ObjectiveStatus = 'ok' | 'warn' | 'error' | 'pending';

function resultStatusToObjective(status: CheckStatus): ObjectiveStatus {
  return status === 'info' ? 'ok' : status;
}

interface ObjectiveState {
  antigravity: ObjectiveStatus;
  mitm: ObjectiveStatus;
  doctor: ObjectiveStatus;
  patch: ObjectiveStatus;
  logs: ObjectiveStatus;
}

function computeObjectives(results: CheckResult[]): ObjectiveState {
  const hasError = results.some((r) => r.status === 'error');
  const hasWarn = results.some((r) => r.status === 'warn');
  const doctorStatus: ObjectiveStatus = hasError ? 'error' : hasWarn ? 'warn' : 'ok';

  const antigravity = results.find((r) => r.id === 'antigravity' || r.id === 'version' || r.id === 'install');
  const mitm = results.find((r) => r.id === 'mitm' || r.id === 'proxy' || r.id === 'ca');
  const patch = results.find((r) => r.id === 'patch');
  const logs = results.find((r) => r.id === 'logs');

  return {
    antigravity: antigravity ? resultStatusToObjective(antigravity.status) : 'pending',
    mitm: mitm ? resultStatusToObjective(mitm.status) : 'pending',
    doctor: doctorStatus,
    patch: patch ? resultStatusToObjective(patch.status) : 'pending',
    logs: logs ? resultStatusToObjective(logs.status) : 'ok',
  };
}

describe('resultStatusToObjective mapping', () => {
  it('maps info status to ok for objectives', () => {
    expect(resultStatusToObjective('info')).toBe('ok');
  });

  it('preserves ok, warn, error statuses', () => {
    expect(resultStatusToObjective('ok')).toBe('ok');
    expect(resultStatusToObjective('warn')).toBe('warn');
    expect(resultStatusToObjective('error')).toBe('error');
  });
});

describe('computeObjectives system summary', () => {
  it('computes all objectives as ok when diagnostic results are healthy', () => {
    const results: CheckResult[] = [
      { id: 'version', name: 'Antigravity Version', status: 'ok', message: 'v2.2.0 installed' },
      { id: 'proxy', name: 'MITM Proxy', status: 'ok', message: 'Port 443 listening' },
      { id: 'patch', name: 'Binary Patch', status: 'ok', message: 'Patched' },
    ];
    const objs = computeObjectives(results);
    expect(objs.antigravity).toBe('ok');
    expect(objs.mitm).toBe('ok');
    expect(objs.doctor).toBe('ok');
    expect(objs.patch).toBe('ok');
    expect(objs.logs).toBe('ok');
  });

  it('flags doctor objective as error when any check has error status', () => {
    const results: CheckResult[] = [
      { id: 'version', name: 'Antigravity Version', status: 'ok', message: 'v2.2.0' },
      { id: 'proxy', name: 'MITM Proxy', status: 'error', message: 'Port 443 refused' },
    ];
    const objs = computeObjectives(results);
    expect(objs.doctor).toBe('error');
    expect(objs.mitm).toBe('error');
    expect(objs.antigravity).toBe('ok');
  });

  it('flags doctor objective as warn when check has warn status and 0 errors', () => {
    const results: CheckResult[] = [
      { id: 'ca', name: 'CA Cert', status: 'warn', message: 'CA cert not in trust store' },
    ];
    const objs = computeObjectives(results);
    expect(objs.doctor).toBe('warn');
    expect(objs.mitm).toBe('warn');
  });

  it('keeps objectives pending when check results for that subsystem are missing', () => {
    const results: CheckResult[] = [];
    const objs = computeObjectives(results);
    expect(objs.antigravity).toBe('pending');
    expect(objs.mitm).toBe('pending');
    expect(objs.patch).toBe('pending');
    expect(objs.logs).toBe('ok');
  });
});
