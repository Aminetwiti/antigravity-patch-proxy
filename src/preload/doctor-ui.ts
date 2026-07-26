/**
 * Doctor UI — full custom-models management panel, Provider Manager modal,
 * design-token CSS injection, focused-element helpers, and provider icon/color utils.
 *
 * ponytail: this file is large because the UI is rich. It is intentionally NOT split
 * further — Doctor UI is a single coherent view. If future UI features demand it,
 * split into doctor-ui/{list,modal,tokens}.ts.
 */
import { storageAPI } from './api';
import { preloadLog } from './logger';
import type { ProviderFileEntry, ProviderModelEntry } from './types';
import { PROVIDER_PRESETS } from './types';

interface McpLayout {
  mainContainer: Node;
  headerRow: Element;
  contentBlock: Element | null;
}

function findRefreshButton(): HTMLButtonElement | null {
  const buttons = Array.from(document.querySelectorAll('button'));
  return (buttons.find((b) => b.textContent?.trim() === 'Refresh') as HTMLButtonElement) || null;
}

function findMcpSectionContainer(): McpLayout | null {
  const refreshBtn = findRefreshButton();
  if (!refreshBtn) return null;

  const btnGroup = refreshBtn.parentNode;
  if (!btnGroup) return null;

  const headerRow = btnGroup.parentNode as Element;
  if (!headerRow) return null;

  const mainContainer = headerRow.parentNode;
  if (!mainContainer) return null;

  const contentBlock = headerRow.nextElementSibling;

  return {
    mainContainer,
    headerRow,
    contentBlock,
  };
}

const PROVIDER_ICONS: Record<string, string> = {
  openai: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M12 2L2 7l10 5 10-5-10-5z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M2 17l10 5 10-5" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M2 12l10 5 10-5" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>`,
  anthropic: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><rect x="3" y="8" width="4" height="8" rx="1" stroke="currentColor" stroke-width="1.5"/><rect x="10" y="5" width="4" height="14" rx="1" stroke="currentColor" stroke-width="1.5"/><rect x="17" y="2" width="4" height="20" rx="1" stroke="currentColor" stroke-width="1.5"/></svg>`,
  google: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="8" stroke="currentColor" stroke-width="1.5"/><path d="M12 4a8 8 0 0 1 5.66 13.66L12 12V4z" fill="currentColor" fill-opacity="0.2"/></svg>`,
  ollama: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><rect x="4" y="4" width="16" height="16" rx="3" stroke="currentColor" stroke-width="1.5"/><circle cx="9" cy="10" r="1.5" fill="currentColor"/><circle cx="15" cy="10" r="1.5" fill="currentColor"/><path d="M8 15c1 1.5 3 2 4 2s3-.5 4-2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
  openrouter: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.5"/><path d="M12 3v4M12 17v4M3 12h4M17 12h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="12" cy="12" r="3" fill="currentColor" fill-opacity="0.3"/></svg>`,
  custom: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="7" stroke="currentColor" stroke-width="1.5"/><path d="M12 8v8M8 12h8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
};

const PROVIDER_COLORS: Record<string, string> = {
  openai: '#10a37f',
  anthropic: '#d97757',
  google: '#4285f4',
  ollama: '#f0f0f0',
  openrouter: '#ff7a45',
  custom: '#a855f7',
};

export const prefersReducedMotion = (): boolean =>
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

export function getProviderIcon(provider: string): string {
  return PROVIDER_ICONS[provider] || PROVIDER_ICONS.custom;
}

export function getProviderColor(provider: string): string {
  return PROVIDER_COLORS[provider] || PROVIDER_COLORS.custom;
}

export async function renderCustomModelsList(): Promise<void> {
  const contentArea = document.getElementById('agy-custom-models-content');
  if (!contentArea) return;

  contentArea.innerHTML = '';

  try {
    const models = await storageAPI.getCustomModels();
    if (!models || models.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'agy-empty-state';
      empty.style.padding = '48px 24px';
      empty.innerHTML = `
        <div style="margin-bottom: 16px; color: var(--agy-ink-secondary);">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/></svg>
        </div>
        <div style="font-size: 14px; font-weight: 500; color: var(--agy-ink-secondary);">No models configured. Add a custom provider to get started.</div>
      `;
      const addBtnEmpty = document.createElement('button');
      addBtnEmpty.type = 'button';
      addBtnEmpty.className = 'agy-btn-primary';
      addBtnEmpty.style.marginTop = '16px';
      addBtnEmpty.innerHTML = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> Add model`;
      addBtnEmpty.addEventListener('click', () => openProviderManagerModal());
      empty.appendChild(addBtnEmpty);
      contentArea.appendChild(empty);
    } else {
      const listContainer = document.createElement('div');
      listContainer.style.display = 'flex';
      listContainer.style.flexDirection = 'column';
      listContainer.style.gap = '8px';

      models.forEach((model) => {
        const item = document.createElement('div');
        item.className = 'agy-provider-row';

        const header = document.createElement('div');
        header.className = 'agy-row-header';

        const info = document.createElement('div');
        info.className = 'agy-row-info';

        const statusDot = document.createElement('span');
        statusDot.className = 'agy-status-dot agy-status-off';
        statusDot.title = 'Connection status unknown (test to verify)';

        const title = document.createElement('div');
        title.className = 'agy-row-name';
        title.textContent = (model.displayName as string) || (model.name as string);

        const badge = document.createElement('span');
        badge.className = 'agy-badge';
        badge.style.backgroundColor = getProviderColor(model.provider as string) + '22';
        badge.style.color = getProviderColor(model.provider as string);
        badge.textContent = model.provider as string;

        const url = document.createElement('div');
        url.className = 'agy-row-sub';
        url.textContent = model.apiUrl as string;

        info.appendChild(statusDot);
        info.appendChild(title);
        info.appendChild(badge);
        info.appendChild(url);

        const actions = document.createElement('div');
        actions.className = 'agy-row-actions';

        const testBtn = document.createElement('button');
        testBtn.className = 'agy-btn-ghost';
        testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`;
        testBtn.title = 'Test connection';

        testBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const originalHtml = testBtn.innerHTML;
          testBtn.style.color = '#fbbf24';
          testBtn.style.cursor = 'wait';
          testBtn.disabled = true;
          testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="${prefersReducedMotion() ? '' : 'animation: agy-spin 0.8s linear infinite;'}"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>`;

          try {
            const result = await storageAPI.testModelConnection({
              apiUrl: model.apiUrl as string,
              provider: model.provider as string,
              apiKey: model.apiKey as string,
              allowUnauthorized: model.allowUnauthorized as boolean | undefined,
            });

            if (result.success) {
              statusDot.className = 'agy-status-dot agy-status-on';
              statusDot.title = result.message || 'Connected';
              testBtn.title = 'Connected ✓';
              testBtn.style.color = 'var(--agy-success)';
              testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`;
              const banner = document.getElementById('agy-persistent-banner');
              if (banner) banner.remove();
              (window as any).failedModelDisplayNames?.clear?.();
              document.querySelectorAll('.ag-model-warning').forEach((el) => el.remove());
            } else {
              statusDot.className = 'agy-status-dot';
              statusDot.style.backgroundColor = 'var(--agy-danger)';
              const errMsg = result.error || 'Connection failed';
              statusDot.title = errMsg;
              testBtn.title = errMsg;
              testBtn.style.color = 'var(--agy-danger)';
              testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>`;
            }
          } catch (err) {
            statusDot.className = 'agy-status-dot';
            statusDot.style.backgroundColor = 'var(--agy-danger)';
            statusDot.title = 'Connection test failed';
            testBtn.title = 'Connection test failed';
            testBtn.style.color = 'var(--agy-danger)';
            testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>`;
          }
          setTimeout(() => {
            testBtn.disabled = false;
            testBtn.style.cursor = 'pointer';
            testBtn.style.color = '';
            testBtn.innerHTML = originalHtml;
          }, 3000);
        });

        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'agy-btn-ghost';
        deleteBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`;
        deleteBtn.setAttribute('aria-label', `Delete ${(model.displayName as string) || (model.name as string)}`);
        deleteBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          if (window.confirm(`Delete "${model.displayName || model.name}"? This removes it from your model list.`)) {
            await storageAPI.deleteCustomModel(model.name as string);
            await renderCustomModelsList();
            const refreshBtn = findRefreshButton();
            if (refreshBtn) refreshBtn.click();
          }
        });

        const editBtn = document.createElement('button');
        editBtn.className = 'agy-btn-ghost';
        editBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>';
        editBtn.title = 'Edit provider settings';
        editBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const providers = await storageAPI.getProviders();
          const p = providers.find((prov) => prov.provider === model.provider || prov.name === model.provider);
          if (p) {
            openProviderManagerModal(p);
          }
        });
        actions.appendChild(editBtn);
        actions.appendChild(testBtn);
        actions.appendChild(deleteBtn);
        header.appendChild(info);
        header.appendChild(actions);
        item.appendChild(header);
        listContainer.appendChild(item);
      });

      contentArea.appendChild(listContainer);
    }
  } catch (err) {
    preloadLog.error('Failed to load custom models in list:', err);
  }
}

export async function injectCustomModelsSection(): Promise<void> {
  const layout = findMcpSectionContainer();
  if (!layout) return;

  const { mainContainer, headerRow, contentBlock } = layout;

  if (document.getElementById('agy-custom-models-section')) return;

  // Remove the old Antigravity Customizations header row to replace it with Doctor UI header
  if (headerRow && headerRow.parentNode) {
    headerRow.parentNode.removeChild(headerRow);
  }
  if (contentBlock && contentBlock.parentNode) {
    contentBlock.parentNode.removeChild(contentBlock);
  }

  ensureAgyTokens();

  const section = document.createElement('div');
  section.id = 'agy-custom-models-section';
  section.className = 'agy-view';
  section.style.marginTop = '0px';

  const viewHeader = document.createElement('div');
  viewHeader.className = 'agy-view-header';

  const viewTitleGroup = document.createElement('div');
  viewTitleGroup.innerHTML = `
    <h1 class="agy-view-title">Custom models</h1>
    <p class="agy-view-subtitle">Configured providers and their status</p>
  `;

  const viewActions = document.createElement('div');
  viewActions.className = 'agy-header-actions';

  const testAllBtn = document.createElement('button');
  testAllBtn.className = 'agy-btn-ghost';
  testAllBtn.innerHTML = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg> Test all`;
  testAllBtn.addEventListener('click', () => {
    const testBtns = document.querySelectorAll('#agy-custom-models-content .agy-row-actions .agy-btn-ghost[title="Test connection"]');
    testBtns.forEach((btn) => (btn as HTMLButtonElement).click());
  });

  const addModelBtn = document.createElement('button');
  addModelBtn.className = 'agy-btn-primary';
  addModelBtn.innerHTML = `☁️ Provider Manager`;
  addModelBtn.addEventListener('click', () => openProviderManagerModal());

  viewActions.appendChild(testAllBtn);
  viewActions.appendChild(addModelBtn);
  viewHeader.appendChild(viewTitleGroup);
  viewHeader.appendChild(viewActions);

  const panel = document.createElement('div');
  panel.className = 'agy-panel';
  const panelBody = document.createElement('div');
  panelBody.className = 'agy-panel-body';
  panelBody.id = 'agy-custom-models-content';

  panel.appendChild(panelBody);
  section.appendChild(viewHeader);
  section.appendChild(panel);

  mainContainer.appendChild(section);

  await renderCustomModelsList();
}

export function ensureAgyTokens(): void {
  if (document.getElementById('agy-style-tokens')) return;
  const style = document.createElement('style');
  style.id = 'agy-style-tokens';
  style.textContent = `
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Outfit:wght@500;600;700&display=swap');

    :root {
      --agy-bg-base: #0d1117;
      --agy-bg-surface: #161b22;
      --agy-bg-elevated: #1c2128;
      --agy-bg-input: #21262d;
      --agy-bg-input-hover: #30363d;
      --agy-border: #30363d;
      --agy-border-strong: #484f58;
      --agy-ink-primary: #f0f6fc;
      --agy-ink-secondary: #8b949e;
      --agy-ink-muted: #6e7681;
      --agy-accent: #1f6feb;
      --agy-accent-hover: #388bfd;
      --agy-success: #3fb950;
      --agy-success-hover: #2ea043;
      --agy-warning: #d29922;
      --agy-danger: #f85149;
      --agy-danger-hover: #da3633;
      --agy-overlay-bg: hsla(222, 47%, 3%, 0.7);
      --agy-shadow-modal: 0 8px 24px hsla(0, 0%, 0%, 0.5);
      --agy-z-overlay: 100000;
      --agy-radius-sm: 4px;
      --agy-radius-md: 6px;
      --agy-radius-lg: 10px;
      --agy-radius-xl: 14px;
      --agy-font: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      --agy-font-display: 'Outfit', 'Inter', sans-serif;
      --agy-font-mono: 'JetBrains Mono', ui-monospace, "SF Mono", Menlo, monospace;
    }

    .agy-overlay {
      position: fixed; inset: 0;
      background: var(--agy-overlay-bg);
      backdrop-filter: blur(6px);
      -webkit-backdrop-filter: blur(6px);
      display: grid; place-items: center;
      z-index: var(--agy-z-overlay);
      animation: agy-fade-in 180ms cubic-bezier(0.4, 0, 0.2, 1);
      font-family: var(--agy-font);
      color: var(--agy-ink-primary);
    }
    @keyframes agy-fade-in { from { opacity: 0; } to { opacity: 1; } }
    .agy-modal {
      background: var(--agy-bg-surface);
      border: 1px solid var(--agy-border-strong);
      border-radius: var(--agy-radius-lg);
      width: 90%; max-width: 560px;
      max-height: min(680px, 88vh);
      display: flex; flex-direction: column;
      box-shadow: var(--agy-shadow-modal);
      overflow: hidden;
      animation: agy-modal-in 180ms cubic-bezier(0.16, 1, 0.3, 1);
    }
    @keyframes agy-modal-in {
      from { opacity: 0; transform: translate3d(0, 8px, 0) scale(0.98); }
      to   { opacity: 1; transform: translate3d(0, 0, 0) scale(1); }
    }
    .agy-modal-header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 14px 18px;
      border-bottom: 1px solid var(--agy-border);
      background: var(--agy-bg-surface);
    }
    .agy-modal-title {
      font-family: var(--agy-font-display);
      font-size: 14px; font-weight: 600;
      display: flex; align-items: center; gap: 8px;
    }
    .agy-modal-body {
      display: flex; flex-direction: column; flex: 1; overflow: hidden; position: relative;
      font-size: 13px; line-height: 1.6;
      background: var(--agy-bg-base);
    }
    .agy-modal-list {
      padding: 18px; overflow-y: auto; flex: 1;
      display: flex; flex-direction: column; gap: 12px;
    }
    .agy-modal-form {
      padding: 18px; overflow-y: auto; flex: 1;
      display: none; flex-direction: column; gap: 16px;
      background: var(--agy-bg-elevated);
    }
    .agy-icon-btn {
      background: transparent; border: none;
      width: 26px; height: 26px;
      display: grid; place-items: center;
      border-radius: var(--agy-radius-sm);
      color: var(--agy-ink-secondary);
      cursor: pointer;
      transition: all 120ms cubic-bezier(0.4, 0, 0.2, 1);
    }
    .agy-icon-btn:hover { background: var(--agy-bg-input); color: var(--agy-ink-primary); }
    .agy-icon-btn:focus-visible { outline: 2px solid var(--agy-accent-hover); outline-offset: 2px; }
    .agy-btn-primary, .agy-btn-secondary, .agy-btn-success, .agy-btn-ghost, .agy-btn-confirm {
      font-family: var(--agy-font);
      border-radius: var(--agy-radius-md);
      cursor: pointer; font-weight: 500;
      transition: all 120ms ease;
      padding: 6px 12px; font-size: 12.5px;
      display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    }
    .agy-btn-primary { background: var(--agy-accent); border: 1px solid transparent; color: white; }
    .agy-btn-primary:hover:not(:disabled) { background: var(--agy-accent-hover); }
    .agy-btn-secondary { background: var(--agy-bg-input); border: 1px solid var(--agy-border-strong); color: var(--agy-ink-primary); }
    .agy-btn-secondary:hover:not(:disabled) { background: var(--agy-bg-input-hover); border-color: var(--agy-ink-muted); }
    .agy-btn-ghost { background: transparent; border: 1px solid transparent; color: var(--agy-ink-secondary); }
    .agy-btn-ghost:hover:not(:disabled) { background: var(--agy-bg-input); color: var(--agy-ink-primary); }
    .agy-btn-success { background: var(--agy-success); border: 1px solid transparent; color: white; }
    .agy-btn-success:hover:not(:disabled) { background: var(--agy-success-hover); }
    .agy-btn-danger, .agy-btn-confirm { background: var(--agy-danger); color: white; border: 1px solid transparent; }
    .agy-btn-danger:hover:not(:disabled), .agy-btn-confirm:hover:not(:disabled) { background: var(--agy-danger-hover); }
    button:focus-visible, input:focus-visible, select:focus-visible {
      outline: 2px solid var(--agy-accent-hover); outline-offset: 2px;
    }
    .agy-list-topactions { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 4px; }
    .agy-list-subtitle { font-size: 13px; color: var(--agy-ink-secondary); }
    .agy-empty-state {
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      padding: 32px 18px; text-align: center;
      border: 1px dashed var(--agy-border-strong); border-radius: var(--agy-radius-lg);
      background: var(--agy-bg-input); color: var(--agy-ink-secondary); font-size: 13px;
    }
    .agy-provider-row {
      background: var(--agy-bg-surface);
      border: 1px solid var(--agy-border);
      border-radius: var(--agy-radius-lg);
      padding: 14px 16px;
      display: flex; flex-direction: column; gap: 10px;
      transition: border-color 120ms ease, background-color 120ms ease;
    }
    .agy-provider-row:hover { border-color: var(--agy-border-strong); background: var(--agy-bg-elevated); }
    .agy-row-header { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
    .agy-row-info { display: flex; align-items: center; gap: 8px; min-width: 0; }
    .agy-row-name { font-size: 14px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 100%; }
    .agy-row-actions { display: flex; gap: 6px; flex-wrap: wrap; }
    .agy-row-sub { font-size: 12px; color: var(--agy-ink-muted); }
    .agy-status-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
    .agy-status-on { background-color: var(--agy-success); box-shadow: 0 0 6px hsla(136, 60%, 50%, 0.4); }
    .agy-status-off { background-color: var(--agy-ink-muted); }
    .agy-form-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
    .agy-form-title { font-size: 15px; font-weight: 600; font-family: var(--agy-font-display); }
    .agy-form-group { display: flex; flex-direction: column; gap: 6px; margin-bottom: 16px; }
    .agy-form-group label { font-size: 13px; font-weight: 500; color: var(--agy-ink-primary); display: flex; align-items: center; justify-content: space-between; }
    .agy-form-hint { font-size: 11.5px; color: var(--agy-ink-secondary); line-height: 1.4; }
    .agy-form-error-banner {
      font-size: 12.5px; color: var(--agy-danger); background: hsla(0, 100%, 65%, 0.1);
      border: 1px solid hsla(0, 100%, 65%, 0.2); border-radius: var(--agy-radius-md);
      padding: 10px 14px; margin-top: 4px; display: none;
    }
    .agy-form-error-visible { display: block !important; }
    .agy-input {
      background-color: var(--agy-bg-base);
      border: 1px solid var(--agy-border-strong);
      border-radius: var(--agy-radius-md);
      color: var(--agy-ink-primary);
      padding: 8px 12px; font-size: 13.5px; font-family: var(--agy-font-mono);
      outline: none; transition: border-color 120ms ease, box-shadow 120ms ease;
    }
    .agy-input:hover { border-color: var(--agy-ink-muted); }
    .agy-input:focus { border-color: var(--agy-accent-hover); box-shadow: 0 0 0 1px var(--agy-accent-hover); }
    .agy-input:invalid:not(:placeholder-shown) { border-color: var(--agy-danger); }
    .agy-form-group-checkbox { flex-direction: row; align-items: center; gap: 8px; margin-bottom: 16px; }
    .agy-form-checkbox { accent-color: var(--agy-accent); width: 14px; height: 14px; cursor: pointer; }
    .agy-form-label-inline { font-size: 13px; color: var(--agy-ink-primary); cursor: pointer; font-weight: 400 !important; }
    .agy-form-header-row { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
    .agy-fetched-models-container {
      border: 1px solid var(--agy-border-strong); border-radius: var(--agy-radius-md);
      background: var(--agy-bg-base); overflow: hidden;
    }
    .agy-fetched-models-list {
      max-height: 220px; overflow-y: auto; display: flex; flex-direction: column;
    }
    .agy-fetched-models-list::-webkit-scrollbar { width: 6px; }
    .agy-fetched-models-list::-webkit-scrollbar-thumb { background: var(--agy-border-strong); border-radius: 4px; }
    .agy-fetched-models-empty { padding: 32px 24px; text-align: center; color: var(--agy-ink-secondary); font-size: 13px; }
    .agy-fetched-model-row {
      display: flex; align-items: center; gap: 10px; padding: 10px 14px;
      border-bottom: 1px solid var(--agy-border); cursor: pointer;
      transition: background-color 120ms ease;
    }
    .agy-fetched-model-row:last-child { border-bottom: none; }
    .agy-fetched-model-row:hover { background: var(--agy-bg-input); }
    .agy-fetched-model-row input { accent-color: var(--agy-accent); }
    .agy-fetched-model-row span { font-size: 13px; color: var(--agy-ink-primary); }
    .agy-form-footer {
      display: flex; justify-content: flex-end; gap: 12px;
      margin-top: auto; padding-top: 16px;
      border-top: 1px solid var(--agy-border);
    }
    @media (max-width: 480px) {
      .agy-modal { width: calc(100vw - 24px); }
      .agy-modal-header { padding: 12px 16px; }
      .agy-modal-list, .agy-modal-form { padding: 16px; }
      .agy-row-header { flex-direction: column; align-items: flex-start; }
      .agy-row-actions { width: 100%; }
      .agy-row-actions .agy-btn-secondary { flex: 1; min-width: 0; }
      .agy-form-footer { justify-content: stretch; }
      .agy-form-footer > button { flex: 1; }
    }
    @media (prefers-reduced-motion: reduce) {
      .agy-overlay, .agy-modal, .agy-btn-primary, .agy-btn-secondary,
      .agy-btn-success, .agy-btn-ghost, .agy-icon-btn, .agy-input,
      .agy-provider-row, .agy-form-error,
      .ag-health-dot, .ag-health-refresh {
        transition: none !important;
        animation: none !important;
      }
    }
    @keyframes ag-pulse-error {
      0%, 100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.5); }
      50%      { box-shadow: 0 0 0 4px rgba(239, 68, 68, 0); }
    }
    @keyframes ag-pulse-healthy {
      0%, 100% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.4); }
      50%      { box-shadow: 0 0 0 3px rgba(34, 197, 94, 0); }
    }
    @keyframes ag-spin {
      from { transform: rotate(0deg); }
      to   { transform: rotate(360deg); }
    }
    @keyframes ag-fade-in {
      from { opacity: 0; transform: translateY(4px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    .ag-health-dot {
      width: 8px; height: 8px;
      border-radius: 50%;
      display: inline-block;
      flex-shrink: 0;
      margin-left: 6px;
      vertical-align: middle;
      transition: background-color 300ms ease, box-shadow 300ms ease;
    }
    .ag-health-dot--healthy { background-color: #22c55e; animation: ag-pulse-healthy 2.5s ease-in-out infinite; }
    .ag-health-dot--error { background-color: #ef4444; animation: ag-pulse-error 1.8s ease-in-out infinite; }
    .ag-health-dot--unknown { background-color: #6b7280; opacity: 0.7; }
    .ag-health-refresh {
      display: inline-flex; align-items: center; justify-content: center;
      width: 18px; height: 18px; margin-left: 4px; padding: 2px;
      border: none; background: transparent; color: #a1a1aa;
      cursor: pointer; border-radius: 50%;
      transition: color 150ms ease, background-color 150ms ease;
      vertical-align: middle; flex-shrink: 0;
    }
    .ag-health-refresh:hover { color: #f4f4f5; background-color: rgba(63, 63, 70, 0.6); }
    .ag-health-refresh--spinning svg { animation: ag-spin 0.8s linear infinite; }
    .ag-health-tooltip {
      position: absolute; z-index: 100001;
      background: #1a1a1a; border: 1px solid #3f3f46; border-left: 3px solid #ef4444;
      border-radius: 6px; padding: 10px 14px; max-width: 320px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 12px; color: #e5e5e5; line-height: 1.5;
      box-shadow: 0 8px 24px rgba(0,0,0,0.4);
      animation: ag-fade-in 150ms ease-out;
      pointer-events: auto;
    }
    .ag-health-tooltip__title { font-weight: 600; font-size: 12px; margin-bottom: 4px; display: flex; align-items: center; gap: 6px; }
    .ag-health-tooltip__msg { color: #a1a1aa; font-size: 11px; margin-bottom: 8px; }
    .ag-health-tooltip__action {
      display: inline-flex; align-items: center; gap: 4px;
      font-size: 11px; font-weight: 500; color: #3b82f6;
      cursor: pointer; background: none; border: none; padding: 0; text-decoration: none;
    }
    .ag-health-tooltip__action:hover { color: #60a5fa; text-decoration: underline; }
    .ag-dropdown-error-overlay { opacity: 0.55; pointer-events: auto; position: relative; }
  `;
  document.head.appendChild(style);
}

export function getFocusableElements(root: HTMLElement): HTMLElement[] {
  const selector = [
    'a[href]',
    'button:not([disabled])',
    'input:not([disabled])',
    'select:not([disabled])',
    'textarea:not([disabled])',
    '[tabindex]:not([tabindex="-1"])',
  ].join(',');
  return Array.from(root.querySelectorAll<HTMLElement>(selector)).filter(
    (el) => !el.hasAttribute('inert') && el.offsetParent !== null,
  );
}

export function openProviderManagerModal(existingProvider?: ProviderFileEntry): void {
  const existing = document.getElementById('agy-modal-overlay');
  if (existing) existing.remove();

  const triggerElement = document.activeElement as HTMLElement | null;
  ensureAgyTokens();

  const overlay = document.createElement('div');
  overlay.id = 'agy-modal-overlay';
  overlay.className = 'agy-overlay';
  overlay.setAttribute('aria-hidden', 'true');

  const modal = document.createElement('div');
  modal.className = 'agy-modal agy-modal-lg';
  modal.setAttribute('role', 'dialog');
  modal.setAttribute('aria-modal', 'true');
  modal.setAttribute('aria-labelledby', 'agy-modal-title');

  const header = document.createElement('div');
  header.className = 'agy-modal-header';

  const titleWrap = document.createElement('div');
  titleWrap.className = 'agy-modal-header-title-wrap';
  const titleIcon = document.createElement('div');
  titleIcon.className = 'agy-modal-header-icon';
  titleIcon.textContent = existingProvider ? '✎' : '+';
  const titleText = document.createElement('h2');
  titleText.id = 'agy-modal-title';
  titleText.textContent = existingProvider ? 'Edit Custom Model' : 'Add Custom Model';
  titleWrap.appendChild(titleIcon);
  titleWrap.appendChild(titleText);

  const closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  closeBtn.className = 'agy-icon-btn modal-close';
  closeBtn.setAttribute('aria-label', 'Close');
  closeBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';

  header.appendChild(titleWrap);
  header.appendChild(closeBtn);
  modal.appendChild(header);

  const body = document.createElement('div');
  body.className = 'agy-modal-body';

  const formContainer = document.createElement('form');
  formContainer.id = 'agy-addModelForm';
  body.appendChild(formContainer);

  const footer = document.createElement('div');
  footer.className = 'agy-modal-footer';

  modal.appendChild(body);
  modal.appendChild(footer);
  overlay.appendChild(modal);
  document.body.appendChild(overlay);

  const closeModal = (): void => {
    overlay.remove();
    document.removeEventListener('keydown', escHandler);
    if (triggerElement && typeof triggerElement.focus === 'function') {
      try { triggerElement.focus(); } catch { /* no-op */ }
    }
  };

  closeBtn.addEventListener('click', closeModal);
  overlay.addEventListener('click', (ev) => {
    if (ev.target === overlay) closeModal();
  });

  const escHandler = (ev: KeyboardEvent): void => {
    if (ev.key === 'Escape') {
      ev.preventDefault();
      closeModal();
    }
  };
  document.addEventListener('keydown', escHandler);

  if (prefersReducedMotion()) {
    overlay.classList.add('agy-no-motion');
  } else {
    overlay.classList.add('agy-anim-in');
  }

  const state = existingProvider
    ? JSON.parse(JSON.stringify(existingProvider))
    : {
        id: 'provider-' + Date.now(),
        name: '',
        provider: 'openai',
        apiUrl: 'https://api.openai.com/v1',
        apiKey: '',
        allowUnauthorized: false,
        enabled: true,
        models: [] as ProviderModelEntry[],
      };

  const createInput = (
    labelStr: string,
    key: string,
    type: string = 'text',
    helpText?: string,
    required: boolean = false,
  ): { wrapper: HTMLElement; input: HTMLInputElement; errorEl: HTMLElement } => {
    const w = document.createElement('div');
    w.className = 'agy-form-group';
    const l = document.createElement('label');
    l.innerHTML = labelStr + (required ? '' : ' <span class="agy-form-hint">(optional)</span>');
    l.htmlFor = 'agy-input-' + key;
    const i = document.createElement('input');
    i.type = type;
    i.id = 'agy-input-' + key;
    i.value = (state as any)[key] || '';
    i.className = 'agy-input';
    if (required) i.setAttribute('required', 'true');
    const errorEl = document.createElement('div');
    errorEl.className = 'agy-form-error-banner';
    errorEl.id = 'agy-error-' + key;

    if (existingProvider && key === 'apiKey') {
      i.placeholder = '•••••••• (leave empty to keep)';
    } else if (key === 'apiKey') {
      i.placeholder = 'sk-...';
    } else if (key === 'apiUrl') {
      i.placeholder = 'https://api.example.com/v1/chat/completions';
    } else if (key === 'name') {
      i.placeholder = 'e.g. My Provider';
    }

    w.appendChild(l);
    w.appendChild(i);
    if (helpText) {
      const help = document.createElement('div');
      help.className = 'agy-form-hint';
      help.textContent = helpText;
      w.appendChild(help);
    }
    w.appendChild(errorEl);
    return { wrapper: w, input: i, errorEl };
  };

  const providerWrap = document.createElement('div');
  providerWrap.className = 'agy-form-group';
  const providerLabel = document.createElement('label');
  providerLabel.textContent = 'Provider Type';
  const providerSelect = document.createElement('select');
  providerSelect.className = 'agy-input';
  for (const preset of PROVIDER_PRESETS) {
    const opt = document.createElement('option');
    opt.value = preset.id;
    opt.textContent = preset.label;
    if (state.provider === preset.id) opt.selected = true;
    providerSelect.appendChild(opt);
  }
  if (!PROVIDER_PRESETS.some((pp) => pp.id === state.provider)) {
    const opt = document.createElement('option');
    opt.value = state.provider;
    opt.textContent = state.provider + ' (saved)';
    opt.selected = true;
    providerSelect.appendChild(opt);
  }

  const providerHint = document.createElement('div');
  providerHint.className = 'agy-form-hint';
  providerHint.textContent = 'Select the API format your provider uses.';

  providerWrap.appendChild(providerLabel);
  providerWrap.appendChild(providerSelect);
  providerWrap.appendChild(providerHint);

  const nameInp = createInput('Provider Name', 'name', 'text', '', true);
  const urlInp = createInput('API URL', 'apiUrl', 'url', 'The chat/completions or messages endpoint.', true);

  const keyWrap = document.createElement('div');
  keyWrap.className = 'agy-form-group';
  const keyLabel = document.createElement('label');
  keyLabel.innerHTML = 'API Key <span class="agy-form-hint">(optional)</span>';
  const keyInp = document.createElement('input');
  keyInp.type = 'password';
  keyInp.className = 'agy-input';
  keyInp.autocomplete = 'off';
  keyInp.spellcheck = false;
  keyInp.placeholder = existingProvider ? '••••••••' : 'sk-...';

  let keyDirty = false;
  keyInp.addEventListener('input', () => { keyDirty = true; });
  keyWrap.appendChild(keyLabel);
  keyWrap.appendChild(keyInp);

  const tlsWrap = document.createElement('div');
  tlsWrap.className = 'agy-form-group agy-form-group-checkbox';
  const tlsChk = document.createElement('input');
  tlsChk.type = 'checkbox';
  tlsChk.className = 'agy-form-checkbox';
  tlsChk.checked = !!state.allowUnauthorized;
  tlsChk.addEventListener('change', (e) => {
    state.allowUnauthorized = (e.target as HTMLInputElement).checked;
  });
  const tlsLbl = document.createElement('label');
  tlsLbl.className = 'agy-form-label-inline';
  tlsLbl.textContent = 'Allow self-signed / unauthorized certificates';
  tlsWrap.appendChild(tlsChk);
  tlsWrap.appendChild(tlsLbl);

  formContainer.appendChild(providerWrap);
  formContainer.appendChild(nameInp.wrapper);
  formContainer.appendChild(urlInp.wrapper);
  formContainer.appendChild(keyWrap);
  formContainer.appendChild(tlsWrap);

  const showError = (el: HTMLElement, msg: string): void => {
    el.textContent = msg;
    el.style.display = 'block';
  };
  const clearError = (el: HTMLElement): void => {
    el.textContent = '';
    el.style.display = 'none';
  };
  const validateUrl = (url: string): boolean => {
    try { const u = new URL(url); return u.protocol === 'http:' || u.protocol === 'https:'; } catch { return false; }
  };

  const formStatus = document.createElement('div');
  formStatus.className = 'agy-form-error-banner';
  formContainer.appendChild(formStatus);

  const step2 = document.createElement('div');
  step2.style.marginTop = '24px';
  step2.style.paddingTop = '24px';
  step2.style.borderTop = '1px solid var(--agy-border-subtle)';

  const modelsSection = document.createElement('div');
  modelsSection.className = 'agy-form-group';

  const modelsHeader = document.createElement('div');
  modelsHeader.className = 'agy-form-header-row';
  const modelsLabel = document.createElement('label');
  modelsLabel.textContent = 'Available Models';
  const fetchBtn = document.createElement('button');
  fetchBtn.type = 'button';
  fetchBtn.className = 'agy-btn-ghost';
  fetchBtn.textContent = 'Refetch';

  modelsHeader.appendChild(modelsLabel);
  modelsHeader.appendChild(fetchBtn);
  modelsSection.appendChild(modelsHeader);

  const listWrapper = document.createElement('div');
  listWrapper.className = 'agy-fetched-models-container';

  const modelsList = document.createElement('div');
  modelsList.className = 'agy-fetched-models-list';
  listWrapper.appendChild(modelsList);
  modelsSection.appendChild(listWrapper);

  step2.appendChild(modelsSection);
  formContainer.appendChild(step2);

  function renderModelsList(): void {
    modelsList.replaceChildren();

    if (state.models.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'agy-fetched-models-empty';
      empty.textContent = 'Fetch models to see available options.';
      modelsList.appendChild(empty);
      return;
    }

    state.models.forEach((m: ProviderModelEntry) => {
      const realIdx = state.models.findIndex((item: ProviderModelEntry) => item.id === m.id);
      const row = document.createElement('label');
      row.className = 'agy-fetched-model-row';

      const chk = document.createElement('input');
      chk.type = 'checkbox';
      chk.className = 'agy-form-checkbox';
      chk.checked = m.enabled;
      chk.addEventListener('change', (e) => {
        if (realIdx !== -1) {
          state.models[realIdx].enabled = (e.target as HTMLInputElement).checked;
        }
      });

      const lbl = document.createElement('span');
      lbl.textContent = m.displayName || m.id;
      row.appendChild(chk);
      row.appendChild(lbl);
      modelsList.appendChild(row);
    });
  }

  renderModelsList();

  fetchBtn.addEventListener('click', async () => {
    if (fetchBtn.disabled) return;
    clearError(formStatus);
    const url = urlInp.input.value.trim();
    if (!validateUrl(url)) {
      showError(urlInp.errorEl, 'Enter a valid http(s) URL');
      urlInp.input.focus();
      return;
    }
    clearError(urlInp.errorEl);
    state.apiUrl = url;
    if (keyDirty) state.apiKey = keyInp.value;

    fetchBtn.disabled = true;
    fetchBtn.textContent = 'Fetching...';

    modelsList.replaceChildren();
    const empty = document.createElement('div');
    empty.className = 'agy-fetched-models-empty';
    empty.textContent = 'Loading models...';
    modelsList.appendChild(empty);

    try {
      const res = await storageAPI.fetchModels({
        baseUrl: state.apiUrl,
        apiUrl: state.apiUrl,
        apiKey: state.apiKey,
        provider: state.provider,
        allowUnauthorized: state.allowUnauthorized,
      });
      if (res.success && res.models) {
        const existingMap = new Map(state.models.map((x: ProviderModelEntry) => [x.id, x]));
        state.models = res.models.map((m: any) => {
          const ext = existingMap.get(m.id);
          return ext ? ext : { id: m.id, displayName: m.displayName || m.id, enabled: true };
        });
        renderModelsList();
      } else {
        showError(formStatus, 'Error: ' + (res.error || 'Unknown error'));
        renderModelsList();
      }
    } catch (err) {
      showError(formStatus, 'Error: ' + (err as Error).message);
      renderModelsList();
    } finally {
      fetchBtn.textContent = 'Refetch';
      fetchBtn.disabled = false;
    }
  });

  const cancelBtn = document.createElement('button');
  cancelBtn.type = 'button';
  cancelBtn.className = 'agy-btn-ghost';
  cancelBtn.textContent = 'Cancel';
  cancelBtn.addEventListener('click', () => closeModal());

  const saveBtn = document.createElement('button');
  saveBtn.type = 'button';
  saveBtn.className = 'agy-btn-primary';
  saveBtn.textContent = existingProvider ? 'Save Changes' : 'Add Selected Models';

  saveBtn.addEventListener('click', async () => {
    if (saveBtn.disabled) return;
    let valid = true;
    const name = nameInp.input.value.trim();
    const url = urlInp.input.value.trim();
    if (!name) {
      showError(nameInp.errorEl, 'Provider name is required');
      valid = false;
    } else {
      clearError(nameInp.errorEl);
    }
    if (!validateUrl(url)) {
      showError(urlInp.errorEl, 'Enter a valid http(s) URL');
      valid = false;
    } else {
      clearError(urlInp.errorEl);
    }
    if (!valid) return;

    state.name = name;
    state.apiUrl = url;
    if (keyDirty) state.apiKey = keyInp.value;

    saveBtn.disabled = true;
    const originalText = saveBtn.textContent;
    saveBtn.textContent = 'Saving...';
    try {
      const res = await storageAPI.saveProvider(state);
      if (res.success) {
        renderCustomModelsList();
        closeModal();
      } else {
        showError(formStatus, 'Error: ' + (res.error || 'Unknown error'));
        saveBtn.textContent = originalText;
        saveBtn.disabled = false;
      }
    } catch (err) {
      showError(formStatus, 'Error: ' + (err as Error).message);
      saveBtn.textContent = originalText;
      saveBtn.disabled = false;
    }
  });

  footer.appendChild(cancelBtn);
  footer.appendChild(saveBtn);

  requestAnimationFrame(() => {
    nameInp.input.focus();
    if (existingProvider) nameInp.input.select();
  });
}
