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
    antigravity: "Vérifier les statuts d'Antigravity et version",
    mitm: "Vérifier et gérer le MITM et le statut proxy",
    doctor: "Faire un diagnostic (Doctor)",
    patch: "Faire un repair (Réparer)",
    logs: "Afficher et suivre les logs",
    proxy: "Démarrer/arrêter le proxy stub sur 50999",
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
 * Format a byte count as a short, human-readable string (B / KB / MB / GB).
 * Used by the patch preflight modal to display the estimated delta size
 * when the backend exposes `deltaSizeBytes` in its patch status payload.
 */
function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0)
        return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
    const value = bytes / Math.pow(1024, i);
    return `${value.toFixed(value < 10 && i > 0 ? 2 : value < 100 && i > 0 ? 1 : 0)} ${units[i]}`;
}
const KNOWN_ERROR_PATTERNS = [
    {
        // Match MITM-specific listen/EADDR errors on port 443 only.
        // Anchored with proxy/MITM context to avoid false positives on legitimate
        // port-443 traffic elsewhere in the logs.
        pattern: 'MITM proxy unreachable (127.0.0.1:443)',
        hint: 'The local MITM proxy is not reachable. The proxy is mandatory for the patch to work — open the MITM view to start it (HTTP on port 443 + HTTPS on port 8443).',
        action: 'open-mitm-view',
        matcher: (s) => /(?:proxy|mitm|listen).*127\.0\.0\.1\s*:\s*443|EADDRNOTAVAIL.*127\.0\.0\.1.*443|ECONNREFUSED.*127\.0\.0\.1.*443/i.test(s),
    },
    {
        pattern: 'Missing Node module (Cannot find module)',
        hint: 'A dependency expected by the doctor CLI is missing. Run "npm install" in ag-doctor (or use the Repair action if available) and try again.',
        action: 'run-doctor',
        matcher: (s) => /Cannot find module|MODULE_NOT_FOUND|require\.resolve/i.test(s),
    },
    {
        pattern: 'Antigravity crash on launch',
        hint: 'Antigravity did not start cleanly after the patch (or before it). Verify the language_server binary is readable, the backup is intact and try again. If it keeps crashing, restore from backup.',
        action: 'show-retry-toast',
        matcher: (s) => /Antigravity crash|antigravity.*crash(ed)? on launch|crash on startup|process exited unexpectedly/i.test(s),
    },
    {
        pattern: 'Port already in use (EADDRINUSE)',
        hint: 'A local port (e.g. 50999 / 443 / 8443) is already taken by another process. Close the application using that port (often a leftover Antigravity instance) and retry.',
        action: 'run-doctor',
        matcher: (s) => /EADDRINUSE|address already in use|bind:.*already in use|listen.*already in use/i.test(s),
    },
];
function decodeError(stderr, stdout = '') {
    const haystack = `${stderr || ''}\n${stdout || ''}`;
    for (const def of KNOWN_ERROR_PATTERNS) {
        if (def.matcher(haystack)) {
            return {
                matched: true,
                pattern: def.pattern,
                hint: def.hint,
                action: def.action,
            };
        }
    }
    return { matched: false, pattern: '', hint: '', action: 'none' };
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
// Modal
// ─────────────────────────────────────────────────────────────────────────────
const modalBackdrop = $('#modalBackdrop');
const modalTitle = $('#modalTitle');
const modalBody = $('#modalBody');
const modalConfirm = $('#modalConfirm');
const modalCancel = $('#modalCancel');
const modalClose = $('#modalClose');
function confirmModal(title, body, opts) {
    return new Promise((resolve) => {
        modalTitle.textContent = title;
        modalBody.innerHTML = body;
        modalConfirm.textContent = opts?.confirmLabel ?? 'Confirm';
        modalConfirm.className = `btn ${opts?.danger ? 'btn-danger' : opts?.confirmDisabled ? 'btn-muted' : 'btn-primary'}`;
        modalConfirm.disabled = !!opts?.confirmDisabled;
        modalBackdrop.hidden = false;
        const cleanup = (result) => {
            modalBackdrop.hidden = true;
            modalConfirm.disabled = false;
            modalConfirm.removeEventListener('click', onConfirm);
            modalCancel.removeEventListener('click', onCancel);
            modalClose.removeEventListener('click', onCancel);
            modalBackdrop.removeEventListener('click', onBackdrop);
            resolve(result);
        };
        const onConfirm = () => {
            if (modalConfirm.disabled)
                return;
            cleanup(true);
        };
        const onCancel = () => cleanup(false);
        const onBackdrop = (e) => {
            if (e.target === modalBackdrop)
                cleanup(false);
        };
        modalConfirm.addEventListener('click', onConfirm);
        modalCancel.addEventListener('click', onCancel);
        modalClose.addEventListener('click', onCancel);
        modalBackdrop.addEventListener('click', onBackdrop);
    });
}
// ─────────────────────────────────────────────────────────────────────────────
// Navigation
// ─────────────────────────────────────────────────────────────────────────────
const navItems = $$('.nav-item');
const activityItems = $$('.activity-item');
const views = $$('.view');
const ACTIVITY_TO_VIEW = {
    explorer: 'dashboard',
    search: 'doctor',
    doctor: 'doctor',
    models: 'models',
    logs: 'logs',
    mitm: 'mitm',
    settings: 'settings',
};
function setActivity(name) {
    activityItems.forEach((a) => a.classList.toggle('active', a.dataset.activity === name));
}
function navigate(viewName) {
    navItems.forEach((n) => n.classList.toggle('active', n.dataset.view === viewName));
    views.forEach((v) => v.classList.toggle('active', v.id === `view-${viewName}`));
    // Sync activity bar with current view
    const activityMap = {
        dashboard: 'explorer', doctor: 'doctor', models: 'models',
        logs: 'logs', mitm: 'mitm', settings: 'settings',
        patch: 'doctor', info: 'explorer',
    };
    setActivity(activityMap[viewName] || 'explorer');
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
activityItems.forEach((a) => a.addEventListener('click', () => {
    const target = ACTIVITY_TO_VIEW[a.dataset.activity || ''];
    if (target)
        navigate(target);
}));
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
    const target = e.target;
    if (target.classList.contains('health-expand')) {
        target.closest('.health-item')?.classList.toggle('expanded');
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
        <p>Click <strong>Run doctor</strong> to start a diagnostic.</p>
      </div>`;
        return;
    }
    // Build via DocumentFragment: parse once, insert once (no double innerHTML parse)
    const html = results
        .map((r, i) => {
        const icon = iconForStatus(r.status);
        const detailsHtml = r.details
            ? `<div class="health-details">${escapeHtml(r.details)}</div><div class="health-expand">Show details</div>`
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
        setDashHero('err', `${results.filter((r) => r.status === 'error').length} error(s)`, `<strong>${total}</strong> checks · <strong>${ok}</strong> passed · review issues below`);
    }
    else if (hasWarn) {
        setDashHero('warn', `${results.filter((r) => r.status === 'warn').length} warning(s)`, `<strong>${total}</strong> checks · <strong>${ok}</strong> passed · some warnings detected`);
    }
    else {
        setDashHero('ok', 'All systems operational', `<strong>${total}</strong> checks passed · last run ${new Date().toLocaleTimeString()}`);
    }
    dashHeroTitle.textContent = 'ag-doctor';
}
async function runDoctor() {
    setStatus('Running diagnostic…', 'busy');
    $('#runDoctorBtn')?.setAttribute('disabled', 'true');
    $('#refreshBtn')?.setAttribute('disabled', 'true');
    $('#quickRunBtn')?.setAttribute('disabled', 'true');
    setObjective('doctor', 'pending', 'Diagnostic en cours…');
    setDashHero('busy', 'Running diagnostic…', 'Scanning Antigravity, MITM, patch and models…');
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
                void window.ag.notify('ag-doctor · new issue', `${newErrors.length} new error(s): ${titles}`);
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
        toast(`Diagnostic complete · ${data.length} checks`, 'ok');
        setStatus('Ready');
    }
    catch (e) {
        toast(`Doctor failed: ${e.message}`, 'err', 5000);
        setStatus('Error', 'err');
        setObjective('doctor', 'error', 'Diagnostic échoué');
        void window.ag.trayStatus('err');
    }
    finally {
        $('#runDoctorBtn')?.removeAttribute('disabled');
        $('#refreshBtn')?.removeAttribute('disabled');
        $('#quickRunBtn')?.removeAttribute('disabled');
    }
}
function resultStatusToObjective(status) {
    return status === 'info' ? 'ok' : status;
}
function updateObjectives(results) {
    const hasError = results.some((r) => r.status === 'error');
    const hasWarn = results.some((r) => r.status === 'warn');
    setObjective('doctor', hasError ? 'error' : hasWarn ? 'warn' : 'ok', hasError ? 'Problèmes détectés' : hasWarn ? 'Avertissements' : 'Diagnostic OK');
    const antigravity = results.find((r) => r.id === 'antigravity' || r.id === 'version' || r.id === 'install');
    setObjective('antigravity', antigravity ? resultStatusToObjective(antigravity.status) : 'pending', antigravity?.message);
    const mitm = results.find((r) => r.id === 'mitm' || r.id === 'proxy' || r.id === 'ca');
    setObjective('mitm', mitm ? resultStatusToObjective(mitm.status) : 'pending', mitm?.message);
    const patch = results.find((r) => r.id === 'patch');
    setObjective('patch', patch ? resultStatusToObjective(patch.status) : 'pending', patch?.message);
    const logs = results.find((r) => r.id === 'logs');
    setObjective('logs', logs ? resultStatusToObjective(logs.status) : 'ok', logs?.message ?? 'Logs disponibles');
}
$('#runDoctorBtn').addEventListener('click', () => void runDoctor());
$('#quickRunBtn').addEventListener('click', () => void runDoctor());
$('#refreshBtn').addEventListener('click', () => void runDoctor());
$('#repairBtn').addEventListener('click', () => void runRepair());
// Fix All: full auto-repair with admin elevation (UAC prompt will appear)
$('#fixAllBtn')?.addEventListener('click', () => void runFixAll());
// Start Stub: emergency proxy stub on port 50999 (no admin needed)
$('#startStubBtn')?.addEventListener('click', () => void runStartStub());
async function runFixAll() {
    const ok = await confirmModal('Fix All — Réparation complète', 'Cela va lancer <code>ag-doctor repair --yes --auto-elevate</code> avec élévation admin (UAC). ' +
        'Toutes les actions de réparation seront effectuées : patch, port 50999, proxy, CA cert.', { confirmLabel: 'Fix All', danger: true });
    if (!ok)
        return;
    setStatus('Fix All — élévation admin…', 'busy');
    $('#fixAllBtn')?.setAttribute('disabled', 'true');
    try {
        // Use the existing IPC handler that spawns the elevated repair script
        const r = await window.ag.repairRun();
        if (r?.ok) {
            toast('Fix All completed successfully', 'ok', 5000);
            setObjective('patch', 'ok', 'Réparation complète effectuée');
        }
        else {
            toast(`Fix All failed: ${r?.error ?? 'unknown'}`, 'err', 6000);
            setObjective('patch', 'error', 'Échec de la réparation complète');
        }
        setStatus('Refreshing diagnostic…', 'busy');
        await runDoctor();
    }
    catch (e) {
        toast(`Fix All error: ${e.message}`, 'err');
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
            toast(`Proxy stub started (pid=${r.pid ?? '?'})`, 'ok', 5000);
            setObjective('proxy', 'ok', 'Stub proxy actif sur 50999');
        }
        else {
            toast(`Stub failed: ${r?.error ?? 'unknown'}`, 'err', 6000);
            setObjective('proxy', 'error', 'Échec du stub');
        }
    }
    catch (e) {
        toast(`Stub error: ${e.message}`, 'err');
    }
    finally {
        $('#startStubBtn')?.removeAttribute('disabled');
        setStatus('Idle', 'ready');
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
    status.textContent = detail ?? (state === 'ok' ? 'Actif' : state === 'pending' ? 'En attente' : state === 'warn' ? 'Avertissement' : 'Erreur');
}
async function runRepair() {
    const ok = await confirmModal('Réparer Antigravity', 'Cela exécutera <code>ag-doctor repair --yes</code> pour tenter de réparer automatiquement les problèmes détectés.', { confirmLabel: 'Repair' });
    if (!ok)
        return;
    setStatus('Repairing…', 'busy');
    $('#repairBtn')?.setAttribute('disabled', 'true');
    try {
        const r = await window.ag.run(['repair', '--yes']);
        if (r.code === 0) {
            toast('Repair completed successfully', 'ok', 5000);
            setObjective('patch', 'ok', 'Réparation effectuée');
        }
        else {
            toast(`Repair failed: ${r.stderr || r.stdout}`, 'err', 6000);
            setObjective('patch', 'error', 'Échec de la réparation');
        }
        setStatus('Refreshing diagnostic…', 'busy');
        await runDoctor();
    }
    catch (e) {
        toast(`Repair error: ${e.message}`, 'err');
        setStatus('Error', 'err');
        setObjective('patch', 'error', 'Erreur');
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
    setStatus('Running diagnostic…', 'busy');
    doctorOutput.textContent = '$ ag-doctor doctor\n';
    try {
        const result = await window.ag.run(['doctor']);
        doctorTpl.innerHTML = ansiToHtml(result.stdout || result.stderr);
        doctorOutput.replaceChildren(doctorTpl.content);
        setStatus('Ready');
    }
    catch (e) {
        doctorOutput.textContent = `Error: ${e.message}`;
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
        toast(`Failed: ${e.message}`, 'err');
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
          <p>No models configured. Click <strong>Add model</strong> to create one.</p>
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
                <button class="btn btn-ghost btn-sm" data-action="test" data-name="${escapeHtml(m.name)}">Test</button>
                <button class="btn btn-ghost btn-sm" data-action="reveal" data-url="${escapeHtml(m.apiUrl)}">Open URL</button>
                <button class="btn btn-danger btn-sm" data-action="remove" data-name="${escapeHtml(m.name)}">Delete</button>
              </div>
            </div>`;
            })
                .join('');
            modelsTpl.innerHTML = html;
            modelsList.replaceChildren(modelsTpl.content);
        }
        setStatus(`${data.models.length} model(s)`);
    }
    catch (e) {
        modelsList.innerHTML = `<div class="empty-state"><p>Error: ${escapeHtml(e.message)}</p></div>`;
        setStatus('Error', 'err');
    }
    finally {
        hideSkeleton(modelsList);
    }
}
// Event delegation for model-card actions (one listener, not N)
modelsList.addEventListener('click', (e) => {
    const target = e.target;
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
            toast(r.stdout.includes('✓') || r.code === 0 ? `${name} reachable` : `${name} failed`, r.code === 0 ? 'ok' : 'err');
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
        const ok = await confirmModal('Delete model', `Are you sure you want to delete <strong>${escapeHtml(name)}</strong>?`, { confirmLabel: 'Delete', danger: true });
        if (!ok)
            return;
        setStatus('Removing…', 'busy');
        const r = await window.ag.run(['models', 'remove', name, '--yes']);
        if (r.code === 0) {
            toast(`Removed ${name}`, 'ok');
            void loadModels();
        }
        else {
            toast(`Failed: ${r.stderr || r.stdout}`, 'err');
        }
        setStatus('Ready');
    }
}
$('#modelsTestBtn').addEventListener('click', async () => {
    setStatus('Testing all models…', 'busy');
    try {
        const r = await window.ag.run(['models', 'test']);
        toast(r.code === 0 ? 'All models reachable' : 'Some models failed', r.code === 0 ? 'ok' : 'warn', 5000);
        setStatus('Ready');
    }
    catch (e) {
        toast(`Test failed: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
// Add Model Modal elements
const addModelModalBackdrop = $('#addModelModalBackdrop');
const addModelModalClose = $('#addModelModalClose');
const addModelModalCancel = $('#addModelModalCancel');
const addModelModalBack = $('#addModelModalBack');
const addModelModalFetch = $('#addModelModalFetch');
const addModelModalSave = $('#addModelModalSave');
const addStep1 = $('#addStep1');
const addStep2 = $('#addStep2');
const addStep1Indicator = $('#addStep1Indicator');
const addStep2Indicator = $('#addStep2Indicator');
const addStep1Badge = $('#addStep1Badge');
const addStep2Badge = $('#addStep2Badge');
const modelProviderTypeInput = $('#modelProviderType');
const modelApiUrlInput = $('#modelApiUrl');
const modelApiKeyInput = $('#modelApiKey');
const modelAllowUnauthorizedInput = $('#modelAllowUnauthorized');
const modelDisplayNameSuffixInput = $('#modelDisplayNameSuffix');
const fetchedModelsList = $('#fetchedModelsList');
const fetchModelsError = $('#fetchModelsError');
const saveModelsError = $('#saveModelsError');
const refetchModelsBtn = $('#refetchModelsBtn');
let fetchedModels = [];
let currentStep = 1;
function setAddStep(step) {
    currentStep = step;
    if (step === 1) {
        addStep1.style.display = 'block';
        addStep2.style.display = 'none';
        addModelModalBack.style.display = 'none';
        addModelModalFetch.style.display = 'inline-flex';
        addModelModalSave.style.display = 'none';
        addStep1Indicator.style.opacity = '1';
        addStep2Indicator.style.opacity = '0.5';
        addStep1Badge.style.backgroundColor = '#3b82f6';
        addStep1Badge.style.color = '#ffffff';
        addStep2Badge.style.backgroundColor = '#27272a';
        addStep2Badge.style.color = '#a1a1aa';
    }
    else {
        addStep1.style.display = 'none';
        addStep2.style.display = 'block';
        addModelModalBack.style.display = 'inline-flex';
        addModelModalFetch.style.display = 'none';
        addModelModalSave.style.display = 'inline-flex';
        addStep1Indicator.style.opacity = '0.5';
        addStep2Indicator.style.opacity = '1';
        addStep1Badge.style.backgroundColor = '#27272a';
        addStep1Badge.style.color = '#a1a1aa';
        addStep2Badge.style.backgroundColor = '#3b82f6';
        addStep2Badge.style.color = '#ffffff';
    }
}
function resetAddModelModal() {
    modelProviderTypeInput.value = 'openai';
    modelApiUrlInput.value = '';
    modelApiKeyInput.value = '';
    modelAllowUnauthorizedInput.checked = false;
    modelDisplayNameSuffixInput.value = '';
    fetchedModels = [];
    fetchedModelsList.innerHTML = `
    <div style="text-align: center; padding: 24px; color: #a1a1aa; font-size: 13px;">
      Fetch models to see available options.
    </div>
  `;
    fetchModelsError.style.display = 'none';
    saveModelsError.style.display = 'none';
    setAddStep(1);
}
function openAddModelModal() {
    resetAddModelModal();
    addModelModalBackdrop.hidden = false;
    addModelModalBackdrop.style.display = 'grid';
    setTimeout(() => modelApiUrlInput.focus(), 50);
}
function closeAddModelModal() {
    addModelModalBackdrop.hidden = true;
    addModelModalBackdrop.style.display = 'none';
}
$('#modelsAddBtn').addEventListener('click', openAddModelModal);
$('#dashboardAddModelBtn').addEventListener('click', openAddModelModal);
addModelModalClose.addEventListener('click', closeAddModelModal);
addModelModalCancel.addEventListener('click', closeAddModelModal);
addModelModalBackdrop.addEventListener('click', (e) => {
    if (e.target === addModelModalBackdrop)
        closeAddModelModal();
});
// Escape key closes the modal
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !addModelModalBackdrop.hidden) {
        closeAddModelModal();
    }
});
// Safety: ensure modal is hidden on script load
addModelModalBackdrop.hidden = true;
addModelModalBackdrop.style.display = 'none';
function renderFetchedModels() {
    if (fetchedModels.length === 0) {
        fetchedModelsList.innerHTML = `
      <div style="text-align: center; padding: 24px; color: #a1a1aa; font-size: 13px;">
        No models found at this endpoint.
      </div>
    `;
        return;
    }
    const allChecked = fetchedModels.length > 0;
    let html = `
    <div style="display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-bottom: 1px solid #27272a; margin-bottom: 4px;">
      <input type="checkbox" id="selectAllModels" style="width: 16px; height: 16px; accent-color: #3b82f6; cursor: pointer;" ${allChecked ? 'checked' : ''} />
      <label for="selectAllModels" style="margin: 0; font-size: 12px; color: #a1a1aa; cursor: pointer;">Select all</label>
    </div>
  `;
    for (const model of fetchedModels) {
        const supportsImages = model.inputModalities?.includes('image') || false;
        const supportsVideo = model.inputModalities?.includes('video') || false;
        const modalityBadges = [];
        if (supportsImages)
            modalityBadges.push(`<span style="font-size: 10px; padding: 2px 6px; border-radius: 4px; background-color: #22c55e18; color: #22c55e;">image</span>`);
        if (supportsVideo)
            modalityBadges.push(`<span style="font-size: 10px; padding: 2px 6px; border-radius: 4px; background-color: #a855f718; color: #a855f7;">video</span>`);
        html += `
      <div style="display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: 6px; transition: background-color 0.15s ease;" class="fetched-model-row" data-model-id="${escapeHtml(model.id)}">
        <input type="checkbox" class="model-select-checkbox" value="${escapeHtml(model.id)}" checked style="width: 16px; height: 16px; accent-color: #3b82f6; cursor: pointer; flex-shrink: 0;" />
        <div style="flex: 1; min-width: 0;">
          <div style="font-size: 13px; color: #f4f4f5; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(model.id)}</div>
          ${model.name !== model.id ? `<div style="font-size: 11px; color: #a1a1aa; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(model.name)}</div>` : ''}
        </div>
        <div style="display: flex; gap: 4px; flex-shrink: 0;">${modalityBadges.join('')}</div>
      </div>
    `;
    }
    fetchedModelsList.innerHTML = html;
    const selectAll = $('#selectAllModels');
    selectAll?.addEventListener('change', () => {
        document.querySelectorAll('.model-select-checkbox').forEach((cb) => {
            cb.checked = selectAll.checked;
        });
    });
}
async function fetchModels() {
    const provider = modelProviderTypeInput.value;
    const url = modelApiUrlInput.value.trim();
    const key = modelApiKeyInput.value.trim();
    const allowUnauthorized = modelAllowUnauthorizedInput.checked;
    if (!url) {
        fetchModelsError.textContent = 'API URL is required';
        fetchModelsError.style.display = 'block';
        modelApiUrlInput.focus();
        return;
    }
    addModelModalFetch.setAttribute('disabled', 'true');
    addModelModalFetch.textContent = 'Fetching…';
    fetchModelsError.style.display = 'none';
    setStatus('Fetching models…', 'busy');
    try {
        const args = [
            'models',
            'fetch',
            '--provider', provider,
            '--url', url,
            '--json',
        ];
        if (key) {
            args.push('--key', key);
        }
        if (allowUnauthorized) {
            args.push('--allow-unauthorized');
        }
        const r = await window.ag.run(args);
        if (r.code !== 0) {
            let msg = r.stderr || r.stdout || 'Failed to fetch models';
            try {
                const parsed = JSON.parse(msg);
                if (parsed.error)
                    msg = parsed.error;
            }
            catch {
                // keep raw msg
            }
            fetchModelsError.textContent = msg;
            fetchModelsError.style.display = 'block';
            setStatus('Ready');
            return;
        }
        const result = JSON.parse(r.stdout);
        if (!result.success) {
            fetchModelsError.textContent = result.error || 'Failed to fetch models';
            fetchModelsError.style.display = 'block';
            setStatus('Ready');
            return;
        }
        fetchedModels = result.models || [];
        renderFetchedModels();
        setAddStep(2);
        setStatus('Ready');
    }
    catch (e) {
        fetchModelsError.textContent = `Error: ${e.message}`;
        fetchModelsError.style.display = 'block';
        setStatus('Error', 'err');
    }
    finally {
        addModelModalFetch.removeAttribute('disabled');
        addModelModalFetch.textContent = 'Fetch Models';
    }
}
addModelModalFetch.addEventListener('click', fetchModels);
refetchModelsBtn.addEventListener('click', fetchModels);
addModelModalBack.addEventListener('click', () => setAddStep(1));
addModelModalSave.addEventListener('click', async () => {
    const selected = Array.from(document.querySelectorAll('.model-select-checkbox:checked')).map((cb) => cb.value);
    if (selected.length === 0) {
        saveModelsError.textContent = 'Please select at least one model';
        saveModelsError.style.display = 'block';
        return;
    }
    const provider = modelProviderTypeInput.value;
    const url = modelApiUrlInput.value.trim();
    const key = modelApiKeyInput.value.trim();
    const suffix = modelDisplayNameSuffixInput.value.trim();
    addModelModalSave.setAttribute('disabled', 'true');
    addModelModalSave.textContent = 'Adding…';
    saveModelsError.style.display = 'none';
    setStatus(`Adding ${selected.length} model(s)…`, 'busy');
    let added = 0;
    let failed = 0;
    const errors = [];
    for (const modelId of selected) {
        const name = `models/${modelId}`;
        const display = suffix ? `${modelId} (${suffix})` : modelId;
        const args = [
            'models',
            'add',
            '--provider', provider,
            '--name', name,
            '--external', modelId,
            '--url', url,
            '--key', key || '',
            '--display', display,
            '--yes'
        ];
        try {
            const r = await window.ag.run(args);
            if (r.code === 0) {
                added++;
            }
            else {
                failed++;
                errors.push(`${modelId}: ${r.stderr || r.stdout}`);
            }
        }
        catch (e) {
            failed++;
            errors.push(`${modelId}: ${e.message}`);
        }
    }
    addModelModalSave.removeAttribute('disabled');
    addModelModalSave.textContent = 'Add Selected Models';
    if (failed === 0) {
        toast(`Successfully added ${added} model(s)`, 'ok');
        closeAddModelModal();
        void loadModels();
    }
    else {
        saveModelsError.textContent = `Added ${added}, failed ${failed}. ${errors.slice(0, 3).join('; ')}`;
        saveModelsError.style.display = 'block';
        toast(`Added ${added} model(s), ${failed} failed`, 'warn', 6000);
        setStatus('Ready');
        if (added > 0)
            void loadModels();
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
             <div class="patch-banner-text">System trusts the local MITM CA.</div>
           </div>
         </div>`
                : `<div class="patch-banner warn">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">${s.ca.isExpired ? 'CA certificate expired' : 'CA certificate not installed'}</div>
             <div class="patch-banner-text">${s.ca.isExpired ? 'The certificate has expired. Use Repair All to regenerate it.' : 'Install the CA to avoid TLS errors in intercepted applications.'}</div>
           </div>
         </div>`;
            const proxyBanner = s.proxy.redirected
                ? `<div class="patch-banner ok">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">System proxy active</div>
             <div class="patch-banner-text">Traffic is redirected to ${escapeHtml(s.proxy.host ?? 'localhost')}:${s.proxy.port ?? '—'}.</div>
           </div>
         </div>`
                : `<div class="patch-banner warn">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">System proxy inactive</div>
             <div class="patch-banner-text">Toggle Proxy ON to start redirecting traffic.</div>
           </div>
         </div>`;
            const interceptionBanner = s.interception.reachable
                ? `<div class="patch-banner ok">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">Interception reachable</div>
             <div class="patch-banner-text">The proxy is listening and responding.</div>
           </div>
         </div>`
                : `<div class="patch-banner err">
           <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
           <div class="patch-banner-body">
             <div class="patch-banner-title">Interception unreachable</div>
             <div class="patch-banner-text">The proxy does not appear to be listening.</div>
           </div>
         </div>`;
            mitmTpl.innerHTML = `
      <div class="mitm-grid">
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>CA Certificate</h3><span class="badge ${s.ca.installed ? 'ok' : 'warn'}">${s.ca.installed ? 'installed' : 'not installed'}</span></div>
          <div class="mitm-card-body">
            <div class="patch-row"><div class="patch-row-label">Generated</div><div class="patch-row-value ${s.ca.generated ? 'ok' : ''}">${s.ca.generated ? 'yes' : 'no'}</div></div>
            <div class="patch-row"><div class="patch-row-label">Expires</div><div class="patch-row-value ${s.ca.isExpired ? 'err' : ''}">${escapeHtml(s.ca.expiresAt ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Path</div><div class="patch-row-value">${escapeHtml(s.ca.path ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Fingerprint</div><div class="patch-row-value">${escapeHtml(s.ca.fingerprint ?? '—')}</div></div>
          </div>
          ${caBanner}
        </div>
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>System Proxy</h3><span class="badge ${s.proxy.redirected ? 'ok' : 'warn'}">${s.proxy.redirected ? 'redirected' : 'off'}</span></div>
          <div class="mitm-card-body">
            <div class="patch-row"><div class="patch-row-label">Host</div><div class="patch-row-value">${escapeHtml(s.proxy.host ?? '—')}</div></div>
            <div class="patch-row"><div class="patch-row-label">Port</div><div class="patch-row-value">${s.proxy.port ?? '—'}</div></div>
          </div>
          ${proxyBanner}
        </div>
        <div class="mitm-card">
          <div class="mitm-card-header"><h3>Interception Status</h3><span class="badge ${s.interception.reachable ? 'ok' : 'err'}">${s.interception.reachable ? 'reachable' : 'unreachable'}</span></div>
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
          Repair All (Requires Admin)
        </button>
      </div>
      ` : ''}`;
            mitmStatusEl.replaceChildren(mitmTpl.content);
            const repairBtn = document.getElementById('repair-all-btn');
            if (repairBtn) {
                repairBtn.addEventListener('click', async () => {
                    repairBtn.setAttribute('disabled', 'true');
                    repairBtn.innerHTML = 'Repairing... Please check UAC prompt.';
                    setStatus('Repairing MITM...', 'busy');
                    try {
                        const res = await window.ag.repairRun();
                        if (res.ok) {
                            toast('✅ Repair script completed successfully.', 'ok', 3000);
                            // Auto-start the proxy server after successful repair
                            console.log('[MITM] Auto-starting proxy server after repair...');
                            const startResult = await window.ag.proxyStart();
                            if (startResult.ok) {
                                toast('✅ Proxy server started automatically', 'ok', 3000);
                            }
                            else {
                                toast(`⚠️ Repair succeeded but proxy server failed to start: ${startResult.message}`, 'warn', 6000);
                            }
                        }
                        else {
                            toast('❌ Repair failed: ' + res.error, 'err', 6000);
                        }
                    }
                    catch (err) {
                        toast('❌ Repair IPC error: ' + err.message, 'err', 6000);
                    }
                    finally {
                        void loadMitmStatus();
                    }
                });
            }
            setStatus('Ready');
        }
        catch (e) {
            mitmStatusEl.innerHTML = `<div class="empty-state"><p>Error: ${escapeHtml(e.message)}</p></div>`;
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
            // Enhanced error message with diagnostic hints
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            const operation = args.slice(1).join(' ');
            // Check for common failure patterns
            if (errorMsg.toLowerCase().includes('uac') || errorMsg.toLowerCase().includes('cancelled')) {
                toast(`❌ ${operation} failed: UAC prompt was declined. Please click "Yes" when prompted.`, 'err', 8000);
            }
            else if (errorMsg.toLowerCase().includes('access denied') || r.code === 5) {
                toast(`❌ ${operation} failed: Access denied. Try running as Administrator.`, 'err', 8000);
            }
            else if (errorMsg.toLowerCase().includes('not found')) {
                toast(`❌ ${operation} failed: Required system tool not found. Check your PATH.`, 'err', 8000);
            }
            else {
                toast(`❌ ${operation} failed: ${errorMsg.substring(0, 150)}`, 'err', 8000);
            }
            console.error(`[MITM Action Failed]`, { args, code: r.code, stderr: r.stderr, stdout: r.stdout });
            setStatus('Error', 'err');
        }
    }
    catch (e) {
        const operation = args.slice(1).join(' ');
        toast(`❌ ${operation} error: ${e.message}`, 'err', 8000);
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
    const pre = await maybeUacPreStatus('install CA');
    void mitmAction(['mitm', 'install', '--yes'], 'CA installed', true, pre);
});
$('#mitmUninstallBtn').addEventListener('click', async () => {
    const pre = await maybeUacPreStatus('uninstall CA');
    void mitmAction(['mitm', 'uninstall', '--yes'], 'CA uninstalled', true, pre);
});
$('#mitmProxyOnBtn').addEventListener('click', async () => {
    setStatus('Enabling proxy...', 'busy');
    try {
        // Step 1: Start the proxy server
        console.log('[MITM] Starting proxy server...');
        const startResult = await window.ag.proxyStart();
        console.log('[MITM] Proxy start result:', startResult);
        if (!startResult.ok) {
            const decoded = decodeError(startResult.message ?? '', '');
            if (decoded.matched) {
                toast(`❌ Failed to start proxy server — ${decoded.pattern}`, 'err', 8000);
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`❌ Failed to start proxy server: ${startResult.message}`, 'err', 8000);
            }
            setStatus('Error', 'err');
            return;
        }
        toast(`✅ Proxy server started (PID: ${startResult.pid})`, 'ok', 3000);
        // Step 2: Configure Windows to use the proxy
        const pre = await maybeUacPreStatus('enable proxy');
        setStatus(pre, 'busy');
        const r = await window.ag.run(['mitm', 'proxy-on']);
        if (r.code === 0) {
            toast('✅ Proxy enabled and running', 'ok', 5000);
            void loadMitmStatus();
        }
        else {
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            toast(`❌ Failed to configure proxy: ${errorMsg}`, 'err', 8000);
            setStatus('Error', 'err');
            // Try to stop the proxy server since configuration failed
            await window.ag.proxyStop();
        }
    }
    catch (e) {
        toast(`❌ Proxy enable error: ${e.message}`, 'err', 8000);
        console.error(`[MITM] Proxy enable exception:`, e);
        setStatus('Error', 'err');
    }
});
$('#mitmProxyOffBtn').addEventListener('click', async () => {
    setStatus('Disabling proxy...', 'busy');
    try {
        // Step 1: Disable Windows proxy configuration
        const pre = await maybeUacPreStatus('disable proxy');
        setStatus(pre, 'busy');
        const r = await window.ag.run(['mitm', 'proxy-off']);
        if (r.code === 0) {
            toast('✅ Proxy disabled', 'ok', 3000);
        }
        else {
            const errorMsg = r.stderr || r.stdout || 'Unknown error';
            toast(`⚠️ Proxy disable warning: ${errorMsg}`, 'warn', 5000);
        }
        // Step 2: Stop the proxy server (even if config failed)
        console.log('[MITM] Stopping proxy server...');
        const stopResult = await window.ag.proxyStop();
        console.log('[MITM] Proxy stop result:', stopResult);
        if (stopResult.ok) {
            toast('✅ Proxy server stopped', 'ok', 3000);
        }
        else {
            const decoded = decodeError(stopResult.message ?? '', '');
            if (decoded.matched) {
                toast(`⚠️ Failed to stop proxy server — ${decoded.pattern}`, 'warn', 5000);
                toast(decoded.hint, 'warn', 8000);
                runErrorAction(decoded.action);
            }
            else {
                toast(`⚠️ Failed to stop proxy server: ${stopResult.message}`, 'warn', 5000);
            }
        }
        void loadMitmStatus();
    }
    catch (e) {
        toast(`❌ Proxy disable error: ${e.message}`, 'err', 8000);
        console.error(`[MITM] Proxy disable exception:`, e);
        setStatus('Error', 'err');
    }
});
$('#mitmExportCaBtn').addEventListener('click', () => void mitmAction(['mitm', 'export-ca'], 'CA exported'));
// ─────────────────────────────────────────────────────────────────────────────
// Patch view
// ─────────────────────────────────────────────────────────────────────────────
const patchStatusEl = $('#patchStatus');
// Reusable template for patch status — avoids creating a new <template> each load
const patchTpl = document.createElement('template');
async function loadPatchStatus() {
    return guardLoad('patch', async () => {
        setStatus('Loading patch status…', 'busy');
        showSkeleton(patchStatusEl, 'lines', 5);
        try {
            const r = await withTimeout(window.ag.run(['patch', 'status', '--json']), 12_000, 'patch status');
            const s = JSON.parse(r.stdout);
            const banner = s.applied
                ? `<div class="patch-banner ok">
             <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
             <div class="patch-banner-body">
               <div class="patch-banner-title">Patch is active</div>
               <div class="patch-banner-text">language_server is redirected to the local proxy.</div>
             </div>
           </div>`
                : s.exists
                    ? `<div class="patch-banner warn">
               <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
               <div class="patch-banner-body">
                 <div class="patch-banner-title">Patch is NOT applied</div>
                 <div class="patch-banner-text">Custom models will not appear in the chat dropdown until the patch is applied.</div>
               </div>
             </div>`
                    : `<div class="patch-banner err">
               <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
               <div class="patch-banner-body">
                 <div class="patch-banner-title">Binary not found</div>
                 <div class="patch-banner-text">Could not locate language_server binary.</div>
               </div>
             </div>`;
            patchTpl.innerHTML = `
      ${banner}
      <div class="patch-row">
        <div class="patch-row-label">Antigravity Version</div>
        <div class="patch-row-value">${escapeHtml(s.antigravityVersion ?? 'unknown')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Binary path</div>
        <div class="patch-row-value">${escapeHtml(s.binaryPath ?? '—')}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Exists</div>
        <div class="patch-row-value ${s.exists ? 'ok' : 'err'}">${s.exists ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Applied</div>
        <div class="patch-row-value ${s.applied ? 'ok' : 'warn'}">${s.applied ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Backup</div>
        <div class="patch-row-value ${s.backupExists ? 'ok' : ''}">${s.backupExists ? 'yes' : 'no'}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Compatible</div>
        <div class="patch-row-value ${s.compatible ? 'ok' : 'warn'}">${s.compatible ? 'yes' : 'no'}</div>
      </div>
      ${s.recommendedPatch ? `
      <div class="patch-row">
        <div class="patch-row-label">Version Range</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.versionRange)}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Original URL</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.originalUrl)}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Patched URL</div>
        <div class="patch-row-value">${escapeHtml(s.recommendedPatch.patchedUrl)}</div>
      </div>` : ''}
      ${s.warningMessage ? `
      <div class="patch-row">
        <div class="patch-row-label">Warning</div>
        <div class="patch-row-value warn">${escapeHtml(s.warningMessage)}</div>
      </div>` : ''}`;
            patchStatusEl.replaceChildren(patchTpl.content);
            setStatus('Ready');
        }
        catch (e) {
            patchStatusEl.innerHTML = `<div class="empty-state"><p>Error: ${escapeHtml(e.message)}</p></div>`;
        }
        finally {
            hideSkeleton(patchStatusEl);
        }
    });
}
$('#patchApplyBtn').addEventListener('click', async () => {
    // P1.3 (subset) — Pré-validation delta size avant d'ouvrir la confirmation.
    // On récupère le statut patch actuel et on valide l'état du binaire
    // (existence, compatibilité, présence d'un backup, patch recommandé connu)
    // AVANT de risquer une modification destructive. C'est l'équivalent côté UI
    // d'un "delta size check" : on s'assure que le delta (backup → binaire
    // patché) est dans un état cohérent avant de l'appliquer.
    let preflight = null;
    try {
        setStatus('Preflight check…', 'busy');
        const r = await withTimeout(window.ag.run(['patch', 'status', '--json']), 12_000, 'patch status');
        preflight = JSON.parse(r.stdout);
    }
    catch (e) {
        setStatus('Ready');
        toast(`❌ Preflight failed: cannot read patch status (${e.message})`, 'err', 6000);
        return;
    }
    if (!preflight.exists) {
        setStatus('Ready');
        toast('❌ Preflight failed: language_server binary not found. Nothing to patch.', 'err', 6000);
        return;
    }
    if (!preflight.compatible) {
        setStatus('Ready');
        toast('❌ Preflight failed: Antigravity version is not compatible with the known patch.', 'err', 6000);
        return;
    }
    if (!preflight.recommendedPatch) {
        setStatus('Ready');
        toast('❌ Preflight failed: no recommended patch available for this version.', 'err', 6000);
        return;
    }
    if (preflight.applied) {
        setStatus('Ready');
        toast('⚠️ Patch is already applied. Use Restore first if you want to re-apply.', 'warn', 5000);
        return;
    }
    if (!preflight.backupExists) {
        // Non-bloquant : on prévient l'utilisateur mais on laisse confirmer
        console.warn('[patch] No backup found — applying patch will not be reversible');
    }
    // Construit le détail affiché dans la modale (inclut la "taille" du delta
    // quand le backend la renseigne via le champ optionnel deltaSizeBytes).
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
            const icon = c.status === 'ok' ? '✅' : '❌';
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
        toast('❌ Asar validation failed (verdict=block). Patch cannot be applied — see preflight modal.', 'err', 8000);
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
        toast(`Error: ${e.message}`, 'err');
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
        toast(`Error: ${e.message}`, 'err');
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
// Streaming buffer: chunks are accumulated and flushed once per animation frame
// to avoid layout thrashing when many small chunks arrive.
let logsPendingChunk = null;
let logsFlushScheduled = false;
const flushLogs = () => {
    logsFlushScheduled = false;
    if (logsPendingChunk) {
        // Use insertAdjacentHTML on a text-only container — faster than innerHTML
        // for appending, and avoids re-parsing the existing content.
        logsOutput.insertAdjacentText('beforeend', logsPendingChunk);
        logsOutput.scrollTop = logsOutput.scrollHeight;
        logsPendingChunk = null;
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
        logsOutput.textContent = `Error: ${e.message}`;
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
        // Accumulate the raw chunk; ansiToHtml is expensive, do it once per flush.
        logsPendingChunk = (logsPendingChunk ?? '') + ansiToHtml(chunk);
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
        logsTabs.forEach((t) => t.classList.toggle('active', t === tab));
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
    if (agUptimeTimer !== null)
        window.clearInterval(agUptimeTimer);
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
                memo('info', 5_000, () => window.ag.info()),
                withTimeout(window.ag.antigravityStatus(), 10_000, 'antigravity status').catch((err) => ({ ok: false, data: undefined, error: err.message })),
                withTimeout(window.ag.antigravityVersion(), 10_000, 'antigravity version').catch((err) => ({ ok: false, data: undefined, error: err.message })),
                withTimeout(window.ag.run(['models', 'list', '--json']), 10_000, 'models list').catch(() => ({ stdout: '{"models":[]}', stderr: '', code: 0 })),
            ]);
            const status = statusResult.ok ? statusResult.data : null;
            const versionData = versionResult.ok ? versionResult.data : null;
            const modelsData = JSON.parse(modelsResult.stdout);
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
            agCustomModels.textContent = String(modelsData.models?.length ?? 0);
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
            infoTable.innerHTML = `<div class="empty-state"><p>Error: ${escapeHtml(e.message)}</p></div>`;
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
    themeToggle.textContent = theme === 'dark' ? 'Switch to light' : 'Switch to dark';
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
    { id: 'dashboard', label: 'Dashboard', view: 'dashboard' },
    { id: 'doctor', label: 'Run doctor', view: 'dashboard', action: () => void runDoctor() },
    { id: 'logs', label: 'Logs', view: 'logs' },
    { id: 'models', label: 'Models', view: 'models' },
    { id: 'mitm', label: 'MITM Proxy', view: 'mitm' },
    { id: 'patch', label: 'Binary patch', view: 'patch' },
    { id: 'settings', label: 'Settings', view: 'settings' },
    { id: 'info', label: 'Antigravity Status', view: 'info' },
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
    const filtered = PALETTE_COMMANDS.filter((c) => c.label.toLowerCase().includes(q));
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
    }
    else if (e.key === 'ArrowUp') {
        e.preventDefault();
        idx = Math.max(idx - 1, 0);
        items.forEach((it) => it.classList.remove('selected'));
        items[idx]?.classList.add('selected');
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
            toast(`Error: ${e.message}`, 'err');
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
        toast(`Error: ${e.message}`, 'err');
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
        toast(`Error: ${e.message}`, 'err');
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
        toast(`Error: ${e.message}`, 'err');
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
        toast(`Error: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
});
//# sourceMappingURL=app.js.map