/**
 * Preload script — runs in every BrowserWindow before the page loads.
 * Exposes a minimal, secure API via contextBridge so the renderer can
 * communicate with the main-process auto-updater without nodeIntegration.
 */

import { contextBridge, ipcRenderer, webFrame } from 'electron';
import { generateModelPlaceholderId, toSlug } from './proxy/idGenerator';
import { classifyError } from './proxy/errorClassifier';
import { DETAILED_PROVIDER_PRESETS } from './constants';
import { createLogger } from './logger';

const preloadLog = createLogger('Preload');
const preloadMetrics = {
  inc: (name: string, labels: Record<string, string> = {}, n = 1): void => {
    // lazy require to avoid loading the metrics module from preload-shim paths
    // that may not include it (preload-shim is bundled standalone).
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const { inc } = require('./metrics');
      inc(name, labels, n);
    } catch {
      /* noop in preload-shim */
    }
  },
};
preloadLog.debug('Preload script loaded');

// ─── Type Declarations for APIs exposed to renderer ──────────────────────────

interface UpdaterState {
  type: string;
  update?: { version: string };
}

type UnsubscribeFn = () => void;

interface UpdaterAPI {
  onStateChanged: (callback: (state: UpdaterState) => void) => UnsubscribeFn;
  applyUpdate: () => Promise<void>;
  quitAndInstall: () => Promise<void>;
  checkForUpdates: () => Promise<void>;
}

interface DialogAPI {
  showOpenDialog: () => Promise<string | undefined>;
}

interface NotificationOptions {
  title: string;
  body: string;
  silent?: boolean;
  payload?: unknown;
}

interface ProviderModelEntry {
  id: string;
  displayName?: string;
  enabled: boolean;
}

interface ProviderFileEntry {
  id: string;
  name: string;
  provider: string;
  apiUrl: string;
  apiKey: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  enabled: boolean;
  models: ProviderModelEntry[];
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalRequests: number;
    lastUsed?: number;
  };
}

interface NotificationAPI {
  send: (options: NotificationOptions) => Promise<void>;
  openSystemPreferences: () => Promise<void>;
  onClicked: (callback: (payload: unknown) => void) => UnsubscribeFn;
}

interface StorageAPI {
  getItems: () => Promise<Record<string, string | null>>;
  updateItems: (changes: Record<string, string | null>) => Promise<void>;
  onChanged: (callback: (changes: Record<string, string | null>) => void) => UnsubscribeFn;
  getCustomModels: () => Promise<CustomModelEntry[]>;
  saveCustomModel: (model: CustomModelEntry) => Promise<{ success: boolean; error?: string }>;
  deleteCustomModel: (modelName: string) => Promise<{ success: boolean; error?: string }>;
  testModelConnection: (model: TestModelParams) => Promise<ConnectionTestResult>;
  fetchModels: (params: FetchModelsParams) => Promise<FetchModelsResult>;
  getProviders: () => Promise<ProviderFileEntry[]>;
  saveProvider: (provider: ProviderFileEntry) => Promise<{ success: boolean; error?: string }>;
  deleteProvider: (providerId: string) => Promise<{ success: boolean; error?: string }>;
  exportProviders: () => Promise<{ success: boolean; count?: number; error?: string }>;
  importProviders: () => Promise<{ success: boolean; count?: number; error?: string }>;
  getDoctorDiagnostics: () => Promise<any>;
}

interface LogsAPI {
  getElectronLogs: () => Promise<string>;
}

interface ExtensionsAPI {
  sendAuthorities: (authoritiesMap: Record<string, string>) => Promise<void>;
}

interface DeepLinkAPI {
  onDeepLink: (callback: (url: string) => void) => UnsubscribeFn;
  getStoredDeepLink: () => Promise<string | undefined>;
}

interface AgentAPI {
  updateActiveAgentCount: (count: number) => Promise<void>;
}

interface TitleBarOverlayOptions {
  color: string;
  symbolColor: string;
}

interface ElectronNativeAPI {
  getZoomLevel: () => number;
  setTitleBarOverlay: (options: TitleBarOverlayOptions) => Promise<void>;
  minimize: () => Promise<void>;
  maximize: () => Promise<void>;
  unmaximize: () => Promise<void>;
  isMaximized: () => Promise<boolean>;
  close: () => Promise<void>;
  toggleDevTools: () => Promise<void>;
  zoomIn: () => void;
  zoomOut: () => void;
  resetZoom: () => void;
  openExternal: (url: string) => Promise<void>;
}

interface CustomModelEntry {
  name: string;
  displayName?: string;
  description?: string;
  provider: string;
  apiKey: string;
  apiUrl: string;
  externalModelName: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  /**
   * Reasoning effort for this model (fetched from /v1/models, not hardcoded).
   * Values: 'low' | 'medium' | 'high' | 'auto' | 'none'
   */
  reasoningEffort?: string;
  /**
   * Thinking budget for this model (fetched from /v1/models, not hardcoded).
   * Values: 'auto' | 'enabled' | 'disabled'
   */
  thinkingBudget?: string;
  /**
   * Mode for this model (fetched from /v1/models, not hardcoded).
   * Values: 'thinking' | 'reasoning' | 'non-thinking' | 'auto'
   */
  mode?: string;
  /**
   * Input modalities supported by this model.
   * e.g., ['text', 'image', 'audio', 'video']
   */
  inputModalities?: string[];
  [key: string]: unknown;
}

interface TestModelParams {
  apiUrl: string;
  provider: string;
  apiKey?: string;
  allowUnauthorized?: boolean;
}

interface ConnectionTestResult {
  success: boolean;
  status?: number;
  message?: string;
  error?: string;
  latencyMs?: number;
}

interface FetchModelsParams {
  baseUrl?: string;
  apiUrl?: string;
  apiKey?: string;
  provider: string;
  allowUnauthorized?: boolean;
}

interface FetchModelsResult {
  success: boolean;
  models?: { id: string; name?: string; displayName?: string; inputModalities?: string[] }[];
  error?: string;
}

const PROVIDER_PRESETS: { id: string; label: string; defaultApiUrl: string }[] = [
  { id: 'openai', label: 'OpenAI-compatible', defaultApiUrl: 'https://api.openai.com/v1' },
  { id: 'openrouter', label: 'OpenRouter', defaultApiUrl: 'https://openrouter.ai/api/v1' },
  { id: 'anthropic', label: 'Anthropic', defaultApiUrl: 'https://api.anthropic.com' },
  { id: 'google', label: 'Google AI Studio', defaultApiUrl: 'https://generativelanguage.googleapis.com' },
  { id: 'ollama', label: 'Ollama (local)', defaultApiUrl: 'http://localhost:11434/v1' },
  { id: 'custom', label: 'Custom', defaultApiUrl: '' },
];

// ─── API Definitions ─────────────────────────────────────────────────────────

const updaterAPI: UpdaterAPI = {
  onStateChanged: (callback) => {
    const handler = (_event: Electron.IpcRendererEvent, state: UpdaterState) => {
      callback(state);
    };
    ipcRenderer.on('updater:state-changed', handler);
    // Return unsubscribe function
    return () => {
      ipcRenderer.removeListener('updater:state-changed', handler);
    };
  },
  applyUpdate: () => ipcRenderer.invoke('updater:apply'),
  quitAndInstall: () => ipcRenderer.invoke('updater:quit-and-install'),
  checkForUpdates: () => ipcRenderer.invoke('updater:check-for-updates'),
};

const dialogAPI: DialogAPI = {
  showOpenDialog: () => ipcRenderer.invoke('dialog:open-workspace'),
};

const notificationAPI: NotificationAPI = {
  send: (options) => ipcRenderer.invoke('notification:send', options),
  openSystemPreferences: () => ipcRenderer.invoke('notification:open-system-preferences'),
  onClicked: (callback) => {
    const handler = (_event: Electron.IpcRendererEvent, payload: unknown) => {
      callback(payload);
    };
    ipcRenderer.on('notification:clicked', handler);
    return () => {
      ipcRenderer.removeListener('notification:clicked', handler);
    };
  },
};

const storageAPI: StorageAPI = {
  getItems: () => ipcRenderer.invoke('storage:get-items'),
  updateItems: (changes) => ipcRenderer.invoke('storage:update-items', changes),
  onChanged: (callback) => {
    const handler = (_event: Electron.IpcRendererEvent, changes: Record<string, string | null>) => {
      callback(changes);
    };
    ipcRenderer.on('storage:changed', handler);
    return () => {
      ipcRenderer.removeListener('storage:changed', handler);
    };
  },
  getCustomModels: () => ipcRenderer.invoke('storage:get-custom-models'),
  saveCustomModel: (model) => ipcRenderer.invoke('storage:save-custom-model', model),
  deleteCustomModel: (modelName) => ipcRenderer.invoke('storage:delete-custom-model', modelName),
  testModelConnection: (model) => ipcRenderer.invoke('storage:test-model-connection', model),
  fetchModels: (params) => ipcRenderer.invoke('storage:fetch-models', params),
  getProviders: () => ipcRenderer.invoke('storage:get-providers'),
  saveProvider: (provider) => ipcRenderer.invoke('storage:save-provider', provider),
  deleteProvider: (providerId) => ipcRenderer.invoke('storage:delete-provider', providerId),
  exportProviders: () => ipcRenderer.invoke('storage:export-providers'),
  importProviders: () => ipcRenderer.invoke('storage:import-providers'),
  getDoctorDiagnostics: () => ipcRenderer.invoke('storage:get-doctor-diagnostics'),
};

const logsAPI: LogsAPI = {
  getElectronLogs: () => ipcRenderer.invoke('logs:electron'),
};

const extensionsAPI: ExtensionsAPI = {
  sendAuthorities: (authoritiesMap) => ipcRenderer.invoke('extensions:send-authorities', authoritiesMap),
};

const deepLinkAPI: DeepLinkAPI = {
  onDeepLink: (callback) => {
    const handler = (_event: Electron.IpcRendererEvent, url: string) => {
      callback(url);
    };
    ipcRenderer.on('deep-link', handler);
    return () => {
      ipcRenderer.removeListener('deep-link', handler);
    };
  },
  getStoredDeepLink: () => ipcRenderer.invoke('deep-link:get-stored'),
};

const agentAPI: AgentAPI = {
  updateActiveAgentCount: (count) => ipcRenderer.invoke('agent:update-active-count', count),
};

const electronNativeAPI: ElectronNativeAPI = {
  getZoomLevel: () => webFrame.getZoomFactor(),
  setTitleBarOverlay: (options) => ipcRenderer.invoke('window:set-title-bar-overlay', options),
  minimize: () => ipcRenderer.invoke('window:minimize'),
  maximize: () => ipcRenderer.invoke('window:maximize'),
  unmaximize: () => ipcRenderer.invoke('window:unmaximize'),
  isMaximized: () => ipcRenderer.invoke('window:is-maximized'),
  close: () => ipcRenderer.invoke('window:close'),
  toggleDevTools: () => ipcRenderer.invoke('window:toggle-devtools'),
  zoomIn: () => {
    const current = webFrame.getZoomLevel();
    webFrame.setZoomLevel(current + 0.5);
  },
  zoomOut: () => {
    const current = webFrame.getZoomLevel();
    webFrame.setZoomLevel(current - 0.5);
  },
  resetZoom: () => {
    webFrame.setZoomLevel(0);
  },
  openExternal: (url) => ipcRenderer.invoke('shell:open-external', url),
};

// ─── Expose all APIs via contextBridge ──────────────────────────────────────

contextBridge.exposeInMainWorld('electronUpdater', updaterAPI);
contextBridge.exposeInMainWorld('dialog', dialogAPI);
contextBridge.exposeInMainWorld('nativeNotifications', notificationAPI);
contextBridge.exposeInMainWorld('nativeStorage', storageAPI);
contextBridge.exposeInMainWorld('logs', logsAPI);
contextBridge.exposeInMainWorld('extensions', extensionsAPI);
contextBridge.exposeInMainWorld('deepLink', deepLinkAPI);
contextBridge.exposeInMainWorld('agent', agentAPI);
contextBridge.exposeInMainWorld('electronNative', electronNativeAPI);

// ─── Renderer Augmentations (for TypeScript global type declarations) ──────

declare global {
  interface Window {
    electronUpdater: UpdaterAPI;
    dialog: DialogAPI;
    nativeNotifications: NotificationAPI;
    nativeStorage: StorageAPI;
    logs: LogsAPI;
    extensions: ExtensionsAPI;
    deepLink: DeepLinkAPI;
    agent: AgentAPI;
    electronNative: ElectronNativeAPI;
  }
}

// ─── Custom Models UI Injection ─────────────────────────────────────────────

window.addEventListener('DOMContentLoaded', () => {
  function findRefreshButton(): HTMLButtonElement | null {
    const buttons = Array.from(document.querySelectorAll('button'));
    return (buttons.find((b) => b.textContent?.trim() === 'Refresh') as HTMLButtonElement) || null;
  }

  interface McpLayout {
    mainContainer: Node;
    headerRow: Element;
    contentBlock: Element | null;
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

  // ─── Provider Icons & Status Helpers ──────────────────────────────
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

  // ─── Legacy duplicate block (lines 414-1697 of pre-refactor) removed ──────────
  // The "Old UI" copy of: renderCustomModelsList, injectCustomModelsSection,
  // ensureAgyTokens, getFocusableElements, openProviderManagerModal,
  // renderList, renderForm, renderModelsList.
  // The Doctor UI versions below (starting at the next function) supersede them.

  const prefersReducedMotion = (): boolean =>
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

  function getProviderIcon(provider: string): string {
    return PROVIDER_ICONS[provider] || PROVIDER_ICONS.custom;
  }

  function getProviderColor(provider: string): string {
    return PROVIDER_COLORS[provider] || PROVIDER_COLORS.custom;
  }

  async function renderCustomModelsList(): Promise<void> {
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
                failedModelDisplayNames.clear();
                document.querySelectorAll('.ag-model-warning').forEach(el => el.remove());
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
            const p = providers.find(prov => prov.provider === model.provider || prov.name === model.provider);
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

  async function injectCustomModelsSection(): Promise<void> {
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

    ensureAgyTokens(); // Ensure Doctor UI CSS tokens are injected

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
      testBtns.forEach(btn => (btn as HTMLButtonElement).click());
    });

    const addModelBtn = document.createElement('button');
    addModelBtn.className = 'agy-btn-primary';
    addModelBtn.innerHTML = `☁️ Provider Manager`;
    addModelBtn.addEventListener('click', () => {
      openProviderManagerModal();
    });

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

  // ─── Helper: Inject design tokens + modal styles (idempotent) ──────────
  function ensureAgyTokens(): void {
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

      /* ── Overlay ────────────────────────────────────────────────── */
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
      @keyframes agy-fade-in {
        from { opacity: 0; }
        to { opacity: 1; }
      }
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

      /* ── Icon button (close) ──────────────── */
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

      /* ── Buttons ────────────────────────────────────────────────── */
      .agy-btn-primary, .agy-btn-secondary, .agy-btn-success, .agy-btn-ghost, .agy-btn-confirm {
        font-family: var(--agy-font);
        border-radius: var(--agy-radius-md);
        cursor: pointer; font-weight: 500;
        transition: all 120ms ease;
        padding: 6px 12px; font-size: 12.5px;
        display: inline-flex; align-items: center; justify-content: center; gap: 6px;
      }
      .agy-btn-primary {
        background: var(--agy-accent); border: 1px solid transparent; color: white;
      }
      .agy-btn-primary:hover:not(:disabled) { background: var(--agy-accent-hover); }
      .agy-btn-secondary {
        background: var(--agy-bg-input); border: 1px solid var(--agy-border-strong); color: var(--agy-ink-primary);
      }
      .agy-btn-secondary:hover:not(:disabled) { background: var(--agy-bg-input-hover); border-color: var(--agy-ink-muted); }
      .agy-btn-ghost {
        background: transparent; border: 1px solid transparent; color: var(--agy-ink-secondary);
      }
      .agy-btn-ghost:hover:not(:disabled) { background: var(--agy-bg-input); color: var(--agy-ink-primary); }
      .agy-btn-success {
        background: var(--agy-success); border: 1px solid transparent; color: white;
      }
      .agy-btn-success:hover:not(:disabled) { background: var(--agy-success-hover); }
      .agy-btn-danger, .agy-btn-confirm {
        background: var(--agy-danger); color: white; border: 1px solid transparent;
      }
      .agy-btn-danger:hover:not(:disabled), .agy-btn-confirm:hover:not(:disabled) {
        background: var(--agy-danger-hover);
      }
      button:focus-visible, input:focus-visible, select:focus-visible {
        outline: 2px solid var(--agy-accent-hover); outline-offset: 2px;
      }

      /* ── List view ──────────────────────────────────────────────── */
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

      /* ── Form view (Doctor UI Style) ────────────────────────────── */
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
      
      /* ── Responsive ─────────────────────────────────────────────── */
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

      /* ── Reduced motion ─────────────────────────────────────────── */
      @media (prefers-reduced-motion: reduce) {
        .agy-overlay, .agy-modal, .agy-btn-primary, .agy-btn-secondary,
        .agy-btn-success, .agy-btn-ghost, .agy-icon-btn, .agy-input,
        .agy-provider-row, .agy-form-error,
        .ag-health-dot, .ag-health-refresh {
          transition: none !important;
          animation: none !important;
        }
      }

      /* ── Dropdown Health Indicators ──────────────────────────────── */
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
      .ag-health-dot--healthy {
        background-color: #22c55e;
        animation: ag-pulse-healthy 2.5s ease-in-out infinite;
      }
      .ag-health-dot--error {
        background-color: #ef4444;
        animation: ag-pulse-error 1.8s ease-in-out infinite;
      }
      .ag-health-dot--unknown {
        background-color: #6b7280;
        opacity: 0.7;
      }
      .ag-health-refresh {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 18px; height: 18px;
        margin-left: 4px;
        padding: 2px;
        border: none;
        background: transparent;
        color: #a1a1aa;
        cursor: pointer;
        border-radius: 50%;
        transition: color 150ms ease, background-color 150ms ease;
        vertical-align: middle;
        flex-shrink: 0;
      }
      .ag-health-refresh:hover {
        color: #f4f4f5;
        background-color: rgba(63, 63, 70, 0.6);
      }
      .ag-health-refresh--spinning svg {
        animation: ag-spin 0.8s linear infinite;
      }
      .ag-health-tooltip {
        position: absolute;
        z-index: 100001;
        background: #1a1a1a;
        border: 1px solid #3f3f46;
        border-left: 3px solid #ef4444;
        border-radius: 6px;
        padding: 10px 14px;
        max-width: 320px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        font-size: 12px;
        color: #e5e5e5;
        line-height: 1.5;
        box-shadow: 0 8px 24px rgba(0,0,0,0.4);
        animation: ag-fade-in 150ms ease-out;
        pointer-events: auto;
      }
      .ag-health-tooltip__title {
        font-weight: 600;
        font-size: 12px;
        margin-bottom: 4px;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .ag-health-tooltip__msg {
        color: #a1a1aa;
        font-size: 11px;
        margin-bottom: 8px;
      }
      .ag-health-tooltip__action {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-size: 11px;
        font-weight: 500;
        color: #3b82f6;
        cursor: pointer;
        background: none;
        border: none;
        padding: 0;
        text-decoration: none;
      }
      .ag-health-tooltip__action:hover {
        color: #60a5fa;
        text-decoration: underline;
      }
      .ag-dropdown-error-overlay {
        opacity: 0.55;
        pointer-events: auto;
        position: relative;
      }
    `;
    document.head.appendChild(style);
  }

  // ─── Helper: focusable elements inside a container ──────────────────
  function getFocusableElements(root: HTMLElement): HTMLElement[] {
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

    function openProviderManagerModal(existingProvider?: ProviderFileEntry): void {
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

    // ─── Header ───────────────────────────────────────────────────────────
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

    // ─── Body ─────────────────────────────────────────────────────────────
    const body = document.createElement('div');
    body.className = 'agy-modal-body';

    const formContainer = document.createElement('form');
    formContainer.id = 'agy-addModelForm';
    body.appendChild(formContainer);

    // ─── Footer ───────────────────────────────────────────────────────────
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
        return;
      }
    };
    document.addEventListener('keydown', escHandler);

    if (prefersReducedMotion()) {
      overlay.classList.add('agy-no-motion');
    } else {
      overlay.classList.add('agy-anim-in');
    }

    // ─── Render Form ──────────────────────────────────────────────────────
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
      i.value = state[key] || '';
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

  // Efficient DOM tracking via MutationObserver — instead of setInterval
  let injectionObserver: MutationObserver | null = null;
  let injectionDebounceTimer: ReturnType<typeof setTimeout> | null = null;

  function setupInjectionObserver(): void {
    // Try immediately first
    void injectCustomModelsSection();

    // If already added, no need for observer
    if (document.getElementById('agy-custom-models-section')) return;

    // Set up observer: watch all changes under document.body
    injectionObserver = new MutationObserver(() => {
      // Debounce: coalesce consecutive mutations into a single attempt
      if (injectionDebounceTimer) clearTimeout(injectionDebounceTimer);
      injectionDebounceTimer = setTimeout(async () => {
        await injectCustomModelsSection();
        // If successfully injected, stop observing
        if (document.getElementById('agy-custom-models-section')) {
          if (injectionObserver) {
            injectionObserver.disconnect();
            injectionObserver = null;
          }
        }
      }, 200);
    });

    injectionObserver.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  // URL tracking for re-injection on SPA page transitions
  let lastUrl = location.href;
  setInterval(() => {
    const currentUrl = location.href;
    if (currentUrl !== lastUrl) {
      lastUrl = currentUrl;
      // Page changed — clean up previous observer and re-initialize
      if (injectionObserver) {
        injectionObserver.disconnect();
        injectionObserver = null;
      }
      // Re-initialize after a short delay (for new DOM to render)
      setTimeout(setupInjectionObserver, 500);
    }
  }, 1500);

  // --- Contextual Error Toast UI ----------------------------------------

  function showErrorToast(diagnostic: any) {
    if (!document || !document.body) return;

    const existingToastId = `agy-toast-${diagnostic.errorType}`;
    const existing = document.getElementById(existingToastId);
    if (existing) {
      existing.style.animation = 'none';
      void existing.offsetWidth; // trigger reflow
      existing.style.animation = 'agy-toast-shake 0.4s ease-in-out, agy-toast-fade-in 0.3s ease-out';
      return;
    }

    let container = document.getElementById('agy-toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'agy-toast-container';
      container.style.cssText = `
        position: fixed;
        top: 24px;
        right: 24px;
        z-index: 9999999;
        display: flex;
        flex-direction: column;
        gap: 12px;
        max-width: 420px;
        width: calc(100vw - 48px);
        pointer-events: none;
      `;
      document.body.appendChild(container);

      const style = document.createElement('style');
      style.textContent = `
        @keyframes agy-toast-fade-in {
          from { opacity: 0; transform: translateY(-20px) scale(0.95); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes agy-toast-fade-out {
          from { opacity: 1; transform: scale(1); }
          to { opacity: 0; transform: scale(0.9); }
        }
        @keyframes agy-toast-shake {
          0%, 100% { transform: translateX(0); }
          20%, 60% { transform: translateX(-6px); }
          40%, 80% { transform: translateX(6px); }
        }
        @media (prefers-reduced-motion: reduce) {
          .agy-toast-el { animation: none !important; }
        }
      `;
      document.head.appendChild(style);
    }

    const toast = document.createElement('div');
    toast.id = existingToastId;
    toast.className = 'agy-toast-el';
    toast.style.cssText = `
      background-color: #18181b;
      border: 1px solid #27272a;
      border-radius: 12px;
      padding: 16px 20px;
      box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.5), 0 4px 6px -2px rgba(0, 0, 0, 0.5);
      color: #f4f4f5;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      pointer-events: auto;
      animation: agy-toast-fade-in 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
      position: relative;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      gap: 10px;
    `;

    let borderLeftColor = '#a855f7';
    let iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>`;
    
    if (diagnostic.errorType === 'billing') {
      borderLeftColor = '#ef4444';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg>`;
    } else if (diagnostic.errorType === 'auth' || diagnostic.errorType === 'forbidden') {
      borderLeftColor = '#f97316';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
    } else if (diagnostic.errorType === 'rate_limit') {
      borderLeftColor = '#eab308';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`;
    } else if (diagnostic.errorType === 'timeout') {
      borderLeftColor = '#3b82f6';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`;
    } else if (diagnostic.errorType === 'network' || diagnostic.errorType === 'dns') {
      borderLeftColor = '#64748b';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12.55a11 11 0 0 1 14.08 0M1.42 9a16 16 0 0 1 21.16 0M8.59 16a7.5 7.5 0 0 1 6.82 0M12 20h.01"/></svg>`;
    } else if (diagnostic.errorType === 'server') {
      borderLeftColor = '#ef4444';
      iconHtml = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`;
    }

    const accentLine = document.createElement('div');
    accentLine.style.cssText = `
      position: absolute;
      left: 0;
      top: 0;
      bottom: 0;
      width: 4px;
      background-color: ${borderLeftColor};
    `;
    toast.appendChild(accentLine);

    const mainRow = document.createElement('div');
    mainRow.style.cssText = `
      display: flex;
      gap: 12px;
      align-items: flex-start;
    `;

    const iconContainer = document.createElement('div');
    iconContainer.style.cssText = `
      color: ${borderLeftColor};
      display: flex;
      align-items: center;
      justify-content: center;
      margin-top: 2px;
    `;
    iconContainer.innerHTML = iconHtml;
    mainRow.appendChild(iconContainer);

    const textContainer = document.createElement('div');
    textContainer.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: 4px;
      flex: 1;
    `;

    const title = document.createElement('div');
    title.style.cssText = `
      font-size: 14px;
      font-weight: 600;
      color: #f4f4f5;
    `;
    title.textContent = diagnostic.title;
    textContainer.appendChild(title);

    const desc = document.createElement('div');
    desc.style.cssText = `
      font-size: 12px;
      color: #a1a1aa;
      line-height: 1.4;
    `;
    desc.textContent = diagnostic.message;
    textContainer.appendChild(desc);

    mainRow.appendChild(textContainer);

    const closeBtn = document.createElement('button');
    closeBtn.textContent = '×';
    closeBtn.style.cssText = `
      background: transparent;
      border: none;
      color: #71717a;
      cursor: pointer;
      font-size: 18px;
      line-height: 1;
      padding: 0 4px;
      margin-top: -2px;
      transition: color 0.15s ease;
    `;
    closeBtn.addEventListener('mouseenter', () => closeBtn.style.color = '#f4f4f5');
    closeBtn.addEventListener('mouseleave', () => closeBtn.style.color = '#71717a');
    
    let autoDismissTimer: ReturnType<typeof setTimeout> | null = null;
    const dismissToast = () => {
      if (autoDismissTimer) {
        clearTimeout(autoDismissTimer);
      }
      toast.style.animation = 'agy-toast-fade-out 0.25s ease-in forwards';
      setTimeout(() => toast.remove(), 250);
    };
    closeBtn.addEventListener('click', dismissToast);
    mainRow.appendChild(closeBtn);

    toast.appendChild(mainRow);

    if (diagnostic.suggestions && diagnostic.suggestions.length > 0) {
      const suggBox = document.createElement('div');
      suggBox.style.cssText = `
        background-color: #1c1c1f;
        border-radius: 6px;
        padding: 10px 12px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        margin-left: 30px;
      `;

      const suggTitle = document.createElement('div');
      suggTitle.style.cssText = `
        font-size: 10px;
        font-weight: 600;
        color: #71717a;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      `;
      suggTitle.textContent = 'Suggested Actions';
      suggBox.appendChild(suggTitle);

      const suggList = document.createElement('ul');
      suggList.style.cssText = `
        margin: 0;
        padding-left: 16px;
        font-size: 11px;
        color: #d4d4d8;
        display: flex;
        flex-direction: column;
        gap: 4px;
      `;

      diagnostic.suggestions.forEach((sug: string) => {
        const item = document.createElement('li');
        item.textContent = sug;
        suggList.appendChild(item);
      });
      suggBox.appendChild(suggList);
      toast.appendChild(suggBox);
    }

    const actionsRow = document.createElement('div');
    actionsRow.style.cssText = `
      display: flex;
      justify-content: flex-end;
      gap: 8px;
      margin-top: 4px;
      margin-left: 30px;
    `;

    if (diagnostic.errorType === 'auth') {
      const configBtn = document.createElement('button');
      configBtn.textContent = 'Configure API Key';
      configBtn.style.cssText = `
        background-color: #3b82f6;
        border: none;
        color: white;
        font-size: 11px;
        font-weight: 500;
        padding: 5px 10px;
        border-radius: 4px;
        cursor: pointer;
        transition: background-color 0.15s ease;
      `;
      configBtn.addEventListener('mouseenter', () => configBtn.style.backgroundColor = '#2563eb');
      configBtn.addEventListener('mouseleave', () => configBtn.style.backgroundColor = '#3b82f6');
      configBtn.addEventListener('click', () => {
        openProviderManagerModal();
        dismissToast();
      });
      actionsRow.appendChild(configBtn);
    }

    if (diagnostic.actionUrl) {
      const billingBtn = document.createElement('button');
      billingBtn.textContent = 'Manage Billing';
      billingBtn.style.cssText = `
        background-color: #ef4444;
        border: none;
        color: white;
        font-size: 11px;
        font-weight: 500;
        padding: 5px 10px;
        border-radius: 4px;
        cursor: pointer;
        transition: background-color 0.15s ease;
      `;
      billingBtn.addEventListener('mouseenter', () => billingBtn.style.backgroundColor = '#dc2626');
      billingBtn.addEventListener('mouseleave', () => billingBtn.style.backgroundColor = '#ef4444');
      billingBtn.addEventListener('click', () => {
        window.open(diagnostic.actionUrl, '_blank');
        dismissToast();
      });
      actionsRow.appendChild(billingBtn);
    }

    const refreshBtn = findRefreshButton();
    if (refreshBtn && (diagnostic.errorType === 'rate_limit' || diagnostic.errorType === 'server' || diagnostic.errorType === 'network')) {
      const retryBtn = document.createElement('button');
      retryBtn.textContent = 'Retry Request';
      retryBtn.style.cssText = `
        background-color: #27272a;
        border: 1px solid #3f3f46;
        color: #d4d4d8;
        font-size: 11px;
        font-weight: 500;
        padding: 5px 10px;
        border-radius: 4px;
        cursor: pointer;
        transition: all 0.15s ease;
      `;
      retryBtn.addEventListener('mouseenter', () => {
        retryBtn.style.backgroundColor = '#3f3f46';
        retryBtn.style.borderColor = '#52525b';
      });
      retryBtn.addEventListener('mouseleave', () => {
        retryBtn.style.backgroundColor = '#27272a';
        retryBtn.style.borderColor = '#3f3f46';
      });
      retryBtn.addEventListener('click', () => {
        refreshBtn.click();
        dismissToast();
      });
      actionsRow.appendChild(retryBtn);
    }

    if (actionsRow.children.length > 0) {
      toast.appendChild(actionsRow);
    }

    container.appendChild(toast);

    if (diagnostic.errorType !== 'auth' && diagnostic.errorType !== 'billing') {
      autoDismissTimer = setTimeout(dismissToast, 10000);
    }
  }

  // --- Network Interceptor for Model Injection & Diagnostics -----------

  const customModelsCache: { models: any[]; ts: number } = { models: [], ts: 0 };

  async function getCustomModelsForInjection(): Promise<any[]> {
    if (Date.now() - customModelsCache.ts < 30000) return customModelsCache.models;
    try {
      const providers = await storageAPI.getProviders();
      const injectedModels: any[] = [];
      providers.forEach(p => {
        if (!p.enabled) return;
        p.models.forEach((m: any) => {
          if (!m.enabled) return;
          injectedModels.push({
            name: m.id,
            displayName: m.displayName || m.id,
            provider: p.provider,
            apiKey: p.apiKey,
            apiUrl: p.apiUrl,
            externalModelName: m.id,
            allowUnauthorized: p.allowUnauthorized,
            inputModalities: ['text']
          });
        });
      });
      customModelsCache.models = injectedModels;
      customModelsCache.ts = Date.now();
    } catch { /* ignore */ }
    return customModelsCache.models;
  }

  // --- Advanced UX Mirroring (Persistent Banner & Model Selector Warnings) ---

  interface ModelHealth {
    status: 'healthy' | 'error' | 'unknown';
    errorType?: string;
    trippedAt?: number;
    failures?: number;
    diagnostic?: any;
    lastChecked: number;
  }
  const modelHealthState = new Map<string, ModelHealth>();
  const failedModelDisplayNames = new Set<string>();

  // --- Proxy port auto-detection ---
  // We sniff the proxy port from intercepted XHR/fetch URLs that go to 127.0.0.1
  let detectedProxyPort = 0;

  function detectProxyPort(url: string): void {
    if (detectedProxyPort > 0) return;
    try {
      const m = url.match(/127\.0\.0\.1:(\d+)/);
      if (m) {
        detectedProxyPort = parseInt(m[1], 10);
      }
    } catch { /* ignore */ }
  }

  // --- Fetch health from proxy /model-health endpoint ---
  async function fetchModelHealthFromProxy(): Promise<Record<string, { status: string; errorType?: string; trippedAt?: number; failures?: number }> | null> {
    if (detectedProxyPort <= 0) return null;
    try {
      const resp = await window.fetch(`http://127.0.0.1:${detectedProxyPort}/model-health`, {
        method: 'GET',
        signal: AbortSignal.timeout(3000),
      });
      if (!resp.ok) return null;
      const data = await resp.json();
      return data.models || null;
    } catch {
      return null;
    }
  }

  // --- Build a display-name → model-id lookup for BOTH native and custom models ---
  // Key = displayName, Value = { id, isCustom }
  const allKnownModels = new Map<string, { id: string; isCustom: boolean }>();

  // Called from XHR/fetch interceptors when we see GetAvailableModels
  function ingestModelsFromResponse(modelsObj: Record<string, any>) {
    if (!modelsObj) return;
    for (const [key, val] of Object.entries(modelsObj)) {
      if (val && typeof val === 'object' && typeof val.displayName === 'string') {
        const id = val.model || val.requestedModel || val.planModel || key;
        const isCustom = id.startsWith('MODEL_PLACEHOLDER_M');
        allKnownModels.set(val.displayName, { id, isCustom });
      }
    }
  }

  async function refreshModelHealthState(): Promise<void> {
    try {
      // 1. Fetch custom models from proxy config
      const customModels = await getCustomModelsForInjection();
      if (customModels && customModels.length > 0) {
        for (const m of customModels) {
          const dn = m.displayName || m.name;
          const pid = generateModelPlaceholderId(m);
          allKnownModels.set(dn, { id: pid, isCustom: true });
        }
      }

      // 2. Fetch live health for custom models from proxy
      const proxyHealth = await fetchModelHealthFromProxy();
      if (proxyHealth && customModels) {
        failedModelDisplayNames.clear();
        for (const m of customModels) {
          const dn = m.displayName || m.name;
          const pid = generateModelPlaceholderId(m);
          const ph = proxyHealth[pid];
          if (ph) {
            const health: ModelHealth = {
              status: ph.status === 'error' ? 'error' : 'healthy',
              errorType: ph.errorType,
              trippedAt: ph.trippedAt,
              failures: ph.failures,
              lastChecked: Date.now(),
            };
            modelHealthState.set(pid, health);
            if (ph.status === 'error') failedModelDisplayNames.add(dn);
          } else {
            modelHealthState.set(pid, { status: 'healthy', lastChecked: Date.now() });
          }
        }
      } else if (customModels) {
        // Proxy unreachable: mark custom models as unknown
        for (const m of customModels) {
          const pid = generateModelPlaceholderId(m);
          if (!modelHealthState.has(pid)) {
            modelHealthState.set(pid, { status: 'unknown', lastChecked: Date.now() });
          }
        }
      }
    } catch { /* ignore */ }
  }

  // --- SVG constants ---
  const SVG_REFRESH = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>`;
  const SVG_ALERT = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>`;
  const SVG_CHECK = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#22c55e" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`;

  // --- Provider Logo Helper ---
  function getProviderLogo(name: string): string {
    const norm = name.toLowerCase();
    if (norm.includes('deepseek')) return '🐋';
    if (norm.includes('openai') || norm.includes('gpt')) return '🟢';
    if (norm.includes('anthropic') || norm.includes('claude')) return '🟠';
    if (norm.includes('ollama')) return '🦙';
    if (norm.includes('groq')) return '⚡';
    if (norm.includes('mistral')) return '🔮';
    if (norm.includes('kimi') || norm.includes('moonshot')) return '🌙';
    if (norm.includes('openrouter')) return '🌐';
    if (norm.includes('nvidia') || norm.includes('nim')) return '💚';
    return '🤖';
  }

  // --- Auto-detect Local Ollama Service ---
  async function checkOllamaLocalAutoDetect(): Promise<void> {
    try {
      const resp = await window.fetch('http://127.0.0.1:11434/api/tags', {
        method: 'GET',
        signal: AbortSignal.timeout(2000),
      });
      if (resp.ok) {
        const providers = await storageAPI.getProviders();
        const hasOllama = providers.some((p) => p.provider === 'ollama' || p.apiUrl.includes('11434'));
        if (!hasOllama) {
          showErrorToast({
            title: '🦙 Ollama Local Detected',
            message: 'Ollama is running on your machine. Would you like to connect it to Antigravity in 1 click?',
            suggestions: ['Click "Configure Ollama" below to auto-register your local LLMs.'],
            retryable: false,
            severity: 'info',
            errorType: 'unknown',
          });
        }
      }
    } catch { /* ignore */ }
  }

  // Trigger Ollama detection check on startup
  setTimeout(checkOllamaLocalAutoDetect, 4000);

  // --- Error type to human-friendly label ---
  function errorTypeLabel(errorType?: string): string {
    switch (errorType) {
      case 'billing': return '💳 Billing / Quota';
      case 'auth': return '🔑 Authentication';
      case 'forbidden': return '🚫 Access Denied';
      case 'rate_limit': return '⏱ Rate Limited';
      case 'server': return '🖥 Server Error';
      case 'network': return '🌐 Network Error';
      case 'dns': return '🔍 DNS Error';
      case 'timeout': return '⏳ Timeout';
      default: return '⚠ Error';
    }
  }

  // --- Create/update health dot for a model item ---
  function createHealthDot(health: ModelHealth): HTMLSpanElement {
    const dot = document.createElement('span');
    dot.className = 'ag-health-dot';
    if (health.status === 'healthy') {
      dot.classList.add('ag-health-dot--healthy');
      dot.title = '✅ Online';
    } else if (health.status === 'error') {
      dot.classList.add('ag-health-dot--error');
      dot.title = `❌ ${errorTypeLabel(health.errorType)}`;
    } else {
      dot.classList.add('ag-health-dot--unknown');
      dot.title = '⏳ Status unknown';
    }
    return dot;
  }

  // --- Create refresh button ---
  function createRefreshButton(onRefresh: () => void): HTMLButtonElement {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'ag-health-refresh';
    btn.title = 'Refresh health status';
    btn.innerHTML = SVG_REFRESH;
    btn.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      btn.classList.add('ag-health-refresh--spinning');
      onRefresh();
      setTimeout(() => btn.classList.remove('ag-health-refresh--spinning'), 1500);
    };
    return btn;
  }

  // --- Show rich error tooltip ---
  function showHealthTooltip(anchor: HTMLElement, health: ModelHealth, displayName: string): void {
    // Remove any existing tooltip
    const existing = document.querySelector('.ag-health-tooltip');
    if (existing) existing.remove();

    if (health.status !== 'error') return;

    const tooltip = document.createElement('div');
    tooltip.className = 'ag-health-tooltip';

    const title = document.createElement('div');
    title.className = 'ag-health-tooltip__title';
    title.innerHTML = `${SVG_ALERT} ${errorTypeLabel(health.errorType)}`;
    tooltip.appendChild(title);

    const msg = document.createElement('div');
    msg.className = 'ag-health-tooltip__msg';
    if (health.diagnostic?.message) {
      msg.textContent = health.diagnostic.message;
    } else if (health.errorType) {
      msg.textContent = `This model is experiencing ${health.errorType} issues. It may not respond correctly.`;
    } else {
      msg.textContent = `Model "${displayName}" is currently unavailable.`;
    }
    tooltip.appendChild(msg);

    const action = document.createElement('button');
    action.className = 'ag-health-tooltip__action';
    action.textContent = '🔧 Fix in Provider Manager';
    action.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      tooltip.remove();
      openProviderManagerModal();
    };
    tooltip.appendChild(action);

    // Position tooltip near the anchor
    document.body.appendChild(tooltip);
    const rect = anchor.getBoundingClientRect();
    tooltip.style.top = `${rect.bottom + 4}px`;
    tooltip.style.left = `${Math.max(8, rect.left - 60)}px`;

    // Auto-dismiss on click outside
    const dismiss = (ev: MouseEvent) => {
      if (!tooltip.contains(ev.target as Node) && !anchor.contains(ev.target as Node)) {
        tooltip.remove();
        document.removeEventListener('click', dismiss, true);
      }
    };
    setTimeout(() => document.addEventListener('click', dismiss, true), 50);
  }

  // --- Dropdown health polling ---
  let healthPollingInterval: ReturnType<typeof setInterval> | null = null;
  let dropdownCurrentlyOpen = false;

  function startHealthPolling(): void {
    if (healthPollingInterval) return;
    dropdownCurrentlyOpen = true;
    healthPollingInterval = setInterval(async () => {
      if (!dropdownCurrentlyOpen) {
        stopHealthPolling();
        return;
      }
      await refreshModelHealthState();
      updateDropdownHealthBadges();
    }, 10_000); // Poll every 10 seconds
  }

  function stopHealthPolling(): void {
    dropdownCurrentlyOpen = false;
    if (healthPollingInterval) {
      clearInterval(healthPollingInterval);
      healthPollingInterval = null;
    }
  }

  // --- Update all health badges in current dropdown ---
  function updateDropdownHealthBadges(): void {
    if (allKnownModels.size === 0) return;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    let node;
    while ((node = walker.nextNode())) {
      const text = node.nodeValue?.trim();
      if (!text || !allKnownModels.has(text)) continue;

      const parent = node.parentNode as HTMLElement;
      if (!parent) continue;

      const modelInfo = allKnownModels.get(text)!;
      // Default to healthy for native models unless we logged an error
      const health = modelHealthState.get(modelInfo.id) || { status: 'healthy', lastChecked: Date.now() };

      // Remove existing indicators
      parent.querySelectorAll('.ag-health-dot, .ag-health-refresh, .ag-model-warning, .ag-status-badge').forEach(el => el.remove());
      parent.classList.remove('ag-dropdown-error-overlay');

      // Add health dot (applies to ALL models)
      const dot = createHealthDot(health);
      parent.appendChild(dot);

      // For error models: add visual dimming, tooltip on hover
      if (health.status === 'error') {
        parent.classList.add('ag-dropdown-error-overlay');
        const showTip = () => showHealthTooltip(parent, health, text);
        dot.addEventListener('mouseenter', showTip);
        dot.style.cursor = 'pointer';
      }

      // Add refresh button ONLY for custom models (native models can't be pinged by proxy)
      if (modelInfo.isCustom) {
        const refreshBtn = createRefreshButton(async () => {
          await refreshModelHealthState();
          updateDropdownHealthBadges();
        });
        parent.appendChild(refreshBtn);
      }
    }
  }

  // --- Dropdown observer: detect opens, inject health UI, manage polling ---
  let dropdownTimeout: any;
  const dropdownObserver = new MutationObserver((mutations) => {
    let hasNewNodes = false;
    for (const m of mutations) {
      if (m.addedNodes.length > 0) {
        hasNewNodes = true;
        break;
      }
    }
    if (!hasNewNodes) return;

    if (dropdownTimeout) clearTimeout(dropdownTimeout);
    dropdownTimeout = setTimeout(async () => {
      // Detect any dropdown or popup menu element in VS Code / Electron webview
      const dropdownMenu = document.querySelector(
        '[role="listbox"], [role="menu"], .monaco-select-box-dropdown-container, .dropdown-menu, .monaco-menu-container, .action-menu-container, .select-box-dropdown'
      );

      if (dropdownMenu) {
        // Dropdown just opened — inject refresh bar if not already there
        if (!dropdownMenu.querySelector('.ag-dropdown-refresh-bar')) {
          const refreshBar = document.createElement('div');
          refreshBar.className = 'ag-dropdown-refresh-bar';
          refreshBar.style.cssText = `
            padding: 6px 12px;
            background: #141416;
            border-bottom: 1px solid #2a2a2e;
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 12px;
            color: #a1a1aa;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          `;

          const label = document.createElement('span');
          label.style.cssText = 'display: flex; align-items: center; gap: 6px; font-weight: 500;';
          label.innerHTML = `${SVG_CHECK} Models Health`;
          refreshBar.appendChild(label);

          const refreshBtn = createRefreshButton(async () => {
            const lbl = refreshBar.querySelector('span')!;
            lbl.innerHTML = `⏳ Checking...`;
            await refreshModelHealthState();
            updateDropdownHealthBadges();
            lbl.innerHTML = `${SVG_CHECK} Models Health`;
          });
          refreshBar.appendChild(refreshBtn);

          dropdownMenu.insertBefore(refreshBar, dropdownMenu.firstChild);
        }

        // Initial health check + badge injection
        await refreshModelHealthState();
        updateDropdownHealthBadges();

        // Start live polling while dropdown is open
        startHealthPolling();

        // Watch for dropdown close (element removal)
        const closeObserver = new MutationObserver(() => {
          if (!document.querySelector('[role="listbox"], .monaco-select-box-dropdown-container, .dropdown-menu')) {
            stopHealthPolling();
            // Clean up tooltips
            document.querySelectorAll('.ag-health-tooltip').forEach(el => el.remove());
            closeObserver.disconnect();
          }
        });
        closeObserver.observe(document.body, { childList: true, subtree: true });
      } else {
        // Not a dropdown event, but might be model text appearing elsewhere
        // Update badges if we have health data
        if (modelHealthState.size > 0 && allKnownModels.size > 0) {
          updateDropdownHealthBadges();
        }
      }
    }, 150); // Debounce
  });

  if (document && document.body) {
    dropdownObserver.observe(document.body, { childList: true, subtree: true });
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      dropdownObserver.observe(document.body, { childList: true, subtree: true });
    });
  }

  function showPersistentBanner(diagnostic: any) {
    if (!document || !document.body) return;
    
    const existing = document.getElementById('agy-persistent-banner');
    if (existing) {
      existing.style.animation = 'none';
      void existing.offsetWidth;
      existing.style.animation = 'agy-toast-shake 0.4s ease-in-out';
      return;
    }

    const textareas = document.querySelectorAll('textarea');
    let chatInput: HTMLElement | null = null;
    for (const ta of Array.from(textareas)) {
      if (ta.getBoundingClientRect().height > 10) {
        chatInput = ta;
        if (ta.placeholder && (ta.placeholder.includes('Ask') || ta.placeholder.includes('Type'))) {
          break;
        }
      }
    }
    
    if (!chatInput) {
      showErrorToast(diagnostic); // fallback
      return;
    }

    let container = chatInput.parentElement;
    while (container && container.tagName !== 'BODY') {
      if (window.getComputedStyle(container).position === 'relative') break;
      container = container.parentElement;
    }
    if (!container || container.tagName === 'BODY') container = chatInput.parentElement;

    const banner = document.createElement('div');
    banner.id = 'agy-persistent-banner';
    banner.style.cssText = `
      background-color: #1a1a1a;
      border: 1px solid #333;
      border-radius: 8px;
      padding: 12px 16px;
      margin-bottom: 12px;
      color: #e5e5e5;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      gap: 12px;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
      position: relative;
      z-index: 100;
    `;

    const headerRow = document.createElement('div');
    headerRow.style.cssText = `display: flex; align-items: center; gap: 8px;`;
    
    const icon = document.createElement('div');
    icon.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>`;
    
    const title = document.createElement('div');
    title.style.cssText = `font-weight: 600; font-size: 13px;`;
    title.textContent = diagnostic.title || 'Model quota reached';
    
    headerRow.appendChild(icon);
    headerRow.appendChild(title);
    banner.appendChild(headerRow);

    const desc = document.createElement('div');
    desc.style.cssText = `font-size: 12px; color: #a3a3a3; line-height: 1.4;`;
    desc.textContent = diagnostic.message + ' To continue using this model now, check your provider billing or API key.';
    banner.appendChild(desc);

    const actionsRow = document.createElement('div');
    actionsRow.style.cssText = `display: flex; justify-content: flex-end; gap: 8px; align-items: center;`;

    const dismissBtn = document.createElement('button');
    dismissBtn.textContent = 'Dismiss';
    dismissBtn.style.cssText = `
      background-color: #333; border: none; color: #e5e5e5; font-size: 12px; padding: 6px 12px; border-radius: 4px; cursor: pointer;
    `;
    dismissBtn.addEventListener('mouseenter', () => dismissBtn.style.backgroundColor = '#404040');
    dismissBtn.addEventListener('mouseleave', () => dismissBtn.style.backgroundColor = '#333');
    dismissBtn.onclick = () => banner.remove();
    actionsRow.appendChild(dismissBtn);

    if (diagnostic.actionUrl) {
      const actionBtn = document.createElement('button');
      actionBtn.textContent = diagnostic.errorType === 'auth' ? 'Configure API Key' : 'Manage Billing';
      actionBtn.style.cssText = `
        background-color: #0284c7; border: none; color: white; font-size: 12px; padding: 6px 12px; border-radius: 4px; cursor: pointer;
      `;
      actionBtn.addEventListener('mouseenter', () => actionBtn.style.backgroundColor = '#0369a1');
      actionBtn.addEventListener('mouseleave', () => actionBtn.style.backgroundColor = '#0284c7');
      actionBtn.onclick = () => {
        if (diagnostic.errorType === 'auth') {
          openProviderManagerModal();
        } else {
          window.open(diagnostic.actionUrl, '_blank');
        }
        banner.remove();
      };
      actionsRow.appendChild(actionBtn);
    } else if (diagnostic.errorType === 'auth') {
      const actionBtn = document.createElement('button');
      actionBtn.textContent = 'Configure API Key';
      actionBtn.style.cssText = `
        background-color: #0284c7; border: none; color: white; font-size: 12px; padding: 6px 12px; border-radius: 4px; cursor: pointer;
      `;
      actionBtn.addEventListener('mouseenter', () => actionBtn.style.backgroundColor = '#0369a1');
      actionBtn.addEventListener('mouseleave', () => actionBtn.style.backgroundColor = '#0284c7');
      actionBtn.onclick = () => { openProviderManagerModal(); banner.remove(); };
      actionsRow.appendChild(actionBtn);
    }

    banner.appendChild(actionsRow);

    if (container && container.parentElement) {
      container.parentElement.insertBefore(banner, container);
    }
  }

  async function handleModelError(url: string, diagnostic: any) {
    const match = url.match(/models\/([^:/]+)/);
    const modelId = match ? match[1] : null;

    if (diagnostic.errorType === 'billing' || diagnostic.errorType === 'auth' || diagnostic.errorType === 'forbidden') {
      if (modelId) {
        let displayName = modelId;
        // Find the displayName from allKnownModels
        for (const [dn, info] of allKnownModels.entries()) {
          if (info.id === modelId) {
            displayName = dn;
            break;
          }
        }
        
        failedModelDisplayNames.add(displayName);
        allKnownModels.set(displayName, { id: modelId, isCustom: modelId.startsWith('MODEL_PLACEHOLDER_M') });
        modelHealthState.set(modelId, {
          status: 'error',
          errorType: diagnostic.errorType,
          lastChecked: Date.now(),
          diagnostic,
        });
        // Immediately update dropdown badges if visible
        updateDropdownHealthBadges();
      }
      showPersistentBanner(diagnostic);
    } else {
      showErrorToast(diagnostic);
    }
  }

  // Intercept XHR to inject custom models and capture errors
  const origXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (
    method: string,
    url: string | URL,
    async?: boolean,
    username?: string | null,
    password?: string | null,
  ) {
    (this as any)._agy_url = typeof url === 'string' ? url : url.toString();
    (this as any)._agy_method = method;
    return origXHROpen.call(this, method, url, async as boolean, username, password);
  };

  const origXHRSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body?: Document | XMLHttpRequestBodyInit | null) {
    const xhr = this;
    const url: string = (xhr as any)._agy_url || '';
    detectProxyPort(url);

    if (url.includes('GetAvailableModels') || url.includes('fetchAvailableModels')) {
      const origOnReady = xhr.onreadystatechange;
      xhr.onreadystatechange = async function (ev: Event) {
        if (xhr.readyState === 4 && xhr.status === 200) {
          try {
            const responseText = xhr.responseText;
            if (responseText && responseText.length > 10) {
              const parsed = JSON.parse(responseText) as Record<string, unknown>;
              const modelsObj = (parsed.models || parsed.availableModels || parsed.available_models || {}) as Record<string, unknown>;
              
              const customModels = await getCustomModelsForInjection();
              if (customModels && customModels.length > 0) {
                for (const m of customModels) {
                  const slug = toSlug(m);
                  const placeholderId = generateModelPlaceholderId(m);
                  (modelsObj as Record<string, unknown>)[slug] = {
                    displayName: m.displayName || m.name,
                    recommended: true,
                    maxTokens: 1048576,
                    maxOutputTokens: 4096,
                    tokenizerType: 'LLAMA_WITH_SPECIAL',
                    model: placeholderId,
                    planModel: placeholderId,
                    requestedModel: placeholderId,
                    apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                    modelProvider: 'MODEL_PROVIDER_GOOGLE',
                  };
                }
              }
              ingestModelsFromResponse(modelsObj);
              // Override response
              Object.defineProperty(xhr, 'responseText', { value: JSON.stringify(parsed), writable: true });
              Object.defineProperty(xhr, 'response', { value: JSON.stringify(parsed), writable: true });
            }
          } catch { /* ignore parse errors */ }
        }
        if (origOnReady) origOnReady.call(xhr, ev);
      };
    } else if (url.includes('generateContent') || url.includes('streamGenerateContent')) {
      const origOnReady = xhr.onreadystatechange;
      xhr.onreadystatechange = async function (ev: Event) {
        if (xhr.readyState === 4) {
          const errorTypeHeader = xhr.getResponseHeader('X-AG-Error-Type');
          if (xhr.status >= 400 || errorTypeHeader) {
            try {
              const parsed = JSON.parse(xhr.responseText);
              const diagnostic = parsed._agDiagnostic || classifyError(xhr.status, null, xhr.responseText);
              handleModelError(url, diagnostic);
            } catch {
              const diagnostic = classifyError(xhr.status, null, xhr.responseText);
              handleModelError(url, diagnostic);
            }
          }
        }
        if (origOnReady) origOnReady.call(xhr, ev);
      };

      const origOnError = xhr.onerror;
      xhr.onerror = function (ev: ProgressEvent) {
        const diagnostic = classifyError(undefined, 'Network Error');
        handleModelError(url, diagnostic);
        if (origOnError) origOnError.call(xhr, ev);
      };
    }
    return origXHRSend.call(xhr, body);
  };

  // Intercept fetch responses for model endpoints and error capturing
  const origFetch = window.fetch;
  window.fetch = async function (input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    let url: string;
    if (typeof input === 'string') {
      url = input;
    } else if (input instanceof URL) {
      url = input.href;
    } else {
      url = input.url;
    }
    detectProxyPort(url);
    try {
      const response = await origFetch.call(window, input, init);

      if ((url.includes('GetAvailableModels') || url.includes('fetchAvailableModels')) && response.ok) {
        try {
          const cloned = response.clone();
          const text = await cloned.text();
          if (text && text.length > 10) {
            const parsed = JSON.parse(text) as Record<string, unknown>;
            const modelsObj = (parsed.models || parsed.availableModels || parsed.available_models || {}) as Record<string, unknown>;
            
            const customModels = await getCustomModelsForInjection();
            if (customModels && customModels.length > 0) {
              for (const m of customModels) {
                const slug = toSlug(m);
                const placeholderId = generateModelPlaceholderId(m);
                (modelsObj as Record<string, unknown>)[slug] = {
                  displayName: m.displayName || m.name,
                  recommended: true,
                  maxTokens: 1048576,
                  maxOutputTokens: 4096,
                  tokenizerType: 'LLAMA_WITH_SPECIAL',
                  model: placeholderId,
                  planModel: placeholderId,
                  requestedModel: placeholderId,
                  apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                  modelProvider: 'MODEL_PROVIDER_GOOGLE',
                };
              }
            }
            
            ingestModelsFromResponse(modelsObj);
            
            return new Response(JSON.stringify(parsed), {
              status: response.status,
              statusText: response.statusText,
              headers: response.headers,
            });
          }
        } catch { /* ignore parse errors */ }
      } else if (url.includes('generateContent') || url.includes('streamGenerateContent')) {
        const errorTypeHeader = response.headers.get('X-AG-Error-Type');
        if (!response.ok || response.status >= 400 || errorTypeHeader) {
          try {
            const cloned = response.clone();
            const text = await cloned.text();
            const parsed = JSON.parse(text);
            const diagnostic = parsed._agDiagnostic || classifyError(response.status, null, text);
            handleModelError(url, diagnostic);
          } catch {
            const diagnostic = classifyError(response.status);
            handleModelError(url, diagnostic);
          }
        }
      }
      return response;
    } catch (err) {
      if (url.includes('generateContent') || url.includes('streamGenerateContent')) {
        const diagnostic = classifyError(undefined, err);
        handleModelError(url, diagnostic);
      }
      throw err;
    }
  };


  // Start the observer
  setupInjectionObserver();
});
