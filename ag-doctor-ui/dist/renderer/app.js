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
        modalConfirm.className = `btn ${opts?.danger ? 'btn-danger' : 'btn-primary'}`;
        modalBackdrop.hidden = false;
        const cleanup = (result) => {
            modalBackdrop.hidden = true;
            modalConfirm.removeEventListener('click', onConfirm);
            modalCancel.removeEventListener('click', onCancel);
            modalClose.removeEventListener('click', onCancel);
            modalBackdrop.removeEventListener('click', onBackdrop);
            resolve(result);
        };
        const onConfirm = () => cleanup(true);
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
const addModelModalSave = $('#addModelModalSave');
const providerGrid = $('#providerGrid');
const modelProviderInput = $('#modelProvider');
const modelIdInput = $('#modelId');
const externalModelNameInput = $('#externalModelName');
const modelApiUrlInput = $('#modelApiUrl');
const modelApiKeyInput = $('#modelApiKey');
const modelDisplayNameInput = $('#modelDisplayName');
const DEFAULT_URLS = {
    openai: 'https://api.openai.com/v1/chat/completions',
    anthropic: 'https://api.anthropic.com/v1/messages',
    openrouter: 'https://openrouter.ai/api/v1/chat/completions',
    ollama: 'http://localhost:11434/v1/chat/completions',
    google: 'https://generativelanguage.googleapis.com/v1beta/models/',
    deepseek: 'https://api.deepseek.com/anthropic',
    groq: 'https://api.groq.com/openai/v1',
    mistral: 'https://api.mistral.ai/v1',
    cerebras: 'https://api.cerebras.ai/v1',
    kimi: 'https://api.moonshot.ai/anthropic/v1',
    fireworks: 'https://api.fireworks.ai/inference/v1',
    lmstudio: 'http://localhost:1234/v1',
    llamacpp: 'http://localhost:8080/v1',
    nvidia: 'https://integrate.api.nvidia.com/v1',
    custom: '',
};
function selectProvider(provider) {
    modelProviderInput.value = provider;
    providerGrid.querySelectorAll('.provider-card').forEach((card) => {
        card.classList.toggle('selected', card.dataset.provider === provider);
    });
    const url = DEFAULT_URLS[provider] || '';
    modelApiUrlInput.value = url;
    modelApiUrlInput.placeholder = url || 'https://api.example.com/v1/chat/completions';
}
providerGrid.querySelectorAll('.provider-card').forEach((card) => {
    card.addEventListener('click', () => selectProvider(card.dataset.provider));
});
// Open modal
function openAddModelModal() {
    // Reset form
    modelIdInput.value = '';
    externalModelNameInput.value = '';
    modelApiKeyInput.value = '';
    modelDisplayNameInput.value = '';
    selectProvider('openai');
    addModelModalBackdrop.hidden = false;
    addModelModalBackdrop.style.display = 'grid';
    // Focus first input for better UX
    setTimeout(() => modelIdInput.focus(), 50);
}
$('#modelsAddBtn').addEventListener('click', openAddModelModal);
$('#dashboardAddModelBtn').addEventListener('click', openAddModelModal);
// Close modal helpers
function closeAddModelModal() {
    addModelModalBackdrop.hidden = true;
    addModelModalBackdrop.style.display = 'none';
}
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
// Auto-fill external model name when model ID is edited (e.g. models/gpt-4o -> gpt-4o)
modelIdInput.addEventListener('input', () => {
    const val = modelIdInput.value.trim();
    if (val.startsWith('models/')) {
        externalModelNameInput.value = val.replace(/^models\//, '');
    }
});
// Save model action
addModelModalSave.addEventListener('click', async () => {
    const provider = modelProviderInput.value;
    let name = modelIdInput.value.trim();
    const external = externalModelNameInput.value.trim();
    const url = modelApiUrlInput.value.trim();
    const key = modelApiKeyInput.value.trim();
    const display = modelDisplayNameInput.value.trim();
    if (!name) {
        toast('Model ID is required', 'warn');
        modelIdInput.focus();
        return;
    }
    if (!name.startsWith('models/')) {
        name = `models/${name}`;
        modelIdInput.value = name;
    }
    if (!external) {
        toast('External model name is required', 'warn');
        externalModelNameInput.focus();
        return;
    }
    if (!url) {
        toast('API URL is required', 'warn');
        modelApiUrlInput.focus();
        return;
    }
    addModelModalSave.setAttribute('disabled', 'true');
    setStatus('Adding model…', 'busy');
    try {
        const args = [
            'models',
            'add',
            '--provider', provider,
            '--name', name,
            '--external', external,
            '--url', url,
            '--key', key || '',
            '--display', display || name,
            '--yes'
        ];
        const r = await window.ag.run(args);
        if (r.code === 0) {
            toast(`Successfully added model ${name}`, 'ok');
            closeAddModelModal();
            void loadModels();
        }
        else {
            toast(`Failed to add model: ${r.stderr || r.stdout}`, 'err', 6000);
            setStatus('Ready');
        }
    }
    catch (e) {
        toast(`Error: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
    finally {
        addModelModalSave.removeAttribute('disabled');
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// MITM view
// ─────────────────────────────────────────────────────────────────────────────
const mitmStatusEl = $('#mitmStatus');
// Reusable template for MITM status — avoids creating a new <template> each load
const mitmTpl = document.createElement('template');
async function loadMitmStatus() {
    setStatus('Loading MITM status…', 'busy');
    showSkeleton(mitmStatusEl, 'cards', 3);
    try {
        const r = await window.ag.run(['mitm', 'status', '--json']);
        const s = JSON.parse(r.stdout);
        const caBanner = s.ca.installed
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
             <div class="patch-banner-title">CA certificate not installed</div>
             <div class="patch-banner-text">Install the CA to avoid TLS errors in intercepted applications.</div>
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
                        toast('Repair script completed successfully.', 'ok', 5000);
                    }
                    else {
                        toast('Repair failed: ' + res.error, 'err', 6000);
                    }
                }
                catch (err) {
                    toast('Repair IPC error: ' + err.message, 'err', 6000);
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
}
async function mitmAction(args, successMsg, refresh = true) {
    setStatus(`${args.slice(1).join(' ')}…`, 'busy');
    try {
        const r = await window.ag.run(args);
        if (r.code === 0) {
            toast(successMsg, 'ok', 5000);
            if (refresh)
                void loadMitmStatus();
        }
        else {
            toast(`Failed: ${r.stderr || r.stdout}`, 'err', 6000);
            setStatus('Error', 'err');
        }
    }
    catch (e) {
        toast(`Error: ${e.message}`, 'err');
        setStatus('Error', 'err');
    }
}
$('#mitmInstallBtn').addEventListener('click', () => void mitmAction(['mitm', 'install', '--yes'], 'CA installed'));
$('#mitmUninstallBtn').addEventListener('click', () => void mitmAction(['mitm', 'uninstall', '--yes'], 'CA uninstalled'));
$('#mitmProxyOnBtn').addEventListener('click', () => void mitmAction(['mitm', 'proxy-on'], 'Proxy enabled'));
$('#mitmProxyOffBtn').addEventListener('click', () => void mitmAction(['mitm', 'proxy-off'], 'Proxy disabled'));
$('#mitmExportCaBtn').addEventListener('click', () => void mitmAction(['mitm', 'export-ca'], 'CA exported'));
// ─────────────────────────────────────────────────────────────────────────────
// Patch view
// ─────────────────────────────────────────────────────────────────────────────
const patchStatusEl = $('#patchStatus');
// Reusable template for patch status — avoids creating a new <template> each load
const patchTpl = document.createElement('template');
async function loadPatchStatus() {
    setStatus('Loading patch status…', 'busy');
    showSkeleton(patchStatusEl, 'lines', 5);
    try {
        const r = await window.ag.run(['patch', 'status', '--json']);
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
        <div class="patch-row-label">Original URL</div>
        <div class="patch-row-value">${escapeHtml(s.originalUrl)}</div>
      </div>
      <div class="patch-row">
        <div class="patch-row-label">Patched URL</div>
        <div class="patch-row-value">${escapeHtml(s.patchedUrl)}</div>
      </div>`;
        patchStatusEl.replaceChildren(patchTpl.content);
        setStatus('Ready');
    }
    catch (e) {
        patchStatusEl.innerHTML = `<div class="empty-state"><p>Error: ${escapeHtml(e.message)}</p></div>`;
        setStatus('Error', 'err');
    }
    finally {
        hideSkeleton(patchStatusEl);
    }
}
$('#patchApplyBtn').addEventListener('click', async () => {
    const ok = await confirmModal('Apply binary patch', `This will modify <code>language_server</code> to redirect API calls to the local proxy.<br><br>A backup will be created automatically.`, { confirmLabel: 'Apply patch' });
    if (!ok)
        return;
    setStatus('Applying patch…', 'busy');
    try {
        const r = await window.ag.run(['patch', 'apply', '--yes']);
        if (r.code === 0) {
            toast('Patch applied successfully', 'ok', 5000);
            void loadPatchStatus();
        }
        else {
            toast(`Patch failed: ${r.stderr || r.stdout}`, 'err', 6000);
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
            toast(`Restore failed: ${r.stderr || r.stdout}`, 'err');
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
    setStatus('Loading Antigravity status…', 'busy');
    setAgHero('busy', 'Checking…', 'Detecting installation');
    try {
        // Parallel: info IPC, status IPC, version IPC, models count
        const [info, statusResult, versionResult, modelsResult] = await Promise.all([
            memo('info', 5_000, () => window.ag.info()),
            window.ag.antigravityStatus().catch((err) => ({ ok: false, data: undefined, error: err.message })),
            window.ag.antigravityVersion().catch((err) => ({ ok: false, data: undefined, error: err.message })),
            window.ag.run(['models', 'list', '--json']).catch(() => ({ stdout: '{"models":[]}', stderr: '', code: 0 })),
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
    setStatus('Loading Antigravity status…', 'busy');
    try {
        const r = await window.ag.antigravityStatus();
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