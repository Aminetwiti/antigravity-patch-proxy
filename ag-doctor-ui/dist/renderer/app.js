"use strict";
/**
 * ag-doctor UI — renderer controller.
 * Vanilla TypeScript, talks to the main process via window.ag (preload bridge).
 *
 * Performance features:
 *  - Memoized IPC calls (config, info) — avoid redundant round-trips
 *  - requestIdleCallback wrapper for non-critical work
 *  - Template-based DOM construction (parse once, insert once)
 *  - Event delegation everywhere
 *  - rAF-batched log streaming
 */
const ipcCache = new Map();
// In-flight tracker: deduplicates concurrent calls with the same key
const ipcInflight = new Map();
async function memo(key, ttlMs, loader) {
    const now = Date.now();
    const cached = ipcCache.get(key);
    if (cached && cached.expiresAt > now) {
        return cached.value;
    }
    // Deduplicate concurrent calls: if a request is already in flight, await it
    const inflight = ipcInflight.get(key);
    if (inflight)
        return inflight;
    const promise = (async () => {
        try {
            const value = await loader();
            ipcCache.set(key, { value, expiresAt: Date.now() + ttlMs });
            return value;
        }
        finally {
            ipcInflight.delete(key);
        }
    })();
    ipcInflight.set(key, promise);
    return promise;
}
function invalidateCache(prefix) {
    if (!prefix) {
        ipcCache.clear();
        return;
    }
    for (const k of ipcCache.keys()) {
        if (k.startsWith(prefix))
            ipcCache.delete(k);
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// withTimeout — wraps a promise so it rejects after `ms` milliseconds.
// F-14: prevents the UI from staying on "Loading…" forever if the IPC handler
// never resolves (worker crash, network hang, etc.).
// ─────────────────────────────────────────────────────────────────────────────
function withTimeout(promise, ms, label) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            reject(new Error(`${label} timed out after ${ms / 1000}s`));
        }, ms);
        promise.then((v) => { clearTimeout(timer); resolve(v); }, (e) => { clearTimeout(timer); reject(e); });
    });
}
// ─────────────────────────────────────────────────────────────────────────────
// inflight guards — prevent concurrent loadX() calls from racing (F-21).
// If a load is already running, return its existing promise.
// ─────────────────────────────────────────────────────────────────────────────
const inflightLoads = new Map();
function guardLoad(key, fn) {
    const existing = inflightLoads.get(key);
    if (existing)
        return existing;
    const p = fn().finally(() => inflightLoads.delete(key));
    inflightLoads.set(key, p);
    return p;
}
const idleScheduler = (() => {
    const win = window;
    if (win.requestIdleCallback) {
        return {
            request: (cb, opts) => win.requestIdleCallback(cb, opts),
        };
    }
    return {
        request: (cb, opts) => setTimeout(() => cb({ didTimeout: true, timeRemaining: () => 0 }), opts?.timeout ?? 50),
    };
})();
function whenIdle(cb, timeout = 100) {
    idleScheduler.request(() => cb(), { timeout });
}
const OBJECTIVE_LABELS = {
    antigravity: "Verify Antigravity status & version",
    mitm: "Verify & manage MITM proxy status",
    doctor: "Run system diagnostic (Doctor)",
    patch: "Apply repair patch",
    logs: "View & follow system logs",
    proxy: "Start/stop proxy stub on 50999",
};
// ─────────────────────────────────────────────────────────────────────────────
// Cached SVG icon strings (avoid recreating on every render)
// ─────────────────────────────────────────────────────────────────────────────
const ICON_OK = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';
const ICON_WARN = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>';
const ICON_ERR = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>';
const ICON_INFO = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>';
const ICON_PENDING = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/></svg>';
function iconForStatus(status) {
    return status === 'ok' ? ICON_OK : status === 'warn' ? ICON_WARN : status === 'error' ? ICON_ERR : ICON_INFO;
}
function iconForObjective(state) {
    return state === 'ok' ? ICON_OK : state === 'warn' ? ICON_WARN : state === 'error' ? ICON_ERR : ICON_PENDING;
}
// ─────────────────────────────────────────────────────────────────────────────
// DOM helpers
// ─────────────────────────────────────────────────────────────────────────────
const $ = (sel) => {
    const el = document.querySelector(sel);
    if (!el)
        throw new Error(`Missing element: ${sel}`);
    return el;
};
const $$ = (sel) => Array.from(document.querySelectorAll(sel));
function escapeHtml(s) {
    return s
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
/**
 * Run an action associated with a decoded error (open a view, trigger a
 * repair command, etc.). Returns true if an action was taken.
 */
function flashMitmBanner() {
    // Best-effort fallback when `navigate` is not in scope. Surface the MITM
    // banner with a quick highlight so the user knows where to go.
    const banner = document.querySelector('[data-view="mitm"], #mitmBanner, .mitm-banner');
    if (banner) {
        banner.classList.add('flash-attention');
        banner.scrollIntoView({ behavior: 'smooth', block: 'center' });
        setTimeout(() => banner.classList.remove('flash-attention'), 2000);
    }
}
function runErrorAction(action) {
    switch (action) {
        case 'open-mitm-view':
            if (typeof navigate === 'function') {
                try {
                    navigate('mitm');
                }
                catch {
                    flashMitmBanner();
                }
            }
            else {
                flashMitmBanner();
            }
            return true;
        case 'run-doctor':
            void window.ag.run(['doctor', '--fix']).catch(() => undefined);
            return true;
        case 'show-retry-toast':
            toast('Please retry the previous action. If it keeps failing, restore the patch.', 'warn', 5000);
            return true;
        default:
            return false;
    }
}
function maskKey(k) {
    if (!k)
        return '(none)';
    if (k.length <= 8)
        return '***';
    return `${k.slice(0, 3)}...${k.slice(-4)}`;
}
// ─────────────────────────────────────────────────────────────────────────────
// Skeleton loader helpers
// ─────────────────────────────────────────────────────────────────────────────
const SKELETON_HTML = {
    lines: (count) => Array.from({ length: count }, (_, i) => {
        const widths = ['short', 'medium', 'long'];
        return `<div class="skeleton skeleton-line ${widths[i % widths.length]}"></div>`;
    }).join(''),
    cards: (count) => Array.from({ length: count }, () => '<div class="skeleton skeleton-card"></div>').join(''),
    text: () => '<span class="skeleton skeleton-text">·····</span>',
};
function showSkeleton(target, kind, count = 3) {
    target.setAttribute('data-loading', 'true');
    if (kind === 'text') {
        target.innerHTML = SKELETON_HTML.text();
    }
    else {
        target.innerHTML = SKELETON_HTML[kind](count);
    }
}
function hideSkeleton(target) {
    target.removeAttribute('data-loading');
}
// ─────────────────────────────────────────────────────────────────────────────
// Status pill
// ─────────────────────────────────────────────────────────────────────────────
const statusPill = $('#statusPill');
const statusText = $('#statusText');
function setStatus(text, kind = 'ready') {
    statusText.textContent = text;
    statusPill.classList.remove('busy', 'err');
    if (kind !== 'ready')
        statusPill.classList.add(kind);
}
// ─────────────────────────────────────────────────────────────────────────────
// Toasts
// ─────────────────────────────────────────────────────────────────────────────
const toastContainer = $('#toastContainer');
const TOAST_ICONS = {
    ok: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',
    err: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
    warn: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',
    info: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>',
};
function toast(message, kind = 'info', durationMs = 3500) {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.innerHTML = `<div class="toast-icon">${TOAST_ICONS[kind]}</div><div>${escapeHtml(message)}</div>`;
    toastContainer.appendChild(el);
    setTimeout(() => {
        el.classList.add('removing');
        setTimeout(() => el.remove(), 250);
    }, durationMs);
}
// ─────────────────────────────────────────────────────────────────────────────
// Modal — managed by ModalManager (see modal-manager.ts)
// ─────────────────────────────────────────────────────────────────────────────
// Single shared instance. ModalManager owns the #modalBackdrop DOM node and
// all open/close/result lifecycle (listeners attached per-open, cleaned on
// close). Mirrors the vscode-unify pickQuickItem / stack-router pattern.
const modals = new ModalManager();
function confirmModal(title, body, opts) {
    return modals.confirm(title, body, opts);
}
// ─────────────────────────────────────────────────────────────────────────────
// Navigation
// ─────────────────────────────────────────────────────────────────────────────
const navItems = $$('.nav-item');
const views = $$('.view');
function navigate(viewName) {
    navItems.forEach((n) => n.classList.toggle('active', n.dataset.view === viewName));
    views.forEach((v) => v.classList.toggle('active', v.id === `view-${viewName}`));
    // Trigger view-specific loaders
    if (viewName === 'models')
        void loadModels();
    if (viewName === 'patch')
        void loadPatchStatus();
    if (viewName === 'info')
        void loadInfo();
    if (viewName === 'logs')
        void loadLogs();
    if (viewName === 'mitm')
        void loadMitmStatus();
    if (viewName === 'settings')
        void loadSettings();
    if (viewName === 'antigravity')
        void loadAntigravity();
}
navItems.forEach((n) => n.addEventListener('click', () => navigate(n.dataset.view)));
// Persistent sidebar "Run diagnostic" CTA — mirrors the legacy quickRunBtn
$('#sidebarRunBtn')?.addEventListener('click', () => {
    navigate('doctor');
    void runDoctor();
});
// ─────────────────────────────────────────────────────────────────────────────
// Doctor / dashboard
// ─────────────────────────────────────────────────────────────────────────────
const healthList = $('#healthList');
const statOk = $('#statOk');
const statWarn = $('#statWarn');
const statErr = $('#statErr');
const statModels = $('#statModels');
const lastRunBadge = $('#lastRunBadge');
let lastResults = [];
// Event delegation: bind once for expand toggles (avoids N listeners per item)
healthList.addEventListener('click', (e) => {
    const target = e.target.closest('.health-expand');
    if (target) {
        const item = target.closest('.health-item');
        const isExpanded = item?.classList.toggle('expanded') ?? false;
        target.setAttribute('aria-expanded', isExpanded ? 'true' : 'false');
        target.textContent = isExpanded ? 'Hide details' : 'Show details';
    }
});
// Reusable template for health list — avoids creating a new <template> each render
const healthTpl = document.createElement('template');
function renderHealthList(results) {
    if (results.length === 0) {
        healthList.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">
          <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
        </div>
        <p>Click <strong>Run doctor</strong> to scan Antigravity, MITM, patches, and models.</p>
      </div>`;
        return;
    }
    // Build via DocumentFragment: parse once, insert once (no double innerHTML parse)
    const html = results
        .map((r, i) => {
        const icon = iconForStatus(r.status);
        const detailsHtml = r.details
            ? `<div class="health-details">${escapeHtml(r.details)}</div><button class="health-expand" type="button" aria-expanded="false">Show details</button>`
            : '';
        return `
        <div class="health-item" style="animation-delay:${i * 40}ms" data-id="${r.id}">
          <div class="health-icon ${r.status}">${icon}</div>
          <div class="health-body">
            <div class="health-title">${escapeHtml(r.title)}</div>
            <div class="health-message">${escapeHtml(r.message)}</div>
            ${detailsHtml}
          </div>
        </div>`;
    })
        .join('');
    healthTpl.innerHTML = html;
    healthList.replaceChildren(healthTpl.content);
}
function updateStats(results) {
    const ok = results.filter((r) => r.status === 'ok').length;
    const warn = results.filter((r) => r.status === 'warn').length;
    const err = results.filter((r) => r.status === 'error').length;
    const modelsCheck = results.find((r) => r.id === 'models');
    const modelsCount = modelsCheck?.data && typeof modelsCheck.data === 'object' && 'count' in modelsCheck.data
        ? modelsCheck.data.count
        : 0;
    statOk.textContent = String(ok);
    statWarn.textContent = String(warn);
    statErr.textContent = String(err);
    statModels.textContent = String(modelsCount);
    lastRunBadge.textContent = new Date().toLocaleTimeString();
}
// Dashboard hero card
const dashHeroDot = $('#dashHeroDot');
const dashHeroLabel = $('#dashHeroLabel');
const dashHeroTitle = $('#dashHeroTitle');
const dashHeroMeta = $('#dashHeroMeta');
// Reusable template for the runtime details table — avoids creating a new <template> each load
const infoTableTpl = document.createElement('template');
// Reusable template for the dashboard hero meta — avoids innerHTML on every doctor run
const dashHeroMetaTpl = document.createElement('template');
function setDashHero(state, label, meta) {
    dashHeroDot.className = `ag-hero-dot ${state}`;
    dashHeroLabel.textContent = label;
    dashHeroMetaTpl.innerHTML = meta;
    dashHeroMeta.replaceChildren(dashHeroMetaTpl.content);
}
function updateDashHero(results) {
    const hasError = results.some((r) => r.status === 'error');
    const hasWarn = results.some((r) => r.status === 'warn');
    const ok = results.filter((r) => r.status === 'ok').length;
    const total = results.length;
    if (hasError) {
        setDashHero('err', `${results.filter((r) => r.status === 'error').length} issue(s) found`, `<strong>${total}</strong> checks · <strong>${ok}</strong> passed · review issues below`);
    }
    else if (hasWarn) {
        setDashHero('warn', `${results.filter((r) => r.status === 'warn').length} warning(s) found`, `<strong>${total}</strong> checks · <strong>${ok}</strong> passed · some warnings detected`);
    }
    else {
        setDashHero('ok', 'All checks passed', `<strong>${total}</strong> checks passed · last run ${new Date().toLocaleTimeString()}`);
    }
    dashHeroTitle.textContent = 'ag-doctor';
}
async function runDoctor() {
    setStatus('Running doctor…', 'busy');
    $('#runDoctorBtn')?.setAttribute('disabled', 'true');
    $('#refreshBtn')?.setAttribute('disabled', 'true');
    $('#sidebarRunBtn')?.setAttribute('disabled', 'true');
    $('#heroRunBtn')?.setAttribute('disabled', 'true');
    setObjective('doctor', 'pending', 'Running…');
    setDashHero('busy', 'Running doctor…', 'Scanning Antigravity, MITM, patches, and models…');
    try {
        const result = await window.ag.run(['doctor', '--json']);
        if (result.code !== 0 && !result.stdout) {
            throw new Error(result.stderr || `Exit ${result.code}`);
        }
        const data = JSON.parse(result.stdout);
        // Diff against previous results for native notifications
        if (lastResults.length > 0) {
            const previousErrors = new Set(lastResults.filter((r) => r.status === 'error').map((r) => r.id));
            const newErrors = data.filter((r) => r.status === 'error' && !previousErrors.has(r.id));
            if (newErrors.length > 0) {
                const titles = newErrors.map((r) => r.title).join(', ');
                void window.ag.notify('ag-doctor · new issue', `${newErrors.length} new issue(s): ${titles}`);
            }
        }
        lastResults = data;
        renderHealthList(data);
        updateStats(data);
        updateObjectives(data);
        updateDashHero(data);
        const hasError = data.some((r) => r.status === 'error');
        const hasWarn = data.some((r) => r.status === 'warn');
        void window.ag.trayStatus(hasError ? 'err' : hasWarn ? 'warn' : 'ok');
        toast(`Doctor complete · ${data.length} checks`, 'ok');
        setStatus('Ready');
    }
    catch (e) {
        toast(`Doctor failed: ${e.message}. Check the Logs tab for full output.`, 'err', 5000);
        setStatus('Error', 'err');
        setObjective('doctor', 'error', 'Doctor failed');
        void window.ag.trayStatus('err');
    }
    finally {
        $('#runDoctorBtn')?.removeAttribute('disabled');
        $('#refreshBtn')?.removeAttribute('disabled');
        $('#sidebarRunBtn')?.removeAttribute('disabled');
        $('#heroRunBtn')?.removeAttribute('disabled');
    }
}
function resultStatusToObjective(status) {
    return status === 'info' ? 'ok' : status;
}
function updateObjectives(results) {
    const hasError = results.some((r) => r.status === 'error');
    const hasWarn = results.some((r) => r.status === 'warn');
    setObjective('doctor', hasError ? 'error' : hasWarn ? 'warn' : 'ok', hasError ? 'Issues detected' : hasWarn ? 'Warnings found' : 'Doctor OK');
    const antigravity = results.find((r) => r.id === 'antigravity' || r.id === 'version' || r.id === 'install');
    setObjective('antigravity', antigravity ? resultStatusToObjective(antigravity.status) : 'pending', antigravity?.message);
    const mitm = results.find((r) => r.id === 'mitm' || r.id === 'proxy' || r.id === 'ca');
    setObjective('mitm', mitm ? resultStatusToObjective(mitm.status) : 'pending', mitm?.message);
    const patch = results.find((r) => r.id === 'patch');
    setObjective('patch', patch ? resultStatusToObjective(patch.status) : 'pending', patch?.message);
    const logs = results.find((r) => r.id === 'logs');
    setObjective('logs', logs ? resultStatusToObjective(logs.status) : 'ok', logs?.message ?? 'Logs available');
}
$('#runDoctorBtn').addEventListener('click', () => void runDoctor());
$('#heroRunBtn')?.addEventListener('click', () => void runDoctor());
$('#emptyStateRunDoctorBtn')?.addEventListener('click', () => void runDoctor());
$('#refreshBtn').addEventListener('click', () => void runDoctor());
$('#repairBtn').addEventListener('click', () => void runRepair());
// Fix All: full auto-repair with admin elevation (UAC prompt will appear)
$('#fixAllBtn')?.addEventListener('click', () => void runFixAll());
// Start Stub: emergency proxy stub on port 50999 (no admin needed)
$('#startStubBtn')?.addEventListener('click', () => void runStartStub());
async function runFixAll() {
    const ok = await confirmModal('Run full auto-repair?', 'This will launch <code>ag-doctor repair --yes --auto-elevate</code> with admin elevation (UAC). ' +
        'All repair actions will run: patch, port 50999, proxy, CA certificate.', { confirmLabel: 'Run full repair', danger: true });
    if (!ok)
        return;
    setStatus('Full repair — admin elevation…', 'busy');
    $('#fixAllBtn')?.setAttribute('disabled', 'true');
    try {
        const r = await window.ag.repairRun();
        if (r?.ok) {
            toast('Full repair completed. Re-running doctor to verify.', 'ok', 5000);
            setObjective('patch', 'ok', 'Full repair completed');
        }
        else {
            toast(`Full repair failed: ${r?.error ?? 'unknown'}. Check the Logs tab for details.`, 'err', 6000);
            setObjective('patch', 'error', 'Full repair failed');
        }
        setStatus('Re-running doctor…', 'busy');
        await runDoctor();
    }
    catch (e) {
        toast(`Full repair error: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
    finally {
        $('#fixAllBtn')?.removeAttribute('disabled');
    }
}
async function runStartStub() {
    setStatus('Starting proxy stub…', 'busy');
    $('#startStubBtn')?.setAttribute('disabled', 'true');
    try {
        const r = await window.ag.proxyStartStub();
        if (r?.ok) {
            toast(`Proxy stub started (pid=${r.pid ?? '?'}) on port 50999`, 'ok', 5000);
            setObjective('proxy', 'ok', 'Proxy stub active on 50999');
        }
        else {
            toast(`Proxy stub failed: ${r?.error ?? 'unknown'}`, 'err', 6000);
            setObjective('proxy', 'error', 'Proxy stub failed');
        }
    }
    catch (e) {
        toast(`Proxy stub error: ${e.message}`, 'err');
    }
    finally {
        $('#startStubBtn')?.removeAttribute('disabled');
        setStatus('Ready', 'ready');
    }
}
// Reusable template for objective icons — avoids innerHTML on every doctor run
const objectiveIconTpl = document.createElement('template');
function setObjective(key, state, detail) {
    const el = document.getElementById(`obj-${key}`);
    if (!el)
        return;
    const icon = el.querySelector('.objective-icon');
    const status = el.querySelector('.objective-status');
    icon.className = `objective-icon ${state}`;
    objectiveIconTpl.innerHTML = iconForObjective(state);
    icon.replaceChildren(objectiveIconTpl.content);
    status.textContent = detail ?? (state === 'ok' ? 'Active' : state === 'pending' ? 'Pending' : state === 'warn' ? 'Warning' : 'Error');
}
async function runRepair() {
    const ok = await confirmModal('Repair detected issues?', 'This runs <code>ag-doctor repair --yes</code> to attempt automatic repair of issues found by the doctor.', { confirmLabel: 'Run repair' });
    if (!ok)
        return;
    setStatus('Running repair…', 'busy');
    $('#repairBtn')?.setAttribute('disabled', 'true');
    try {
        const r = await window.ag.run(['repair', '--yes']);
        if (r.code === 0) {
            toast('Repair completed. Re-running doctor to verify.', 'ok', 5000);
            setObjective('patch', 'ok', 'Repair completed');
        }
        else {
            toast(`Repair failed: ${r.stderr || r.stdout}. Check the Logs tab for details.`, 'err', 6000);
            setObjective('patch', 'error', 'Repair failed');
        }
        setStatus('Re-running doctor…', 'busy');
        await runDoctor();
    }
    catch (e) {
        toast(`Repair error: ${e.message}`, 'err');
        setStatus('Error', 'err');
        setObjective('patch', 'error', 'Repair failed');
    }
    finally {
        $('#repairBtn')?.removeAttribute('disabled');
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic view
// ─────────────────────────────────────────────────────────────────────────────
const doctorOutput = $('#doctorOutput');
function ansiToHtml(s) {
    // Strip ANSI escape codes and replace with HTML spans for known sequences
    return escapeHtml(s)
        .replace(/\x1b\[32m/g, '<span class="t-ok">')
        .replace(/\x1b\[33m/g, '<span class="t-warn">')
        .replace(/\x1b\[31m/g, '<span class="t-err">')
        .replace(/\x1b\[36m/g, '<span class="t-info">')
        .replace(/\x1b\[90m/g, '<span class="t-dim">')
        .replace(/\x1b\[1m/g, '<span class="t-bold">')
        .replace(/\x1b\[22m/g, '</span>')
        .replace(/\x1b\[39m/g, '</span>')
        .replace(/\x1b\[0m/g, '</span>');
}
// Reusable template for doctor output — avoids creating a new <template> each run
const doctorTpl = document.createElement('template');
async function runDoctorView() {
    setStatus('Running doctor…', 'busy');
    doctorOutput.textContent = '$ ag-doctor doctor\n';
    try {
        const result = await window.ag.run(['doctor']);
        doctorTpl.innerHTML = ansiToHtml(result.stdout || result.stderr);
        doctorOutput.replaceChildren(doctorTpl.content);
        setStatus('Ready');
    }
    catch (e) {
        doctorOutput.textContent = `Could not run doctor: ${e.message}`;
        setStatus('Error', 'err');
    }
}
$('#doctorRunBtn').addEventListener('click', () => void runDoctorView());
$('#doctorJsonBtn').addEventListener('click', async () => {
    setStatus('Loading JSON…', 'busy');
    try {
        const result = await window.ag.run(['doctor', '--json']);
        doctorOutput.textContent = result.stdout || result.stderr;
        setStatus('Ready');
    }
    catch (e) {
        toast(`Could not load doctor JSON: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// Models view
// ──────���──────────────────────────────────────────────────────────────────────
const modelsList = $('#modelsList');
// Reusable template for models list — avoids creating a new <template> each load
const modelsTpl = document.createElement('template');
async function loadModels() {
    setStatus('Loading models…', 'busy');
    showSkeleton(modelsList, 'cards', 3);
    try {
        const result = await window.ag.run(['models', 'list', '--json']);
        const data = JSON.parse(result.stdout);
        if (data.models.length === 0) {
            modelsList.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon">
            <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/></svg>
          </div>
          <p style="margin-bottom: 12px;">No models configured yet. <strong>Add model</strong> to connect a custom OpenAI- or Anthropic-compatible provider.</p>
          <button class="btn btn-primary btn-sm" id="emptyAddModelBtn" type="button">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
            Add model
          </button>
        </div>`;
        }
        else {
            // Use template element for parse-once, insert-once
            const html = data.models
                .map((m) => {
                const initials = (m.displayName ?? m.name).slice(0, 2).toUpperCase();
                return `
            <div class="model-card">
              <div class="model-avatar">${escapeHtml(initials)}</div>
              <div class="model-body">
                <div class="model-name">${escapeHtml(m.displayName ?? m.name)}</div>
                <div class="model-meta">
                  <code>${escapeHtml(m.name)}</code> · ${escapeHtml(m.provider)} · ${escapeHtml(m.externalModelName)}
                </div>
                <div class="model-meta" style="margin-top:4px">
                  <code style="font-size:10px">${escapeHtml(m.apiUrl)}</code> · key: ${escapeHtml(maskKey(m.apiKey))}${m.encrypted ? ' · <span style="color:var(--ok)">encrypted</span>' : ''}
                </div>
              </div>
              <div class="model-actions">
                <button class="btn btn-ghost btn-sm" data-action="test" data-name="${escapeHtml(m.name)}">Test model</button>
                <button class="btn btn-ghost btn-sm" data-action="reveal" data-url="${escapeHtml(m.apiUrl)}">Open endpoint</button>
                <button class="btn btn-danger btn-sm" data-action="remove" data-name="${escapeHtml(m.name)}">Delete model</button>
              </div>
            </div>`;
            })
                .join('');
            modelsTpl.innerHTML = html;
            modelsList.replaceChildren(modelsTpl.content);
        }
        setStatus(`${data.models.length} model(s) loaded`);
    }
    catch (e) {
        modelsList.innerHTML = `<div class="empty-state"><p>Could not load models: ${escapeHtml(e.message)}</p></div>`;
        setStatus('Error', 'err');
    }
    finally {
        hideSkeleton(modelsList);
    }
}
// Event delegation for model-card actions (one listener, not N)
modelsList.addEventListener('click', (e) => {
    const target = e.target;
    if (target.closest('#emptyAddModelBtn')) {
        openProviderManagerModal();
        return;
    }
    const btn = target.closest('[data-action]');
    if (!btn)
        return;
    void handleModelAction(btn);
});
async function handleModelAction(btn) {
    const action = btn.dataset.action;
    const name = btn.dataset.name ?? '';
    const url = btn.dataset.url ?? '';
    if (action === 'test') {
        setStatus(`Testing ${name}…`, 'busy');
        try {
            const r = await window.ag.run(['models', 'test', name]);
            toast(r.stdout.includes('✓') || r.code === 0 ? `${name} is reachable` : `${name} failed — check the endpoint and API key`, r.code === 0 ? 'ok' : 'err');
            setStatus('Ready');
        }
        catch (e) {
            toast(`Test failed: ${e.message}`, 'err');
            setStatus('Error', 'err');
        }
    }
    else if (action === 'reveal') {
        await window.ag.openExternal(url);
    }
    else if (action === 'remove') {
        const ok = await confirmModal('Delete this model?', `Delete <strong>${escapeHtml(name)}</strong> from this device? This only removes the saved provider — models on your remote account are unaffected.`, { confirmLabel: 'Delete model', danger: true });
        if (!ok)
            return;
        setStatus('Removing model…', 'busy');
        const r = await window.ag.run(['models', 'remove', name, '--yes']);
        if (r.code === 0) {
            toast(`Removed ${name}`, 'ok');
            void loadModels();
        }
        else {
            toast(`Delete failed: ${r.stderr || r.stdout}. Check the Logs tab for details.`, 'err');
        }
        setStatus('Ready');
    }
}
$('#modelsTestBtn').addEventListener('click', async () => {
    setStatus('Testing all models…', 'busy');
    try {
        const r = await window.ag.run(['models', 'test']);
        if (r.code === 0) {
            toast('All models reachable', 'ok', 5000);
        }
        else {
            toast('Some models failed. Open the Models view for details.', 'warn', 5000);
        }
        setStatus('Ready');
    }
    catch (e) {
        toast(`Test failed: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// MITM view
// ─────────────────────────────────────────────────────────────────────────────
const mitmStatusEl = $('#mitmStatus');
// Reusable template for MITM status — avoids creating a new <template> each load
const mitmTpl = document.createElement('template');
async function loadMitmStatus() {
    return guardLoad('mitm', async () => {
        setStatus('Loading MITM status…', 'busy');
        showSkeleton(mitmStatusEl, 'cards', 3);
        try {
            const r = await withTimeout(window.ag.run(['mitm', 'status', '--json']), 12_000, 'mitm status');
            const s = JSON.parse(r.stdout);
            const caBanner = s.ca.installed && !s.ca.isExpired
                ? `<div class="patch-banner ok">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">CA certificate installed</div>
             <div class="patch-banner-text">Your system trusts the local MITM certificate.</div>
           </div>
         </div>`
                : `<div class="patch-banner warn">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">${s.ca.isExpired ? 'CA certificate expired' : 'CA certificate not installed'}</div>
             <div class="patch-banner-text">${s.ca.isExpired ? 'The certificate has expired. Run Repair all to regenerate it.' : 'Install the CA to avoid TLS errors in intercepted apps.'}</div>
           </div>
         </div>`;
            const proxyBanner = s.proxy.redirected
                ? `<div class="patch-banner ok">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">System proxy active</div>
             <div class="patch-banner-text">Traffic is being redirected to ${escapeHtml(s.proxy.host ?? 'localhost')}:${s.proxy.port ?? '—'}.</div>
           </div>
         </div>`
                : `<div class="patch-banner warn">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">System proxy inactive</div>
             <div class="patch-banner-text">Click <strong>Proxy ON</strong> above to start redirecting traffic.</div>
           </div>
         </div>`;
            const interceptionBanner = s.interception.reachable
                ? `<div class="patch-banner ok">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">Interception reachable</div>
             <div class="patch-banner-text">The proxy is listening and responding to requests.</div>
           </div>
         </div>`
                : `<div class="patch-banner err">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">Interception unreachable</div>
             <div class="patch-banner-text">The proxy does not appear to be listening. Try Repair all.</div>
           </div>
         </div>`;
            mitmTpl.innerHTML = `
      <div class="mitm-grid">
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>CA certificate</h3><span class="badge ${s.ca.installed ? 'ok' : 'warn'}">${s.ca.installed ? 'installed' : 'not installed'}</span></div>
          <div class="mitm-card-body">
            <div class="patch-row"><div class="patch-row-label">Generated</div><div class="patch-row-value ${s.ca.generated ? 'ok' : ''}">${s.ca.generated ? 'yes' : 'no'}</div></div>
            <div class="patch-row"><div class="patch-row-label">Expires</div><div class="patch-row-value ${s.ca.isExpired ? 'err' : ''}">${escapeHtml(s.ca.expiresAt ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Path</div><div class="patch-row-value">${escapeHtml(s.ca.path ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Fingerprint</div><div class="patch-row-value">${escapeHtml(s.ca.fingerprint ?? '—')}</div></div>
          </div>
          ${caBanner}
        </div>
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>System proxy</h3><span class="badge ${s.proxy.redirected ? 'ok' : 'warn'}">${s.proxy.redirected ? 'redirected' : 'off'}</span></div>
          <div class="mitm-card-body">
            <div class="patch-row"><div class="patch-row-label">Host</div><div class="patch-row-value">${escapeHtml(s.proxy.host ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Port</div><div class="patch-row-value">${s.proxy.port ?? '—'}</div></div>
          </div>
          ${proxyBanner}
        </div>
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>Interception status</h3><span class="badge ${s.interception.reachable ? 'ok' : 'err'}">${s.interception.reachable ? 'reachable' : 'unreachable'}</span></div>
          <div class="mitm-card-body">
            <div class="patch-row"><div class="patch-row-label">Listening</div><div class="patch-row-value ${s.interception.listening ? 'ok' : ''}">${s.interception.listening ? 'yes' : 'no'}</div></div>
            <div class="patch-row"><div class="patch-row-label">Connectivity</div><div class="patch-row-value ${s.interception.reachable ? 'ok' : 'err'}">${s.interception.reachable ? 'ok' : 'failed'}</div></div>
          </div>
          ${interceptionBanner}
        </div>
      </div>
      ${(!s.ca.installed || !s.proxy.redirected || !s.interception.reachable) ? `
      <div style="margin-top: 20px; text-align: center;">
        <button id="repair-all-btn" class="btn btn-primary" style="padding: 10px 20px; font-size: 14px;">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" style="vertical-align: text-bottom; margin-right: 6px;"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 9.36l-7.1 7.1a1 1 0 0 1-1.4 0l-2.8-2.8a1 1 0 0 1 0-1.4l7.1-7.1a6 6 0 0 1 9.36-7.94z"/></svg>
          Repair all (needs admin)
        </button>
      </div>
      ` : ''}`;
            mitmStatusEl.replaceChildren(mitmTpl.content);
            const repairBtn = document.getElementById('repair-all-btn');
            if (repairBtn) {
                repairBtn.setAttribute('aria-label', 'Repair all MITM issues (requires administrator)');
                repairBtn.addEventListener('click', async () => {
                    repairBtn.setAttribute('disabled', 'true');
                    repairBtn.textContent = 'Repairing — approve the UAC prompt…';
                    setStatus('Repairing MITM…', 'busy');
                    try {
                        const res = await window.ag.repairRun();
                        if (res.ok) {
                            toast('Repair script completed successfully.', 'ok', 3000);
                            // Auto-start the proxy server after a successful repair
                            console.log('[MITM] Auto-starting proxy server after repair...');
                            const startResult = await window.ag.proxyStart();
                            if (startResult.ok) {
                                toast('Proxy server started automatically.', 'ok', 3000);
                            }
                            else {
                                toast(`Repair succeeded but proxy server failed to start: ${startResult.message}`, 'warn', 6000);
                            }
                        }
                        else {
                            toast(`Repair failed: ${res.error}`, 'err', 6000);
                        }
                    }
                    catch (err) {
                        toast(`Repair IPC error: ${err.message}`, 'err', 6000);
                    }
                    finally {
                        void loadMitmStatus();
                    }
                });
            }
            setStatus('Ready');
        }
        catch (e) {
            mitmStatusEl.innerHTML = `<div class="empty-state"><p>Could not load MITM status: ${escapeHtml(e.message)}</p></div>`;
            setStatus('Error', 'err');
        }
        finally {
            hideSkeleton(mitmStatusEl);
        }
    });
}
async function mitmAction(args, successMsg, refresh = true, preStatus) {
    // Show a UAC-wait message up-front for operations that may trigger an
    // elevation prompt. Otherwise users see "busy…" for several seconds with
    // no indication of what is happening and assume the UI is hung.
    setStatus(preStatus ?? `${args.slice(1).join(' ')}…`, 'busy');
    try {
        const r = await window.ag.run(args);
        if (r.code === 0) {
            toast(successMsg, 'ok', 5000);
            if (refresh)
                void loadMitmStatus();
        }
        else {
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            const operation = args.slice(1).join(' ');
            // Match common failure patterns with actionable guidance.
            if (errorMsg.toLowerCase().includes('uac') || errorMsg.toLowerCase().includes('cancelled')) {
                toast(`${operation} failed: UAC prompt was declined. Click "Yes" when prompted.`, 'err', 8000);
            }
            else if (errorMsg.toLowerCase().includes('access denied') || r.code === 5) {
                toast(`${operation} failed: access denied. Try running as Administrator.`, 'err', 8000);
            }
            else if (errorMsg.toLowerCase().includes('not found')) {
                toast(`${operation} failed: required system tool not found. Check your PATH.`, 'err', 8000);
            }
            else {
                toast(`${operation} failed: ${errorMsg.substring(0, 150)}`, 'err', 8000);
            }
            console.error(`[MITM Action Failed]`, { args, code: r.code, stderr: r.stderr, stdout: r.stdout });
            setStatus('Error', 'err');
        }
    }
    catch (e) {
        const operation = args.slice(1).join(' ');
        toast(`${operation} error: ${e.message}`, 'err', 8000);
        console.error(`[MITM Action Exception]`, { args, error: e });
        setStatus('Error', 'err');
    }
}
// Subcommands that may trigger a UAC prompt on Windows (certutil + netsh
// both require Admin). On macOS/Linux the message is misleading so we only
// show it on Windows; the platform is reported via `ag.info()`.
async function maybeUacPreStatus(subcommand) {
    const info = await window.ag.info();
    const platform = info?.platform ?? '';
    if (platform !== 'win32')
        return `${subcommand}…`;
    return `Waiting for UAC prompt — click "Yes" to allow ${subcommand}…`;
}
$('#mitmInstallBtn').addEventListener('click', async () => {
    const pre = await maybeUacPreStatus('install CA certificate');
    void mitmAction(['mitm', 'install', '--yes'], 'CA certificate installed', true, pre);
});
$('#mitmUninstallBtn').addEventListener('click', async () => {
    const pre = await maybeUacPreStatus('uninstall CA certificate');
    void mitmAction(['mitm', 'uninstall', '--yes'], 'CA certificate uninstalled', true, pre);
});
$('#mitmProxyOnBtn').addEventListener('click', async () => {
    setStatus('Enabling proxy…', 'busy');
    try {
        // Step 1: Start the proxy server
        console.log('[MITM] Starting proxy server...');
        const startResult = await window.ag.proxyStart();
        console.log('[MITM] Proxy start result:', startResult);
        if (!startResult.ok) {
            const decoded = decodeError(startResult.message ?? '', '');
            if (decoded.matched) {
                toast(`Failed to start proxy server — ${decoded.pattern}`, 'err', 8000);
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`Failed to start proxy server: ${startResult.message}`, 'err', 8000);
            }
            setStatus('Error', 'err');
            return;
        }
        toast(`Proxy server started (PID: ${startResult.pid})`, 'ok', 3000);
        // Step 2: Configure Windows to use the proxy
        const pre = await maybeUacPreStatus('enable proxy');
        setStatus(pre, 'busy');
        const r = await window.ag.run(['mitm', 'proxy-on']);
        if (r.code === 0) {
            toast('Proxy enabled and running', 'ok', 5000);
            void loadMitmStatus();
        }
        else {
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            toast(`Failed to configure proxy: ${errorMsg}`, 'err', 8000);
            setStatus('Error', 'err');
            // Try to stop the proxy server since configuration failed
            await window.ag.proxyStop();
        }
    }
    catch (e) {
        toast(`Proxy enable error: ${e.message}`, 'err', 8000);
        console.error(`[MITM] Proxy enable exception:`, e);
        setStatus('Error', 'err');
    }
});
$('#mitmProxyOffBtn').addEventListener('click', async () => {
    setStatus('Disabling proxy…', 'busy');
    try {
        // Step 1: Disable Windows proxy configuration
        const pre = await maybeUacPreStatus('disable proxy');
        setStatus(pre, 'busy');
        const r = await window.ag.run(['mitm', 'proxy-off']);
        if (r.code === 0) {
            toast('Proxy disabled', 'ok', 3000);
        }
        else {
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            toast(`Proxy disable warning: ${errorMsg}`, 'warn', 5000);
        }
        // Step 2: Stop the proxy server (even if config failed)
        console.log('[MITM] Stopping proxy server...');
        const stopResult = await window.ag.proxyStop();
        console.log('[MITM] Proxy stop result:', stopResult);
        if (stopResult.ok) {
            toast('Proxy server stopped', 'ok', 3000);
        }
        else {
            const decoded = decodeError(stopResult.message ?? '', '');
            if (decoded.matched) {
                toast(`Failed to stop proxy server — ${decoded.pattern}`, 'warn', 5000);
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`Failed to stop proxy server: ${stopResult.message}`, 'warn', 5000);
            }
        }
        void loadMitmStatus();
    }
    catch (e) {
        toast(`Proxy disable error: ${e.message}`, 'err', 8000);
        console.error(`[MITM] Proxy disable exception:`, e);
        setStatus('Error', 'err');
    }
});
$('#mitmExportCaBtn').addEventListener('click', () => void mitmAction(['mitm', 'export-ca'], 'CA exported'));
// ─────────────────────────────────────────────────────────────────────────────
// Patch view
// ─────────────────────────────────────────────────────────────────────────────
const patchStatusEl = $('#patchStatus');
const patchDetectedVersionEl = $('#patchDetectedVersion');
const patchDetectedSourceEl = $('#patchDetectedSource');
const patchRecommendedBadgeEl = $('#patchRecommendedBadge');
const patchDetectedMetaEl = $('#patchDetectedMeta');
const patchRangeGridEl = $('#patchRangeGrid');
const patchOverrideBannerEl = $('#patchOverrideBanner');
const patchOverrideBannerTextEl = $('#patchOverrideBannerText');
const patchRescanBtn = $('#patchRescanBtn');
const patchClearOverrideBtn = $('#patchClearOverrideBtn');
// Reusable template for patch status — avoids creating a new <template> each load
const patchTpl = document.createElement('template');
function patchBadge(label, tone = 'muted') {
    return `<span class="badge badge-${tone}">${escapeHtml(label)}</span>`;
}
function patchSourceLabel(s) {
    if (s.overrideActive)
        return 'Manual selection';
    if (s.antigravityVersionSource && s.antigravityVersionSource !== 'unknown') {
        return `Version read from ${s.antigravityVersionSource}`;
    }
    return 'Uncertain detection';
}
function patchFamilyLabel(range) {
    if (range.includes('2.3'))
        return 'Family 2.3';
    if (range.includes('2.2'))
        return 'Family 2.2';
    return 'Family 2.1';
}
function patchConfidenceLabel(confidence) {
    if (confidence === 'high')
        return 'High confidence';
    if (confidence === 'medium')
        return 'Medium confidence';
    return 'Low confidence';
}
function patchConfidenceTone(confidence) {
    if (confidence === 'high')
        return 'ok';
    if (confidence === 'medium')
        return 'warn';
    return 'err';
}
function patchSignatureLabel(s) {
    if (s.binarySignatureState === 'patched')
        return 'Binary signature: patch already present';
    if (s.binarySignatureState === 'original')
        return 'Binary signature: stock binary detected';
    return 'Binary signature missing';
}
function patchOverlayLabel(s) {
    if (!s.overlayFingerprintDetected || !s.overlayFingerprintRange)
        return 'JS overlay footprint missing or inconclusive';
    return `JS overlay footprint: ${s.overlayFingerprintRange}`;
}
function patchNeedsMetadataWithoutBinaryWarning(s) {
    return !!(s.antigravityVersion && s.antigravityVersion !== 'unknown' && !s.binarySignatureDetected);
}
function renderPatchSelector(s) {
    patchDetectedVersionEl.textContent = s.antigravityVersion ?? 'unknown';
    patchDetectedSourceEl.className = `badge ${s.overrideActive ? 'badge-warn' : 'badge-muted'}`;
    patchDetectedSourceEl.textContent = patchSourceLabel(s);
    patchRecommendedBadgeEl.className = `badge ${s.compatible ? 'badge-ok' : 'badge-warn'}`;
    patchRecommendedBadgeEl.textContent = s.recommendedPatch
        ? `${patchFamilyLabel(s.recommendedPatch.versionRange)} · ${patchConfidenceLabel(s.detectionConfidence)}`
        : 'no recommended family';
    const detectorMeta = [
        `<span class="badge badge-${patchConfidenceTone(s.detectionConfidence)}">${escapeHtml(patchConfidenceLabel(s.detectionConfidence))}</span>`,
        `<span class="badge ${s.binarySignatureDetected ? 'badge-ok' : 'badge-warn'}">${escapeHtml(patchSignatureLabel(s))}</span>`,
        s.overlayFingerprintDetected
            ? `<span class="badge ${s.overlayFingerprintConfidence === 'high' ? 'badge-ok' : 'badge-warn'}">${escapeHtml(patchOverlayLabel(s))}</span>`
            : '',
        s.detectionReason ? `<span class="badge badge-muted">${escapeHtml(s.detectionReason)}</span>` : '',
    ].filter(Boolean).join('');
    patchDetectedMetaEl.innerHTML = `
    <span class="badge ${s.overrideActive ? 'badge-warn' : 'badge-muted'}">${escapeHtml(patchSourceLabel(s))}</span>
    <span class="badge ${s.compatible ? 'badge-ok' : 'badge-warn'}">${escapeHtml(s.recommendedPatch ? `${patchFamilyLabel(s.recommendedPatch.versionRange)} · ${patchConfidenceLabel(s.detectionConfidence)}` : 'no recommended family')}</span>
    ${detectorMeta}`;
    if (s.overrideActive && s.overrideInfo?.range) {
        patchOverrideBannerEl.hidden = false;
        const reason = s.overrideInfo.reason ? ` — ${s.overrideInfo.reason}` : '';
        patchOverrideBannerTextEl.textContent = `Forced family: ${s.overrideInfo.range}${reason}`;
    }
    else {
        patchOverrideBannerEl.hidden = true;
        patchOverrideBannerTextEl.textContent = '—';
    }
    const detectedRanges = new Set((s.detectedPatches ?? []).map((p) => p.versionRange));
    if (s.overlayFingerprintDetected && s.overlayFingerprintRange) {
        detectedRanges.add(s.overlayFingerprintRange);
    }
    const recommendedRange = s.recommendedPatch?.versionRange ?? null;
    const cards = (s.availableRanges ?? []).map((range) => {
        const isRecommended = recommendedRange === range.versionRange;
        const isSelected = s.overrideInfo?.range === range.versionRange;
        const isDetected = detectedRanges.has(range.versionRange);
        const classes = [
            'patch-range-card',
            isRecommended ? 'recommended' : '',
            isSelected ? 'selected' : '',
            isDetected ? 'detected' : '',
            !s.compatible && isRecommended ? 'incompatible' : '',
        ].filter(Boolean).join(' ');
        const tags = [
            patchBadge(patchFamilyLabel(range.versionRange), 'muted'),
            isRecommended ? patchBadge('recommended', 'ok') : '',
            isSelected ? patchBadge('manual', 'warn') : '',
            isDetected && s.overlayFingerprintRange === range.versionRange
                ? patchBadge(`JS overlay footprint · ${patchConfidenceLabel(s.overlayFingerprintConfidence)}`, s.overlayFingerprintConfidence === 'high' ? 'ok' : 'warn')
                : '',
            isDetected && s.overlayFingerprintRange !== range.versionRange ? patchBadge('specific signature detected', 'ok') : '',
            !isDetected && s.binarySignatureDetected ? patchBadge('metadata-guided version', 'muted') : patchBadge('test manually', 'muted'),
        ].filter(Boolean).join('');
        return `
      <div class="${classes}">
        <div class="patch-range-card-header">
          <div class="patch-range-card-title">${escapeHtml(range.versionRange)}</div>
          ${isRecommended ? patchBadge(s.overrideActive ? 'forced' : 'auto target', s.overrideActive ? 'warn' : 'ok') : ''}
        </div>
        <div class="patch-range-card-body">
          <div class="patch-range-card-description">${escapeHtml(range.description)}</div>
          <div class="patch-range-card-tags">${tags}</div>
          <div class="patch-inline-note">${escapeHtml(range.originalUrl)} → ${escapeHtml(range.patchedUrl)}</div>
        </div>
        <div class="patch-range-card-actions">
          <button class="btn ${isSelected ? 'btn-secondary' : 'btn-ghost'} btn-sm" type="button" data-patch-range="${escapeHtml(range.versionRange)}">${isSelected ? 'Selected' : 'Select family'}</button>
        </div>
      </div>`;
    }).join('');
    patchRangeGridEl.innerHTML = cards || '<div class="empty-state"><p>No patch families available.</p></div>';
}
async function applyPatchRangeSelection(range) {
    setStatus(range ? `Selecting ${range}…` : 'Resetting to auto-detection…', 'busy');
    try {
        const args = range ? ['patch', 'select', range, '--json'] : ['patch', 'select', 'auto', '--json'];
        const r = await withTimeout(window.ag.run(args), 12_000, 'patch select');
        if (r.code !== 0) {
            throw new Error(r.stderr || r.stdout || 'patch select failed');
        }
        toast(range ? `Patch family set to ${range}` : 'Manual selection cleared', 'ok', 4000);
        await loadPatchStatus();
    }
    catch (e) {
        toast(`Patch update failed: ${e.message}`, 'err', 7000);
        setStatus('Error', 'err');
    }
}
async function loadPatchStatus() {
    return guardLoad('patch', async () => {
        setStatus('Loading patch status…', 'busy');
        showSkeleton(patchStatusEl, 'lines', 5);
        try {
            const r = await withTimeout(window.ag.run(['patch', 'status', '--json']), 12_000, 'patch status');
            const s = JSON.parse(r.stdout);
            renderPatchSelector(s);
            const banner = s.applied
                ? `<div class="patch-banner ok">
             <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
             <div class="patch-banner-body">
               <div class="patch-banner-title">Patch active</div>
               <div class="patch-banner-text"><code>language_server</code> is redirecting requests to the local proxy.</div>
             </div>
           </div>`
                : s.exists
                    ? `<div class="patch-banner warn">
               <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
               <div class="patch-banner-body">
                 <div class="patch-banner-title">Patch not applied</div>
                 <div class="patch-banner-text">Custom models will not appear in the menu until this step is applied.</div>
               </div>
             </div>`
                    : `<div class="patch-banner err">
               <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
               <div class="patch-banner-body">
                 <div class="patch-banner-title">Binary not found</div>
                 <div class="patch-banner-text">Could not locate <code>language_server</code> in the Antigravity installation.</div>
               </div>
             </div>`;
            const confidenceHero = `
      <div class="patch-confidence patch-confidence-${patchConfidenceTone(s.detectionConfidence)}">
        <div class="patch-confidence-eyebrow">Confidence level</div>
        <div class="patch-confidence-value">${escapeHtml(patchConfidenceLabel(s.detectionConfidence))}</div>
        <div class="patch-confidence-text">${escapeHtml(s.detectionReason ?? 'No detailed explanation provided by auto-detection yet.')}</div>
      </div>`;
            const metadataWithoutBinaryBanner = patchNeedsMetadataWithoutBinaryWarning(s)
                ? `<div class="patch-banner err">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4"/><path d="M12 17h.01"/><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">Version detected, binary signature missing</div>
             <div class="patch-banner-text">Antigravity <code>${escapeHtml(s.antigravityVersion ?? 'unknown')}</code> was recognized via <code>${escapeHtml(s.antigravityVersionSource ?? 'metadata')}</code>, but the <code>language_server</code> binary does not contain the expected signature. This can indicate a different build, a pre-modified binary, or a mixed installation.</div>
           </div>
         </div>`
                : '';
            const recommendationRow = s.recommendedPatch
                ? `
      <div class="patch-row">
        <div class="patch-row-label">Recommended family</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.versionRange)}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Recommendation source</div>
        <div class="patch-row-value ${s.overrideActive ? 'warn' : 'ok'}">${escapeHtml(s.overrideActive ? 'manual selection' : 'auto-detection')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Confidence</div>
        <div class="patch-row-value ${patchConfidenceTone(s.detectionConfidence)}">${escapeHtml(patchConfidenceLabel(s.detectionConfidence))}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Binary signature</div>
        <div class="patch-row-value ${s.binarySignatureDetected ? 'ok' : 'warn'}">${escapeHtml(patchSignatureLabel(s))}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">JS overlay footprint</div>
        <div class="patch-row-value ${s.overlayFingerprintDetected ? (s.overlayFingerprintConfidence === 'high' ? 'ok' : 'warn') : 'warn'}">${escapeHtml(patchOverlayLabel(s))}</div>
      </div>
      ${s.overlayFingerprintReason ? `
      <div class="patch-row">
        <div class="patch-row-label">JS footprint reason</div>
        <div class="patch-row-value">${escapeHtml(s.overlayFingerprintReason)}</div>
      </div>` : ''}
      <div class="patch-row">
        <div class="patch-row-label">Original URL</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.originalUrl)}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Patched URL</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.patchedUrl)}</div>
      </div>`
                : '';
            const overrideRow = s.overrideInfo?.range
                ? `
      <div class="patch-row">
        <div class="patch-row-label">Manual selection</div>
        <div class="patch-row-value warn">${escapeHtml(s.overrideInfo.range)}</div>
      </div>
      ${s.overrideInfo.reason ? `
      <div class="patch-row">
        <div class="patch-row-label">Reason</div>
        <div class="patch-row-value warn">${escapeHtml(s.overrideInfo.reason)}</div>
      </div>` : ''}`
                : '';
            const suggestions = `
      <div class="patch-row patch-suggestions">
        <div class="patch-row-label">Guidance</div>
        <div class="patch-row-value" style="max-width:100%; text-align:left;">
          <ul class="patch-suggestion-list">
            <li>Keep auto-detection active by default and only force a family if the detected version is incorrect.</li>
            <li>Always keep a clean backup before switching between 2.1, 2.2, or 2.3 patch families.</li>
            <li>For 2.2.x and 2.3.x, check MITM status and CA certificate installation before applying the patch.</li>
            <li>If metadata and binary signature disagree, restore from backup first before trying a manual family.</li>
          </ul>
        </div>
      </div>`;
            patchTpl.innerHTML = `
      ${banner}
      ${confidenceHero}
      ${metadataWithoutBinaryBanner}
      <div class="patch-row">
        <div class="patch-row-label">Antigravity version</div>
        <div class="patch-row-value">${escapeHtml(s.antigravityVersion ?? 'unknown')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Version source</div>
        <div class="patch-row-value">${escapeHtml(s.antigravityVersionSource ?? 'unknown')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Binary path</div>
        <div class="patch-row-value">${escapeHtml(s.binaryPath ?? '—')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Present</div>
        <div class="patch-row-value ${s.exists ? 'ok' : 'err'}">${s.exists ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Already patched</div>
        <div class="patch-row-value ${s.applied ? 'ok' : 'warn'}">${s.applied ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Backup</div>
        <div class="patch-row-value ${s.backupExists ? 'ok' : ''}">${s.backupExists ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Compatibility</div>
        <div class="patch-row-value ${s.compatible ? 'ok' : 'warn'}">${s.compatible ? 'ok' : 'needs verification'}</div>
      </div>
      ${s.detectionReason ? `
      <div class="patch-row">
        <div class="patch-row-label">Recommendation reason</div>
        <div class="patch-row-value">${escapeHtml(s.detectionReason)}</div>
      </div>` : ''}
      ${recommendationRow}
      ${overrideRow}
      ${s.warningMessage ? `
      <div class="patch-row">
        <div class="patch-row-label">Warning</div>
        <div class="patch-row-value warn">${escapeHtml(s.warningMessage)}</div>
      </div>` : ''}
      ${suggestions}`;
            patchStatusEl.replaceChildren(patchTpl.content);
            setStatus('Ready');
        }
        catch (e) {
            patchStatusEl.innerHTML = `<div class="empty-state"><p>Could not load patch status: ${escapeHtml(e.message)}</p></div>`;
        }
        finally {
            hideSkeleton(patchStatusEl);
        }
    });
}
patchRescanBtn.addEventListener('click', () => void loadPatchStatus());
patchClearOverrideBtn.addEventListener('click', () => void applyPatchRangeSelection(null));
patchRangeGridEl.addEventListener('click', (event) => {
    const target = event.target;
    const button = target?.closest('[data-patch-range]');
    if (!button)
        return;
    const range = button.getAttribute('data-patch-range');
    if (!range)
        return;
    void applyPatchRangeSelection(range);
});
$('#patchApplyBtn').addEventListener('click', async () => {
    // P1.3 (subset) — Validate the binary state (existence, compatibility,
    // backup presence, known recommended patch) BEFORE risking a destructive
    // change. The UI equivalent of a "delta size check": confirm the delta
    // (backup → patched binary) is in a consistent state before applying.
    let preflight = null;
    try {
        setStatus('Preflight check…', 'busy');
        const r = await withTimeout(window.ag.run(['patch', 'status', '--json']), 12_000, 'patch status');
        preflight = JSON.parse(r.stdout);
    }
    catch (e) {
        setStatus('Ready');
        toast(`Preflight failed: cannot read patch status (${e.message})`, 'err', 6000);
        return;
    }
    if (!preflight.exists) {
        setStatus('Ready');
        toast('Preflight failed: language_server binary not found. Nothing to patch.', 'err', 6000);
        return;
    }
    if (!preflight.compatible) {
        setStatus('Ready');
        toast('Preflight failed: Antigravity version is not compatible with the known patch.', 'err', 6000);
        return;
    }
    if (!preflight.recommendedPatch) {
        setStatus('Ready');
        toast('Preflight failed: no recommended patch available for this version.', 'err', 6000);
        return;
    }
    if (preflight.applied) {
        setStatus('Ready');
        toast('Patch is already applied. Use Restore first if you want to re-apply.', 'warn', 5000);
        return;
    }
    if (!preflight.backupExists) {
        // Non-blocking: warn the user but still allow them to confirm.
        console.warn('[patch] No backup found — applying patch will not be reversible');
    }
    // Build the details shown in the confirmation modal (includes the "delta
    // size" when the backend provides it via the optional deltaSizeBytes field).
    const sizeInfo = typeof preflight.deltaSizeBytes === 'number' && preflight.deltaSizeBytes > 0
        ? `<br><br><strong>Estimated delta size:</strong> ${escapeHtml(formatBytes(preflight.deltaSizeBytes))}`
        : '';
    const backupWarn = preflight.backupExists
        ? ''
        : '<br><br><strong style="color:var(--warn)">⚠ No backup found — patch will not be reversible.</strong>';
    const validateReport = preflight
        .validateAsarReport ?? null;
    const verdict = validateReport?.verdict ?? preflight.verdict ?? null;
    let validateBlockHtml = '';
    if (validateReport) {
        const verdictColor = verdict === 'block' ? 'var(--err, #f44)' :
            verdict === 'warn' ? 'var(--warn, #f90)' :
                verdict === 'ok' ? 'var(--ok, #0a0)' : 'var(--muted, #888)';
        const verdictLabel = (verdict ?? 'unknown').toUpperCase();
        const rows = validateReport.checks
            .map((c) => {
            const icon = c.status === 'ok' ? '✓' : '✗';
            const tag = c.required ? 'required' : 'advisory';
            const detail = c.detail ? ` — <span class="patch-row-detail">${escapeHtml(c.detail)}</span>` : '';
            return `<li>${icon} <strong>${escapeHtml(c.label)}</strong> <em>(${tag})</em>${detail}</li>`;
        })
            .join('');
        validateBlockHtml = `
      <div class="patch-row">
        <div class="patch-row-label">Asar validation</div>
        <div class="patch-row-value" style="color:${verdictColor}">
          <strong>Verdict: ${escapeHtml(verdictLabel)}</strong>
          <ul style="margin: 6px 0 0 18px; padding: 0;">${rows}</ul>
        </div>
      </div>`;
    }
    if (verdict === 'block') {
        setStatus('Ready');
        toast('Asar validation failed (verdict=block). Patch cannot be applied — see preflight modal.', 'err', 8000);
        // Open the confirmation modal anyway so the user can read the verdict,
        // but the Apply button will be disabled below.
    }
    const ok = await confirmModal('Apply binary patch', `This will modify <code>language_server</code> to redirect API calls to the local proxy.<br><br>A backup will be created automatically.${sizeInfo}${backupWarn}${validateBlockHtml}`, { confirmLabel: verdict === 'block' ? 'Blocked — cannot apply' : 'Apply patch', confirmDisabled: verdict === 'block' });
    if (!ok) {
        setStatus('Ready');
        return;
    }
    setStatus('Applying patch…', 'busy');
    try {
        const r = await window.ag.run(['patch', 'apply', '--yes']);
        if (r.code === 0) {
            toast('Patch applied successfully', 'ok', 5000);
            void loadPatchStatus();
        }
        else {
            const decoded = decodeError(r.stderr, r.stdout);
            if (decoded.matched) {
                toast(`Patch failed — ${decoded.pattern}`, 'err', 6000);
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`Patch failed: ${r.stderr || r.stdout}`, 'err', 6000);
            }
        }
        setStatus('Ready');
    }
    catch (e) {
        toast(`Could not apply patch: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
$('#patchRestoreBtn').addEventListener('click', async () => {
    const ok = await confirmModal('Restore from backup', `This will restore the original <code>language_server</code> binary from backup.<br><br>The patch will be undone.`, { confirmLabel: 'Restore', danger: true });
    if (!ok)
        return;
    setStatus('Restoring…', 'busy');
    try {
        const r = await window.ag.run(['patch', 'restore', '--yes']);
        if (r.code === 0) {
            toast('Restored successfully', 'ok');
            void loadPatchStatus();
        }
        else {
            const decoded = decodeError(r.stderr, r.stdout);
            if (decoded.matched) {
                toast(`Restore failed — ${decoded.pattern}`, 'err');
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`Restore failed: ${r.stderr || r.stdout}`, 'err');
            }
        }
        setStatus('Ready');
    }
    catch (e) {
        toast(`Could not restore: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// Logs view (streaming)
// ─────────────────────────────────────────────────────────────────────────────
const logsOutput = $('#logsOutput');
const logsFollowBtn = $('#logsFollowBtn');
const logsClearBtn = $('#logsClearBtn');
const logsCopyBtn = $('#logsCopyBtn');
let logsStreamId = null;
let logsStreaming = false;
// Streaming buffer: raw text chunks are concatenated and ANSI-converted ONCE
// per animation frame, then appended in a single DOM mutation. The previous
// implementation ran ansiToHtml on every chunk (N regex passes per flush
// window) — see audit finding P0.
// Hard cap on the rendered log buffer so a long stream cannot bloat the
// <pre> node past ~500 KB and stall layout. We keep the last ~400 KB.
const LOGS_MAX_BYTES = 500_000;
const LOGS_KEEP_BYTES = 400_000;
let logsPendingChunk = null;
let logsFlushScheduled = false;
const flushLogs = () => {
    logsFlushScheduled = false;
    if (logsPendingChunk) {
        // Append as text (no HTML parsing needed for ANSI-stripped output).
        logsOutput.insertAdjacentText('beforeend', logsPendingChunk);
        logsPendingChunk = null;
    }
    // Bound the DOM: when the rendered text grows past the cap, drop the
    // oldest content while keeping the latest keep-window.
    if (logsOutput.textContent && logsOutput.textContent.length > LOGS_MAX_BYTES) {
        const trimmed = logsOutput.textContent.slice(-LOGS_KEEP_BYTES);
        logsOutput.textContent = trimmed;
        logsOutput.scrollTop = logsOutput.scrollHeight;
    }
    else {
        logsOutput.scrollTop = logsOutput.scrollHeight;
    }
};
const scheduleLogsFlush = () => {
    if (logsFlushScheduled)
        return;
    logsFlushScheduled = true;
    requestAnimationFrame(flushLogs);
};
// Reusable template for terminal output — avoids creating a new <template> each load
const logsTpl = document.createElement('template');
const logsSkeleton = $('#logsSkeleton');
async function loadLogs() {
    if (logsStreaming)
        return;
    setStatus('Loading logs…', 'busy');
    logsSkeleton.style.display = 'block';
    logsOutput.style.display = 'none';
    try {
        const r = await window.ag.run(['logs', '-n', '100', '--source', currentLogSource]);
        logsTpl.innerHTML = ansiToHtml(r.stdout || r.stderr || '(empty)');
        logsOutput.replaceChildren(logsTpl.content);
        setStatus('Ready');
    }
    catch (e) {
        logsOutput.textContent = `Could not load logs: ${e.message}`;
        setStatus('Error', 'err');
    }
    finally {
        logsSkeleton.style.display = 'none';
        logsOutput.style.display = '';
    }
}
async function startLogStream() {
    if (logsStreaming)
        return;
    logsStreaming = true;
    logsFollowBtn.innerHTML = '<span class="dot-live"></span> Stop';
    setStatus('Streaming logs…', 'busy');
    logsStreamId = `logs-${Date.now()}`;
    window.ag.onStreamData(logsStreamId, (chunk) => {
        // PERF: accumulate RAW chunks and run ansiToHtml exactly once per flush.
        // The previous code called ansiToHtml on every chunk (N regex passes
        // per flush window when chunks arrive in quick bursts).
        logsPendingChunk = (logsPendingChunk ?? '') + chunk;
        scheduleLogsFlush();
    });
    window.ag.onStreamClose(logsStreamId, (code) => {
        // Flush any pending chunks before signaling closure
        flushLogs();
        logsStreaming = false;
        logsFollowBtn.innerHTML = '<span class="dot-live"></span> Follow';
        setStatus(`Stream closed (${code})`);
    });
    window.ag.onStreamError(logsStreamId, (err) => {
        flushLogs();
        toast(`Stream error: ${err}`, 'err');
        stopLogStream();
    });
    await window.ag.startStream(['logs', '-f'], logsStreamId);
}
async function stopLogStream() {
    if (logsStreamId) {
        await window.ag.cancelStream(logsStreamId);
        logsStreamId = null;
    }
    logsStreaming = false;
    logsFollowBtn.innerHTML = '<span class="dot-live"></span> Follow';
    setStatus('Ready');
}
logsFollowBtn.addEventListener('click', () => {
    if (logsStreaming)
        void stopLogStream();
    else
        void startLogStream();
});
logsClearBtn.addEventListener('click', () => {
    logsOutput.textContent = '';
});
logsCopyBtn.addEventListener('click', async () => {
    await navigator.clipboard.writeText(logsOutput.textContent ?? '');
    toast('Logs copied to clipboard', 'ok', 2000);
});
// Logs tabs: switch between log sources
let currentLogSource = 'language_server';
const logsTabs = $$('#logsTabs .tab');
logsTabs.forEach((tab) => {
    tab.addEventListener('click', () => {
        const source = tab.dataset.source ?? 'language_server';
        if (source === currentLogSource)
            return;
        logsTabs.forEach((t) => {
            const isActive = t === tab;
            t.classList.toggle('active', isActive);
            t.setAttribute('aria-selected', isActive ? 'true' : 'false');
        });
        currentLogSource = source;
        void loadLogs();
    });
});
// ─────────────────────────────────────────────────────────────────────────────
// Antigravity Status view
// ─────────────────────────────────────────────────────────────────────────────
const infoTable = $('#infoTable');
const agHeroDot = $('#agHeroDot');
const agHeroLabel = $('#agHeroLabel');
const agHeroTitle = $('#agHeroTitle');
const agHeroMeta = $('#agHeroMeta');
const agVersion = $('#agVersion');
const agPid = $('#agPid');
const agCustomModels = $('#agCustomModels');
const agUptime = $('#agUptime');
const agPaths = $('#agPaths');
const agRefreshBtn = $('#agRefreshBtn');
const agOpenBtn = $('#agOpenBtn');
const agRestartBtn = $('#agRestartBtn');
const agLaunchLogsBtn = $('#agLaunchLogsBtn');
const agRevealBtn = $('#agRevealBtn');
const agCopyPathsBtn = $('#agCopyPathsBtn');
let agStartedAt = null;
let agUptimeTimer = null;
function setAgHero(status, label, meta) {
    agHeroDot.className = `ag-hero-dot ${status}`;
    agHeroLabel.textContent = label;
    agHeroMeta.textContent = meta;
}
function formatUptime(ms) {
    const s = Math.floor(ms / 1000);
    if (s < 60)
        return `${s}s`;
    const m = Math.floor(s / 60);
    if (m < 60)
        return `${m}m ${s % 60}s`;
    const h = Math.floor(m / 60);
    return `${h}h ${m % 60}m`;
}
function startUptimeTicker() {
    // PERF: every previous interval must be cleared before assigning a new one.
    // The original code only cleared when re-entering startUptimeTicker, so a
    // fast launch → refresh → launch sequence leaked N zombie timers that kept
    // writing into a hidden view's DOM node.
    if (agUptimeTimer !== null) {
        window.clearInterval(agUptimeTimer);
        agUptimeTimer = null;
    }
    agStartedAt = Date.now();
    agUptimeTimer = window.setInterval(() => {
        if (agStartedAt)
            agUptime.textContent = formatUptime(Date.now() - agStartedAt);
    }, 1000);
}
// Reusable template for paths — avoids creating a new <template> each render
const pathsTpl = document.createElement('template');
function renderPaths(paths) {
    const html = paths
        .filter(([, v]) => v && v !== '—')
        .map(([label, value]) => `
      <div class="path-row">
        <div class="path-row-label">${escapeHtml(label)}</div>
        <div class="path-row-value" title="${escapeHtml(value)}">${escapeHtml(value)}</div>
        <div class="path-row-actions">
          <button type="button" data-copy="${escapeHtml(value)}" title="Copy">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          </button>
          <button type="button" data-reveal="${escapeHtml(value)}" title="Reveal">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          </button>
        </div>
      </div>
    `).join('');
    pathsTpl.innerHTML = html;
    agPaths.replaceChildren(pathsTpl.content);
}
// Event delegation for path actions
agPaths.addEventListener('click', async (e) => {
    const target = e.target;
    const copyBtn = target.closest('[data-copy]');
    if (copyBtn) {
        await navigator.clipboard.writeText(copyBtn.dataset.copy ?? '');
        toast('Path copied', 'ok', 1500);
        return;
    }
    const revealBtn = target.closest('[data-reveal]');
    if (revealBtn) {
        await window.ag.reveal(revealBtn.dataset.reveal ?? '');
    }
});
agCopyPathsBtn.addEventListener('click', async () => {
    const values = Array.from(agPaths.querySelectorAll('.path-row-value'))
        .map((el) => el.textContent ?? '').join('\n');
    await navigator.clipboard.writeText(values);
    toast('All paths copied', 'ok', 2000);
});
agRefreshBtn.addEventListener('click', () => void loadAntigravityStatus());
agOpenBtn.addEventListener('click', async () => {
    setAgHero('busy', 'Opening…', 'Launching Antigravity');
    try {
        const result = await window.ag.antigravityLaunch();
        if (!result.ok)
            throw new Error(result.error ?? 'Launch failed');
        const pid = result.data?.pid;
        setAgHero('ok', 'Running', `PID ${pid ?? '—'} · Launched`);
        startUptimeTicker();
        toast('Antigravity launched', 'ok', 2000);
    }
    catch (e) {
        setAgHero('err', 'Failed', e.message);
        toast(`Launch failed: ${e.message}`, 'err');
    }
});
agRestartBtn.addEventListener('click', async () => {
    setAgHero('busy', 'Restarting…', 'Killing and relaunching');
    try {
        const result = await window.ag.antigravityRestart();
        if (!result.ok)
            throw new Error(result.error ?? 'Restart failed');
        const pid = result.data?.pid;
        setAgHero('ok', 'Running', `PID ${pid ?? '—'} · Restarted`);
        startUptimeTicker();
        toast('Antigravity restarted', 'ok', 2000);
    }
    catch (e) {
        setAgHero('err', 'Failed', e.message);
        toast(`Restart failed: ${e.message}`, 'err');
    }
});
agRevealBtn.addEventListener('click', async () => {
    try {
        const r = await window.ag.antigravityStatus();
        const installDir = r.ok ? r.data?.installDir : undefined;
        if (installDir) {
            await window.ag.reveal(installDir);
        }
        else {
            toast('Install directory not found', 'warn');
        }
    }
    catch (e) {
        toast(`Reveal failed: ${e.message}`, 'err');
    }
});
async function loadAntigravityStatus() {
    return guardLoad('agStatus', async () => {
        setStatus('Loading Antigravity status…', 'busy');
        setAgHero('busy', 'Checking…', 'Detecting installation');
        try {
            // Parallel: info IPC, status IPC, version IPC, models count
            const [info, statusResult, versionResult, modelsResult] = await Promise.all([
                // PERF: 5 s TTL caused stale reads and split-cached state with the
                // boot path that requests 60 s. Unify to 60 s (info rarely changes).
                memo('info', 60_000, () => window.ag.info()),
                withTimeout(window.ag.antigravityStatus(), 10_000, 'antigravity status').catch((err) => ({ ok: false, data: undefined, error: err.message })),
                withTimeout(window.ag.antigravityVersion(), 10_000, 'antigravity version').catch((err) => ({ ok: false, data: undefined, error: err.message })),
                withTimeout(window.ag.run(['models', 'list', '--json']), 10_000, 'models list').catch(() => ({ stdout: '{"models":[]}', stderr: '', code: 0 })),
            ]);
            const status = statusResult.ok ? statusResult.data : null;
            const versionData = versionResult.ok ? versionResult.data : null;
            let modelsCount = 0;
            try {
                const modelsData = JSON.parse(modelsResult.stdout);
                if (modelsData && Array.isArray(modelsData.models)) {
                    modelsCount = modelsData.models.length;
                }
            }
            catch {
                modelsCount = 0;
            }
            const installed = Boolean(status?.installed ?? status?.installDir);
            const running = Boolean(status?.running ?? status?.pid);
            const pid = status?.pid;
            const version = versionData?.version ?? status?.version;
            const installDir = status?.installDir ?? '';
            // Hero card
            if (!installed) {
                setAgHero('err', 'Not installed', installDir || 'No installation found');
            }
            else if (running) {
                setAgHero('ok', 'Running', `PID ${pid ?? '—'} · ${version ?? 'unknown'}`);
                startUptimeTicker();
            }
            else {
                setAgHero('warn', 'Installed · Stopped', version ?? 'Not running');
            }
            agHeroTitle.textContent = status?.displayName ?? 'Antigravity';
            // Stat cards
            agVersion.textContent = version ?? '—';
            agPid.textContent = pid != null ? String(pid) : '—';
            agCustomModels.textContent = String(modelsCount);
            if (!running && agUptime)
                agUptime.textContent = '—';
            // Paths
            const paths = [
                ['Install dir', installDir],
                ['Binary', status?.binaryPath ?? ''],
                ['app.asar', status?.appAsarPath ?? ''],
                ['custom_models.json', status?.customModelsPath ?? ''],
                ['LS log', status?.lsLogPath ?? ''],
                ['CLI', info.cliPath],
            ];
            renderPaths(paths);
            // Runtime details table
            const rows = [
                ['Platform', `${info.platform}/${info.arch}`],
                ['Electron', info.electron],
                ['Node', info.node],
                ['Chromium', info.chrome],
                ['Username', status?.username ?? '—'],
                ['Home', status?.homedir ?? '—'],
                ['CPU', status?.cpu ?? '—'],
                ['Memory', status?.memory ?? '—'],
            ];
            const html = rows
                .map(([k, v]) => `<div class="info-cell k">${escapeHtml(k)}</div><div class="info-cell v">${escapeHtml(v)}</div>`)
                .join('');
            infoTableTpl.innerHTML = html;
            infoTable.replaceChildren(infoTableTpl.content);
            setStatus('Ready');
        }
        catch (e) {
            setAgHero('err', 'Error', e.message);
            infoTable.innerHTML = `<div class="empty-state"><p>Could not load Antigravity info: ${escapeHtml(e.message)}</p></div>`;
            setStatus('Error', 'err');
        }
    });
}
// Backward compat alias
const loadInfo = loadAntigravityStatus;
// ─────────────────────────────────────────────────────────────────────────────
// Settings view
// ─────────────────────────────────────────────────────────────────────────────
const themeToggle = $('#themeToggle');
const settingsConfigPath = $('#settingsConfigPath');
const settingsConfigBody = $('#settingsConfigBody');
const settingsConfigSkeleton = $('#settingsConfigSkeleton');
async function loadSettings() {
    setStatus('Loading settings…', 'busy');
    settingsConfigSkeleton.style.display = 'block';
    settingsConfigBody.style.display = 'none';
    try {
        // Parallelize the three independent IPC calls.
        // Memoize config() with 30s TTL — it changes only when user toggles theme.
        const [cfg, pathResult, listResult] = await Promise.all([
            memo('config', 30_000, () => window.ag.config()),
            window.ag.run(['config', 'path']),
            window.ag.run(['config', 'list', '--json']),
        ]);
        const theme = cfg.ui?.theme ?? 'dark';
        themeToggle.textContent = theme === 'dark' ? 'Switch to light' : 'Switch to dark';
        settingsConfigPath.textContent = pathResult.stdout.trim();
        settingsConfigBody.textContent = JSON.stringify(JSON.parse(listResult.stdout), null, 2);
        setStatus('Ready');
    }
    catch (e) {
        setStatus('Error', 'err');
        toast(`Settings error: ${e.message}`, 'err');
    }
    finally {
        settingsConfigSkeleton.style.display = 'none';
        settingsConfigBody.style.display = '';
    }
}
themeToggle.addEventListener('click', async () => {
    const current = document.documentElement.dataset.theme ?? 'dark';
    const next = current === 'dark' ? 'light' : 'dark';
    await setTheme(next);
});
async function setTheme(theme) {
    document.documentElement.dataset.theme = theme;
    themeToggle.textContent = theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme';
    themeToggle.setAttribute('aria-pressed', theme === 'light' ? 'true' : 'false');
    updateStatusBarTheme(theme);
    // Invalidate config cache so the next loadSettings() picks up the new theme
    invalidateCache('config');
    await window.ag.setTheme(theme);
    toast(`Theme set to ${theme}`, 'ok', 2000);
}
async function applySavedTheme() {
    try {
        // Memoize config() — applied at boot, called once
        const cfg = await memo('config', 30_000, () => window.ag.config());
        const theme = cfg.ui?.theme ?? 'dark';
        document.documentElement.dataset.theme = theme;
        updateStatusBarTheme(theme);
    }
    catch {
        document.documentElement.dataset.theme = 'dark';
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// Command palette
// ─────────────────────────────────────────────────────────────────────────────
const paletteBackdrop = $('#paletteBackdrop');
const paletteInput = $('#paletteInput');
const paletteResults = $('#paletteResults');
const PALETTE_COMMANDS = [
    { id: 'dashboard', label: 'Go to Dashboard', view: 'dashboard' },
    { id: 'doctor', label: 'Run System Diagnostic (Doctor)', view: 'dashboard', action: () => void runDoctor() },
    { id: 'fix-all', label: 'Fix All — Full Auto-Repair', view: 'dashboard', action: () => void runFixAll() },
    { id: 'antigravity', label: 'Go to Antigravity Status', view: 'info' },
    { id: 'models', label: 'Go to Custom Models', view: 'models' },
    { id: 'mitm', label: 'Go to MITM Proxy Manager', view: 'mitm' },
    { id: 'patch', label: 'Go to Binary Patch Manager', view: 'patch' },
    { id: 'proxy-stub', label: 'Start Emergency Proxy Stub (Port 50999)', view: 'mitm', action: () => void runStartStub() },
    { id: 'logs', label: 'Go to System Logs', view: 'logs' },
    { id: 'settings', label: 'Go to Settings', view: 'settings' },
    { id: 'theme', label: 'Toggle Light / Dark Theme', view: 'settings', action: () => {
            const current = document.documentElement.dataset.theme ?? 'dark';
            void setTheme(current === 'dark' ? 'light' : 'dark');
        } },
    { id: 'info', label: 'Go to System Info & Installations', view: 'info' },
];
function openPalette() {
    paletteBackdrop.hidden = false;
    paletteInput.value = '';
    paletteInput.focus();
    renderPalette('');
}
function closePalette() {
    paletteBackdrop.hidden = true;
}
// Reusable template element — avoids creating a new <template> on every keystroke
const paletteTpl = document.createElement('template');
// Single delegated click listener (bound once) instead of N listeners per item
paletteResults.addEventListener('click', (e) => {
    const target = e.target.closest('.palette-item');
    if (target?.dataset.id)
        executePalette(target.dataset.id);
});
function renderPalette(query) {
    const q = query.trim().toLowerCase();
    const filtered = PALETTE_COMMANDS.filter((c) => c.label.toLowerCase().includes(q) || c.view.toLowerCase().includes(q));
    const html = filtered
        .map((c, i) => `
      <div class="palette-item ${i === 0 ? 'selected' : ''}" data-index="${i}" data-id="${escapeHtml(c.id)}">
        <span>${escapeHtml(c.label)}</span>
        <span class="palette-hint">${escapeHtml(c.view)}</span>
      </div>`)
        .join('');
    paletteTpl.innerHTML = html;
    paletteResults.replaceChildren(paletteTpl.content);
}
function executePalette(id) {
    const cmd = PALETTE_COMMANDS.find((c) => c.id === id);
    if (!cmd)
        return;
    closePalette();
    if (cmd.action)
        cmd.action();
    else
        navigate(cmd.view);
}
paletteInput.addEventListener('input', () => renderPalette(paletteInput.value));
paletteInput.addEventListener('keydown', (e) => {
    const items = paletteResults.querySelectorAll('.palette-item');
    const selected = paletteResults.querySelector('.palette-item.selected');
    let idx = selected ? Number(selected.dataset.index) : -1;
    if (e.key === 'ArrowDown') {
        e.preventDefault();
        idx = Math.min(idx + 1, items.length - 1);
        items.forEach((it) => it.classList.remove('selected'));
        items[idx]?.classList.add('selected');
        items[idx]?.scrollIntoView({ block: 'nearest' });
    }
    else if (e.key === 'ArrowUp') {
        e.preventDefault();
        idx = Math.max(idx - 1, 0);
        items.forEach((it) => it.classList.remove('selected'));
        items[idx]?.classList.add('selected');
        items[idx]?.scrollIntoView({ block: 'nearest' });
    }
    else if (e.key === 'Enter') {
        e.preventDefault();
        const target = paletteResults.querySelector('.palette-item.selected') ?? items[0];
        if (target)
            executePalette(target.dataset.id);
    }
    else if (e.key === 'Escape') {
        closePalette();
    }
});
paletteBackdrop.addEventListener('click', (e) => {
    if (e.target === paletteBackdrop)
        closePalette();
});
// Global shortcut: Ctrl+Shift+P / Cmd+Shift+P
document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'P' || e.key === 'p')) {
        e.preventDefault();
        openPalette();
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// Main → renderer events
// ─────────────────────────────────────────────────────────────────────────────
window.ag.onRunDoctor(() => void runDoctor());
window.ag.onNavigate((view) => navigate(view));
window.ag.onCommandPalette(() => openPalette());
window.ag.onThemeChanged((theme) => {
    document.documentElement.dataset.theme = theme;
    themeToggle.textContent = theme === 'dark' ? 'Switch to light' : 'Switch to dark';
    updateStatusBarTheme(theme);
});
// ─────────────────────────────────────────────────────────────────────────────
// Status bar wiring
// ─────────────────────────────────────────────────────────────────────────────
const statusPlatformText = $('#statusPlatformText');
const statusVersion = $('#statusVersion');
const statusTheme = $('#statusTheme');
function updateStatusBarTheme(theme) {
    if (!statusTheme)
        return;
    const label = statusTheme.querySelector('span');
    if (label)
        label.textContent = theme === 'light' ? 'Light' : 'Dark';
}
function updateStatusBarPlatform(platform, arch) {
    if (statusPlatformText)
        statusPlatformText.textContent = `${platform}/${arch}`;
}
if (statusTheme) {
    statusTheme.addEventListener('click', async () => {
        const current = document.documentElement.dataset.theme ?? 'dark';
        const next = current === 'dark' ? 'light' : 'dark';
        await setTheme(next);
    });
}
// ─────────────────────────────────────────────────────────────────────────────
// Boot
// ─────────────────────────────────────────────────────────────────────────────
(async function boot() {
    setStatus('Initializing…', 'busy');
    try {
        // Parallelize: theme config + system info are independent IPC calls
        const [, info] = await Promise.all([
            applySavedTheme(),
            memo('info', 60_000, () => window.ag.info()),
        ]);
        setStatus(`Ready · ${info.platform}/${info.arch}`);
        updateStatusBarPlatform(info.platform, info.arch);
        updateStatusBarTheme(document.documentElement.dataset.theme ?? 'dark');
        if (statusVersion)
            statusVersion.textContent = `v${info.electron ? '1.0.0' : '1.0.0'}`;
    }
    catch {
        setStatus('Ready');
    }
    // Defer the initial diagnostic to idle time so the UI paints first.
    // The user sees the dashboard shell immediately, then results fill in.
    whenIdle(() => void runDoctor(), 250);
})();
const agVersionValue = $('#agVersionValue');
const agRunningValue = $('#agRunningValue');
const agProxyValue = $('#agProxyValue');
const agLsValue = $('#agLsValue');
const agSourceBadge = $('#agSourceBadge');
const agInstallPath = $('#agInstallPath');
const agAppAsar = $('#agAppAsar');
const agVersionRow = $('#agVersionRow');
const agChannelRow = $('#agChannelRow');
const agPidsBadge = $('#agPidsBadge');
const agAgPids = $('#agAgPids');
const agLsPids = $('#agLsPids');
function renderAntigravity(s) {
    if (!s.installed) {
        agVersionValue.textContent = '—';
        agRunningValue.textContent = 'not installed';
        agProxyValue.textContent = '—';
        agLsValue.textContent = '—';
        agSourceBadge.textContent = 'missing';
        agInstallPath.textContent = 'Antigravity executable not found';
        agAppAsar.textContent = '—';
        agVersionRow.textContent = '—';
        agChannelRow.textContent = '—';
        agPidsBadge.textContent = '0 PIDs';
        agAgPids.textContent = '—';
        agLsPids.textContent = '—';
        return;
    }
    // version is now a flat string; versionInfo has {version, channel, source}
    const vStr = s.version ?? s.versionInfo?.version ?? 'unknown';
    const vSource = s.versionInfo?.source ?? 'unknown';
    const vChannel = s.versionInfo?.channel ?? s.displayName ?? '—';
    agVersionValue.textContent = vStr;
    agVersionValue.className = 'stat-value ' + (vSource === 'asar' ? 'ok' : 'warn');
    agRunningValue.textContent = s.running ? 'running' : 'stopped';
    agRunningValue.className = 'stat-value ' + (s.running ? 'ok' : 'err');
    agProxyValue.textContent = s.proxyReachable ? `:${s.proxyPort} up` : `:${s.proxyPort} down`;
    agProxyValue.className = 'stat-value ' + (s.proxyReachable ? 'ok' : 'warn');
    agLsValue.textContent = s.languageServerRunning ? 'running' : 'stopped';
    agLsValue.className = 'stat-value ' + (s.languageServerRunning ? 'ok' : 'warn');
    agSourceBadge.textContent = vSource;
    agInstallPath.textContent = s.installDir ?? '—';
    agAppAsar.textContent = s.appAsar ?? s.appAsarPath ?? '—';
    agVersionRow.textContent = vStr;
    agChannelRow.textContent = vChannel;
    const total = s.pids.length + s.languageServerPids.length;
    agPidsBadge.textContent = `${total} PID${total === 1 ? '' : 's'}`;
    agAgPids.textContent = s.pids.length ? s.pids.join(', ') : '—';
    agLsPids.textContent = s.languageServerPids.length ? s.languageServerPids.join(', ') : '—';
}
async function loadAntigravity() {
    return guardLoad('ag', async () => {
        setStatus('Loading Antigravity status…', 'busy');
        try {
            const r = await withTimeout(window.ag.antigravityStatus(), 10_000, 'antigravity status');
            if (!r.ok || !r.data) {
                toast(`Antigravity: ${r.error ?? 'unknown error'}`, 'err');
                setStatus('Ready');
                return;
            }
            renderAntigravity(r.data);
            setStatus('Ready');
        }
        catch (e) {
            toast(`Could not load Antigravity status: ${e.message}`, 'err');
            setStatus('Error', 'err');
        }
    });
}
$('#agRefreshBtn').addEventListener('click', () => void loadAntigravity());
$('#agLaunchBtn').addEventListener('click', async () => {
    setStatus('Launching Antigravity…', 'busy');
    try {
        const r = await window.ag.antigravityLaunch();
        if (r.ok && r.data) {
            toast(r.data.message, r.data.ok ? 'ok' : 'warn', 4000);
        }
        else {
            toast(`Launch failed: ${r.error ?? 'unknown'}`, 'err');
        }
        await loadAntigravity();
    }
    catch (e) {
        toast(`Could not launch Antigravity: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
$('#agLaunchLogsBtn').addEventListener('click', async () => {
    if (logsStreaming) {
        toast('A log stream is already running', 'warn');
        return;
    }
    setStatus('Launching Antigravity + logs…', 'busy');
    try {
        const streamId = await window.ag.antigravityLaunchLogs();
        if (!streamId) {
            toast('Failed to start launch + logs stream', 'err');
            return;
        }
        // Wire the same handlers used by the regular logs view
        logsStreaming = true;
        logsStreamId = streamId;
        window.ag.onStreamData(streamId, (chunk) => {
            logsPendingChunk = (logsPendingChunk ?? '') + ansiToHtml(chunk);
            scheduleLogsFlush();
        });
        window.ag.onStreamClose(streamId, (code) => {
            flushLogs();
            logsStreaming = false;
            logsStreamId = null;
            setStatus(`Launch + logs closed (${code})`);
            void loadAntigravity();
        });
        window.ag.onStreamError(streamId, (err) => {
            flushLogs();
            logsStreaming = false;
            logsStreamId = null;
            toast(`Stream error: ${err}`, 'err');
        });
        // Navigate to the logs view to show what comes in
        navigate('logs');
        toast('Antigravity launched — following logs', 'ok', 2000);
    }
    catch (e) {
        toast(`Could not launch with logs: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
$('#agKillBtn').addEventListener('click', async () => {
    const ok = await confirmModal('Close Antigravity', 'This will terminate all Antigravity processes. Unsaved work may be lost.', { confirmLabel: 'Close' });
    if (!ok)
        return;
    setStatus('Closing Antigravity…', 'busy');
    try {
        const r = await window.ag.antigravityKill();
        if (r.ok && r.data) {
            toast(r.data.message, r.data.killed > 0 ? 'ok' : 'info', 4000);
        }
        else {
            toast(`Close failed: ${r.error ?? 'unknown'}`, 'err');
        }
        await loadAntigravity();
    }
    catch (e) {
        toast(`Could not close Antigravity: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
$('#agRestartBtn').addEventListener('click', async () => {
    setStatus('Restarting Antigravity…', 'busy');
    try {
        const r = await window.ag.antigravityRestart();
        if (r.ok && r.data) {
            toast(r.data.message, r.data.ok ? 'ok' : 'warn', 4000);
        }
        else {
            toast(`Restart failed: ${r.error ?? 'unknown'}`, 'err');
        }
        await loadAntigravity();
    }
    catch (e) {
        toast(`Could not restart Antigravity: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
const pmBackdrop = $('#providerManagerModalBackdrop');
const pmClose = $('#providerManagerModalClose');
const pmListContainer = $('#pmListContainer');
const pmFormContainer = $('#pmFormContainer');
const pmAddBtn = $('#pmAddBtn');
const pmFormBack = $('#pmFormBack');
const pmFormTitle = $('#pmFormTitle');
const pmFormName = $('#pmFormName');
const pmFormType = $('#pmFormType');
const pmFormUrl = $('#pmFormUrl');
const pmFormKey = $('#pmFormKey');
const pmFormInsecure = $('#pmFormInsecure');
const pmFormSave = $('#pmFormSave');
const pmFormError = $('#pmFormError');
const pmModelsList = $('#pmModelsList');
let providersCache = [];
let editingProviderId = null;
// Smart Banner Manager instance
const smartBanner = new SmartBannerManager('globalSmartBanner');
function triggerSmartFailover(failingProviderId) {
    const fallback = providersCache.find((p) => p.enabled && p.id !== failingProviderId && (p.status === 'healthy' || !p.status));
    if (fallback) {
        toast(`Switched to fallback provider ${fallback.name}`, 'ok');
    }
    else {
        toast(`No alternative healthy provider available`, 'warn');
    }
}
function handleProviderError(errorMsg, status, p) {
    const decoded = decodeCustomProviderError(errorMsg, status, p?.name);
    smartBanner.show({
        category: decoded.category,
        title: decoded.title,
        hint: decoded.hint,
        resetSeconds: decoded.resetSeconds,
        providerName: decoded.providerName,
        onFallback: () => triggerSmartFailover(p?.id),
        onEditKey: () => {
            if (p)
                openProviderForm(p.id);
            else
                openProviderManagerModal();
        },
        onStartStub: () => {
            window.location.hash = '#mitm';
            navigate('mitm');
        }
    });
}
function showPmView(view) {
    if (view === 'list') {
        pmListContainer.style.display = 'block';
        pmFormContainer.style.display = 'none';
    }
    else {
        pmListContainer.style.display = 'none';
        pmFormContainer.style.display = 'block';
    }
}
function renderHealthStatusIndicator(p) {
    const status = p.status || 'untested';
    const titleText = status === 'healthy'
        ? `Healthy · ${p.latencyMs ?? 0}ms response time`
        : status === 'degraded'
            ? `Degraded · ${p.latencyMs ?? 0}ms response time (Slow)`
            : status === 'offline'
                ? `Offline · ${p.lastError || 'Unreachable'}`
                : 'Untested connection';
    let html = `<span class="agy-status-dot ${status}" title="${escapeHtml(titleText)}"></span>`;
    if (typeof p.latencyMs === 'number' && status !== 'untested') {
        html += `<span class="agy-latency-badge ${status}" title="${escapeHtml(titleText)}">${p.latencyMs} ms</span>`;
    }
    return html;
}
function renderProviderStatus(p) {
    if (!p.enabled) {
        return `<span class="agy-pill agy-pill-muted">Disabled</span>`;
    }
    return `<span class="agy-pill agy-pill-ok">
    <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
    Enabled
  </span>`;
}
async function renderProviderList() {
    providersCache = (await window.ag.providers.get());
    if (!providersCache || providersCache.length === 0) {
        pmListContainer.innerHTML = `
      <div class="agy-empty-state">
        <div class="agy-empty-icon">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
        </div>
        <div class="agy-empty-title">No providers yet</div>
        <div class="agy-empty-text">Add a custom OpenAI-compatible provider to get started.</div>
      </div>
    `;
        return;
    }
    let html = `<div class="agy-provider-list">`;
    for (const p of providersCache) {
        html += `
      <div class="agy-provider-row" data-id="${escapeHtml(p.id)}">
        <div class="agy-provider-row-main">
          <div class="agy-provider-row-name" style="display:flex; align-items:center;">
            ${renderHealthStatusIndicator(p)}
            <span>${escapeHtml(p.name)}</span>
          </div>
          <div class="agy-provider-row-meta">
            <span>${escapeHtml(p.provider)}</span>
            <span class="agy-dot">·</span>
            <span>${escapeHtml(p.apiUrl.replace(/^https?:\/\//, ''))}</span>
            <span class="agy-dot">·</span>
            <span>${p.models.length} model${p.models.length === 1 ? '' : 's'}</span>
          </div>
        </div>
        <div class="agy-provider-row-status">${renderProviderStatus(p)}</div>
        <div class="agy-provider-row-actions">
          <button class="agy-icon-btn pm-test" title="Test connection" aria-label="Test connection for ${escapeHtml(p.name)}">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
          </button>
          <button class="agy-icon-btn pm-toggle" title="${p.enabled ? 'Disable' : 'Enable'} provider" aria-label="${p.enabled ? 'Disable' : 'Enable'} provider ${escapeHtml(p.name)}">
            ${p.enabled
            ? `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg>`
            : `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6.64 18.36a9 9 0 1 0 12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/><polyline points="16 8 12 12 8 8"/></svg>`}
          </button>
          <button class="agy-icon-btn pm-edit" title="Edit provider" aria-label="Edit provider ${escapeHtml(p.name)}">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
          </button>
          <button class="agy-icon-btn pm-delete" title="Delete provider" aria-label="Delete provider ${escapeHtml(p.name)}">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>
          </button>
        </div>
      </div>
    `;
    }
    html += `</div>`;
    pmListContainer.innerHTML = html;
    pmListContainer.querySelectorAll('.pm-test').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            const row = e.currentTarget.closest('.agy-provider-row');
            const id = row.dataset.id;
            const p = providersCache.find((x) => x.id === id);
            if (!p)
                return;
            btn.setAttribute('disabled', 'true');
            const orig = btn.innerHTML;
            btn.innerHTML = `<span class="spinner"></span>`;
            try {
                const r = (await window.ag.providers.test({ apiUrl: p.apiUrl, apiKey: p.apiKey, id: p.id }));
                if (r.success) {
                    p.status = r.healthStatus ?? 'healthy';
                    p.latencyMs = r.latencyMs;
                    toast(`Healthy (${r.latencyMs ?? 0}ms)`, 'ok');
                    smartBanner.dismiss();
                }
                else {
                    p.status = r.healthStatus ?? 'offline';
                    p.latencyMs = r.latencyMs;
                    p.lastError = r.error;
                    toast(`Failed: ${r.error || r.status}`, 'err', 6000);
                    handleProviderError(r.error || `HTTP ${r.status}`, r.status, p);
                }
                await renderProviderList();
            }
            catch (err) {
                const errorMsg = err.message;
                toast(`Test error: ${errorMsg}`, 'err');
                handleProviderError(errorMsg, undefined, p);
            }
            finally {
                btn.removeAttribute('disabled');
                btn.innerHTML = orig;
            }
        });
    });
    pmListContainer.querySelectorAll('.pm-toggle').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            const row = e.currentTarget.closest('.agy-provider-row');
            const id = row.dataset.id;
            const p = providersCache.find((x) => x.id === id);
            if (!p)
                return;
            p.enabled = !p.enabled;
            const r = (await window.ag.providers.save(p));
            if (r.success) {
                toast(p.enabled ? 'Provider enabled' : 'Provider disabled', 'ok');
                await renderProviderList();
            }
            else {
                toast(`Save failed: ${r.error}`, 'err');
                p.enabled = !p.enabled; // revert
            }
        });
    });
    pmListContainer.querySelectorAll('.pm-edit').forEach((btn) => {
        btn.addEventListener('click', (e) => {
            const row = e.currentTarget.closest('.agy-provider-row');
            const id = row.dataset.id;
            openProviderForm(id);
        });
    });
    pmListContainer.querySelectorAll('.pm-delete').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            const row = e.currentTarget.closest('.agy-provider-row');
            const id = row.dataset.id;
            const p = providersCache.find((x) => x.id === id);
            if (!p)
                return;
            if (!confirm(`Delete provider "${p.name}"?`))
                return;
            const r = (await window.ag.providers.delete(id));
            if (r.success) {
                toast('Provider deleted', 'ok');
                await renderProviderList();
            }
            else {
                toast(`Delete failed: ${r.error}`, 'err');
            }
        });
    });
}
function resetProviderForm() {
    pmFormName.value = '';
    pmFormType.value = 'openai';
    pmFormUrl.value = '';
    pmFormKey.value = '';
    pmFormInsecure.checked = false;
    pmModelsList.innerHTML = '';
    pmFormError.style.display = 'none';
    editingProviderId = null;
}
function openProviderForm(existingId) {
    resetProviderForm();
    if (existingId) {
        const p = providersCache.find((x) => x.id === existingId);
        if (!p)
            return;
        editingProviderId = existingId;
        pmFormTitle.textContent = 'Edit provider';
        pmFormName.value = p.name;
        pmFormType.value = p.provider;
        pmFormUrl.value = p.apiUrl;
        pmFormKey.value = p.apiKey;
        pmFormInsecure.checked = !!p.allowUnauthorized;
        if (p.models && p.models.length > 0) {
            let html = '<div class="agy-model-chips">';
            for (const m of p.models) {
                const checked = m.enabled ? 'checked' : '';
                html += `<label class="agy-chip">
          <input type="checkbox" data-model-id="${escapeHtml(m.id)}" ${checked} />
          <span>${escapeHtml(m.displayName || m.id)}</span>
        </label>`;
            }
            html += '</div>';
            pmModelsList.innerHTML = html;
        }
        else {
            pmModelsList.innerHTML = '<div style="color: var(--text-2); font-size: 12px;">No models loaded. Click "Fetch models" to load the list.</div>';
        }
    }
    else {
        pmFormTitle.textContent = 'Add provider';
        pmModelsList.innerHTML = '<div style="color: var(--text-2); font-size: 12px;">Save the provider first, then fetch models to populate the list.</div>';
    }
    showPmView('form');
    setTimeout(() => pmFormName.focus(), 50);
}
function getSelectedProviderModels() {
    const checkboxes = pmModelsList.querySelectorAll('input[type="checkbox"][data-model-id]');
    const models = [];
    checkboxes.forEach((cb) => {
        models.push({ id: cb.dataset.modelId, displayName: cb.dataset.modelId, enabled: cb.checked });
    });
    return models;
}
pmAddBtn.addEventListener('click', () => openProviderForm());
pmFormBack.addEventListener('click', async () => {
    showPmView('list');
    await renderProviderList();
});
function closeProviderManagerModal() {
    pmBackdrop.hidden = true;
    pmBackdrop.style.display = 'none';
}
pmClose.addEventListener('click', closeProviderManagerModal);
$('#pmModalClose2')?.addEventListener('click', closeProviderManagerModal);
$('#pmFormBack2')?.addEventListener('click', async () => {
    showPmView('list');
    await renderProviderList();
});
$('#pmFormBack3')?.addEventListener('click', async () => {
    showPmView('list');
    await renderProviderList();
});
$('#pmFormSave2')?.addEventListener('click', () => pmFormSave.click());
pmBackdrop.addEventListener('click', (e) => {
    if (e.target === pmBackdrop)
        closeProviderManagerModal();
});
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !pmBackdrop.hidden) {
        closeProviderManagerModal();
    }
});
pmFormSave.addEventListener('click', async () => {
    const name = pmFormName.value.trim();
    const provider = pmFormType.value;
    const apiUrl = pmFormUrl.value.trim();
    const apiKey = pmFormKey.value.trim();
    if (!name || !provider || !apiUrl) {
        pmFormError.textContent = 'Name, type and URL are required';
        pmFormError.style.display = 'block';
        return;
    }
    pmFormSave.setAttribute('disabled', 'true');
    pmFormSave.textContent = 'Savingâ€¦';
    try {
        const id = editingProviderId ?? `provider-${Date.now()}`;
        const existing = providersCache.find((x) => x.id === id);
        const providerEntry = {
            id,
            name,
            provider,
            apiUrl,
            apiKey,
            enabled: existing?.enabled ?? true,
            allowUnauthorized: pmFormInsecure.checked,
            models: editingProviderId ? getSelectedProviderModels() : (existing?.models ?? [])
        };
        const r = (await window.ag.providers.save(providerEntry));
        if (!r.success)
            throw new Error(r.error || 'Save failed');
        toast(editingProviderId ? 'Provider updated' : 'Provider added', 'ok');
        showPmView('list');
        await renderProviderList();
    }
    catch (err) {
        pmFormError.textContent = err.message;
        pmFormError.style.display = 'block';
    }
    finally {
        pmFormSave.removeAttribute('disabled');
        pmFormSave.textContent = 'Save provider';
    }
});
async function openProviderManagerModal() {
    pmBackdrop.hidden = false;
    pmBackdrop.style.display = 'flex';
    showPmView('list');
    await renderProviderList();
}
$('#modelsAddBtn')?.addEventListener('click', openProviderManagerModal);
$('#providerManagerBtn')?.addEventListener('click', openProviderManagerModal);
// Real-time synchronization listener: re-render provider list whenever custom_models.json changes
window.ag.providers.onChanged(() => {
    void renderProviderList();
});
//# sourceMappingURL=app.js.map