/**
 * Preload script — runs in every BrowserWindow before the page loads.
 * Exposes a minimal, secure API via contextBridge so the renderer can
 * communicate with the main-process auto-updater without nodeIntegration.
 */

import { contextBridge, ipcRenderer, webFrame } from 'electron';
import { generateModelPlaceholderId, toSlug } from './proxy/idGenerator';
import { classifyError } from './proxy/errorClassifier';

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
  fetchModels: (params: { baseUrl: string; apiKey?: string; allowUnauthorized?: boolean }) => Promise<{ success: boolean; models?: {id: string, displayName: string}[]; error?: string }>;
  getProviders: () => Promise<ProviderFileEntry[]>;
  saveProvider: (provider: ProviderFileEntry) => Promise<{ success: boolean; error?: string }>;
  deleteProvider: (providerId: string) => Promise<{ success: boolean; error?: string }>;
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
}

interface FetchModelsResult {
  success: boolean;
  models?: { id: string; name: string; inputModalities?: string[] }[];
  error?: string;
}

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
        const placeholder = document.createElement('div');
        placeholder.style.display = 'flex';
        placeholder.style.flexDirection = 'column';
        placeholder.style.alignItems = 'center';
        placeholder.style.justifyContent = 'center';
        placeholder.style.padding = '24px';
        placeholder.style.backgroundColor = '#18181b';
        placeholder.style.border = '1px solid #27272a';
        placeholder.style.borderRadius = '8px';
        placeholder.style.textAlign = 'center';

        placeholder.innerHTML = `
                    <div style="font-size: 15px; font-weight: 600; color: #f4f4f5; margin-bottom: 4px;">No custom models yet</div>
                    <div style="font-size: 13px; color: #a1a1aa;">You haven't added any custom models. Use "Provider Manager" above to connect one.</div>
                `;
        contentArea.appendChild(placeholder);
      } else {
        models.forEach((model) => {
          const item = document.createElement('div');
          item.style.display = 'flex';
          item.style.justifyContent = 'space-between';
          item.style.alignItems = 'center';
          item.style.padding = '12px 16px';
          item.style.backgroundColor = '#18181b';
          item.style.border = '1px solid #27272a';
          item.style.borderRadius = '8px';
          item.style.transition = 'border-color 0.15s ease, background-color 0.15s ease';
          item.style.marginBottom = '8px';
          item.style.cursor = 'default';
          item.tabIndex = 0;
          item.setAttribute('role', 'listitem');

          item.addEventListener('mouseenter', () => {
            item.style.borderColor = '#3f3f46';
            item.style.backgroundColor = '#1c1c1f';
          });
          item.addEventListener('mouseleave', () => {
            item.style.borderColor = '#27272a';
            item.style.backgroundColor = '#18181b';
          });

          // ─── Left: Provider icon + model info ────────────
          const left = document.createElement('div');
          left.style.display = 'flex';
          left.style.alignItems = 'center';
          left.style.gap = '12px';

          // Provider icon bubble
          const iconWrapper = document.createElement('div');
          iconWrapper.style.width = '32px';
          iconWrapper.style.height = '32px';
          iconWrapper.style.borderRadius = '8px';
          iconWrapper.style.display = 'flex';
          iconWrapper.style.alignItems = 'center';
          iconWrapper.style.justifyContent = 'center';
          iconWrapper.style.backgroundColor = getProviderColor(model.provider as string) + '18';
          iconWrapper.style.color = getProviderColor(model.provider as string);
          iconWrapper.style.flexShrink = '0';
          iconWrapper.innerHTML = getProviderIcon(model.provider as string);

          // Text info
          const info = document.createElement('div');
          info.style.display = 'flex';
          info.style.flexDirection = 'column';
          info.style.gap = '2px';

          // Title row with status dot
          const titleRow = document.createElement('div');
          titleRow.style.display = 'flex';
          titleRow.style.alignItems = 'center';
          titleRow.style.gap = '6px';

          // Status indicator dot
          const statusDot = document.createElement('span');
          statusDot.style.width = '6px';
          statusDot.style.height = '6px';
          statusDot.style.borderRadius = '50%';
          statusDot.style.flexShrink = '0';
          statusDot.style.backgroundColor = '#71717a'; // neutral = unknown
          statusDot.title = 'Connection status unknown (test to verify)';
          statusDot.style.transition = 'background-color 0.3s ease';

          const title = document.createElement('div');
          title.style.fontSize = '14px';
          title.style.fontWeight = '500';
          title.style.color = '#f4f4f5';
          title.textContent = (model.displayName as string) || (model.name as string);

          titleRow.appendChild(statusDot);
          titleRow.appendChild(title);

          // Subtitle with provider badge
          const sub = document.createElement('div');
          sub.style.fontSize = '12px';
          sub.style.color = '#a1a1aa';
          sub.style.display = 'flex';
          sub.style.alignItems = 'center';
          sub.style.gap = '8px';

          // Provider badge
          const badge = document.createElement('span');
          badge.style.fontSize = '10px';
          badge.style.fontWeight = '600';
          badge.style.textTransform = 'uppercase';
          badge.style.letterSpacing = '0.5px';
          badge.style.padding = '2px 6px';
          badge.style.borderRadius = '4px';
          badge.style.backgroundColor = getProviderColor(model.provider as string) + '22';
          badge.style.color = getProviderColor(model.provider as string);
          badge.textContent = model.provider as string;

          sub.appendChild(badge);
          sub.appendChild(document.createTextNode(model.apiUrl as string));

          info.appendChild(titleRow);
          info.appendChild(sub);

          left.appendChild(iconWrapper);
          left.appendChild(info);

          // ─── Right: Action buttons ──────────────────
          const actions = document.createElement('div');
          actions.style.display = 'flex';
          actions.style.gap = '4px';
          actions.style.alignItems = 'center';

          // Test Connection button
          const testBtn = document.createElement('button');
          testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`;
          testBtn.style.background = 'transparent';
          testBtn.style.border = 'none';
          testBtn.style.color = '#a1a1aa';
          testBtn.style.cursor = 'pointer';
          testBtn.style.padding = '6px';
          testBtn.style.borderRadius = '4px';
          testBtn.style.display = 'flex';
          testBtn.style.alignItems = 'center';
          testBtn.style.justifyContent = 'center';
          testBtn.style.transition = 'color 0.15s ease, background-color 0.15s ease';
          testBtn.title = 'Test connection';
          testBtn.setAttribute('aria-label', `Test connection for ${(model.displayName as string) || (model.name as string)}`);

          testBtn.addEventListener('mouseenter', () => {
            testBtn.style.color = '#22c55e';
            testBtn.style.backgroundColor = 'rgba(34, 197, 94, 0.1)';
          });
          testBtn.addEventListener('mouseleave', () => {
            testBtn.style.color = '#a1a1aa';
            testBtn.style.backgroundColor = 'transparent';
          });

          testBtn.addEventListener('click', async (e) => {
            e.stopPropagation();
            // Show loading spinner
            const originalHtml = testBtn.innerHTML;
            testBtn.style.color = '#fbbf24';
            testBtn.style.cursor = 'wait';
            testBtn.disabled = true;
            const spinnerSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="${prefersReducedMotion() ? '' : 'animation: agy-spin 0.8s linear infinite;'}"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>`;
            testBtn.innerHTML = spinnerSvg;

            try {
              const result = await storageAPI.testModelConnection({
                apiUrl: model.apiUrl as string,
                provider: model.provider as string,
                apiKey: model.apiKey as string,
                allowUnauthorized: model.allowUnauthorized as boolean | undefined,
              });

              if (result.success) {
                statusDot.style.backgroundColor = '#22c55e'; // green
                statusDot.title = result.message || 'Connected';
                testBtn.title = 'Connected ✓';
                testBtn.style.color = '#22c55e';
                testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`;
                
                // Auto-healing
                const banner = document.getElementById('agy-persistent-banner');
                if (banner) banner.remove();
                failedModelDisplayNames.clear();
                document.querySelectorAll('.ag-model-warning').forEach(el => el.remove());
              } else {
                statusDot.style.backgroundColor = '#ef4444'; // red
                const errMsg = result.error || 'Connection failed';
                statusDot.title = errMsg;
                testBtn.title = errMsg;
                testBtn.style.color = '#ef4444';
                testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>`;
              }
            } catch (err) {
              statusDot.style.backgroundColor = '#ef4444';
              statusDot.title = 'Connection test failed';
              testBtn.title = 'Connection test failed';
              testBtn.style.color = '#ef4444';
              testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>`;
            }

            testBtn.style.cursor = 'pointer';

            // Reset to neutral after 3 seconds
            setTimeout(() => {
              testBtn.disabled = false;
              testBtn.style.cursor = 'pointer';
              testBtn.style.color = '#a1a1aa';
              testBtn.style.borderColor = '#3f3f46';
              testBtn.innerHTML = originalHtml;
            }, 3000);
          });

          // Delete button
          const deleteBtn = document.createElement('button');
          deleteBtn.innerHTML = `
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <polyline points="3 6 5 6 21 6"></polyline>
                            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                            <line x1="10" y1="11" x2="10" y2="17"></line>
                            <line x1="14" y1="11" x2="14" y2="17"></line>
                        </svg>
                    `;
          deleteBtn.style.background = 'transparent';
          deleteBtn.style.border = 'none';
          deleteBtn.style.color = '#a1a1aa';
          deleteBtn.style.cursor = 'pointer';
          deleteBtn.style.padding = '6px';
          deleteBtn.style.borderRadius = '4px';
          deleteBtn.style.display = 'flex';
          deleteBtn.style.alignItems = 'center';
          deleteBtn.style.justifyContent = 'center';
          deleteBtn.style.transition = 'color 0.15s ease, background-color 0.15s ease';
          deleteBtn.setAttribute('aria-label', `Delete ${(model.displayName as string) || (model.name as string)}`);

          deleteBtn.addEventListener('mouseenter', () => {
            deleteBtn.style.color = '#ef4444';
            deleteBtn.style.backgroundColor = 'rgba(239, 68, 68, 0.1)';
          });
          deleteBtn.addEventListener('mouseleave', () => {
            deleteBtn.style.color = '#a1a1aa';
            deleteBtn.style.backgroundColor = 'transparent';
          });

          deleteBtn.addEventListener('click', async (e) => {
            e.stopPropagation();
            if (window.confirm(`Delete "${model.displayName || model.name}"? This removes it from your model list.`)) {
              await storageAPI.deleteCustomModel(model.name as string);
              await renderCustomModelsList();

              const refreshBtn = findRefreshButton();
              if (refreshBtn) refreshBtn.click();
            }
          });

          actions.appendChild(testBtn);
          actions.appendChild(deleteBtn);

          item.appendChild(left);
          item.appendChild(actions);
          contentArea.appendChild(item);
        });
      }
    } catch (err) {
      console.error('Failed to load custom models in list:', err);
    }
  }

  async function injectCustomModelsSection(): Promise<void> {
    const layout = findMcpSectionContainer();
    if (!layout) return;

    const { mainContainer, headerRow, contentBlock } = layout;

    if (document.getElementById('agy-custom-models-section')) return;

    const section = document.createElement('div');
    section.id = 'agy-custom-models-section';
    section.style.marginTop = '24px';
    section.style.display = 'flex';
    section.style.flexDirection = 'column';
    section.style.gap = '12px';

    const newHeaderRow = document.createElement('div');
    newHeaderRow.className = (headerRow as HTMLElement).className;
    newHeaderRow.style.cssText = (headerRow as HTMLElement).style.cssText;
    newHeaderRow.style.display = 'flex';
    newHeaderRow.style.justifyContent = 'space-between';
    newHeaderRow.style.alignItems = 'center';
    newHeaderRow.style.marginBottom = '8px';

    const originalHeading = headerRow.firstElementChild as HTMLElement;
    const newHeading = document.createElement(originalHeading ? originalHeading.tagName : 'div');
    if (originalHeading) {
      newHeading.className = originalHeading.className;
      newHeading.style.cssText = originalHeading.style.cssText;
    }
    newHeading.textContent = 'Custom Models';

    const newBtnGroup = document.createElement('div');
    const originalBtnGroup = headerRow.lastElementChild as HTMLElement;
    if (originalBtnGroup) {
      newBtnGroup.className = originalBtnGroup.className;
      newBtnGroup.style.cssText = originalBtnGroup.style.cssText;
    }
    newBtnGroup.style.display = 'flex';
    newBtnGroup.style.gap = '8px';
    newBtnGroup.style.alignItems = 'center';

    const addModelBtn = document.createElement('button');
    addModelBtn.id = 'agy-add-model-btn';
    addModelBtn.textContent = '☁️ Provider Manager';
    const refreshBtn = findRefreshButton();
    if (refreshBtn) {
      addModelBtn.className = refreshBtn.className;
      addModelBtn.style.cssText = refreshBtn.style.cssText;
    }
    addModelBtn.style.cursor = 'pointer';
    addModelBtn.addEventListener('click', () => {
      openProviderManagerModal();
    });
    newBtnGroup.appendChild(addModelBtn);
    newHeaderRow.appendChild(newHeading);
    newHeaderRow.appendChild(newBtnGroup);

    const contentArea = document.createElement('div');
    contentArea.id = 'agy-custom-models-content';
    contentArea.style.display = 'flex';
    contentArea.style.flexDirection = 'column';
    contentArea.style.gap = '8px';

    section.appendChild(newHeaderRow);
    section.appendChild(contentArea);

    if (contentBlock && contentBlock.nextSibling) {
      mainContainer.insertBefore(section, contentBlock.nextSibling);
    } else {
      mainContainer.appendChild(section);
    }

    await renderCustomModelsList();
  }

  function openProviderManagerModal(): void {
    const existing = document.getElementById('agy-modal-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'agy-modal-overlay';
    overlay.style.cssText = `
      position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
      background: rgba(0, 0, 0, 0.6); backdrop-filter: blur(6px); z-index: 999999;
      display: flex; justify-content: center; align-items: center;
      opacity: 1; transition: opacity 0.2s ease;
    `;

    const modal = document.createElement('div');
    modal.style.cssText = `
      background: #18181b; border: 1px solid #3f3f46; border-radius: 12px;
      width: 650px; max-height: 85vh; display: flex; flex-direction: column;
      box-shadow: 0 20px 25px -5px rgba(0,0,0,0.5); overflow: hidden; color: #f4f4f5;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      transform: scale(1) translateY(0); opacity: 1; transition: transform 0.2s ease, opacity 0.2s ease;
      outline: none;
    `;

    const header = document.createElement('div');
    header.style.cssText = `padding: 16px 24px; border-bottom: 1px solid #3f3f46; display: flex; justify-content: space-between; align-items: center;`;
    
    const titleRow = document.createElement('div');
    titleRow.style.cssText = `display: flex; align-items: center; gap: 8px;`;
    titleRow.innerHTML = `<h3 style="margin:0; font-size:18px; font-weight:600;">Provider Manager</h3>`;
    titleRow.setAttribute('role', 'heading');
    titleRow.setAttribute('aria-level', '3');
    
    const closeBtn = document.createElement('button');
    closeBtn.style.cssText = `background:none; border:none; color:#a1a1aa; font-size:24px; cursor:pointer; padding:0; line-height:1; border-radius:4px; transition: color 0.15s ease, background-color 0.15s ease;`;
    closeBtn.setAttribute('aria-label', 'Close provider manager');
    closeBtn.onclick = () => overlay.remove();
    
    header.appendChild(titleRow);
    header.appendChild(closeBtn);
    modal.appendChild(header);

    const body = document.createElement('div');
    body.style.cssText = `display: flex; flex-direction: column; flex: 1; overflow: hidden; position: relative;`;

    const listContainer = document.createElement('div');
    listContainer.style.cssText = `padding: 24px; overflow-y: auto; flex: 1; display: flex; flex-direction: column; gap: 16px;`;

    const formContainer = document.createElement('div');
    formContainer.style.cssText = `padding: 24px; overflow-y: auto; flex: 1; display: none; flex-direction: column; gap: 16px; background: #1c1c1f;`;

    body.appendChild(listContainer);
    body.appendChild(formContainer);
    modal.appendChild(body);
    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    // Animate in
    if (!prefersReducedMotion()) {
      overlay.style.opacity = '0';
      modal.style.opacity = '0';
      modal.style.transform = 'scale(0.9) translateY(20px)';
      modal.style.transition = 'transform 0.2s ease, opacity 0.2s ease';
      overlay.style.transition = 'opacity 0.2s ease';
      requestAnimationFrame(() => {
        overlay.style.opacity = '1';
        modal.style.opacity = '1';
        modal.style.transform = 'scale(1) translateY(0)';
      });
    } else {
      overlay.style.opacity = '1';
      modal.style.opacity = '1';
      modal.style.transform = 'scale(1) translateY(0)';
    }

    const closeModalAndCleanup = () => {
      overlay.style.opacity = '0';
      modal.style.transform = 'scale(0.9) translateY(20px)';
      document.removeEventListener('keydown', onKeydown);
      setTimeout(() => overlay.remove(), 200);
    };

    document.getElementById('agy-modal-close')!.addEventListener('click', closeModalAndCleanup);
    document.getElementById('agy-btn-cancel')!.addEventListener('click', closeModalAndCleanup);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) closeModalAndCleanup();
    });

    const onKeydown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        closeModalAndCleanup();
      }
    };
    document.addEventListener('keydown', onKeydown);

    // Element references for Step 1
    const updateSelectedDisplay = () => {
      if (selectedModels.size > 0) {
        selectedModelsDiv.style.display = 'flex';
        selectedListDiv.textContent = `${selectedModels.size} model(s) selected`;
        saveBtn.style.display = 'block';
      } else {
        selectedModelsDiv.style.display = 'none';
        saveBtn.style.display = 'none';
      }
    };

    // Back to step 1
    backToStep1Btn.addEventListener('click', () => {
      step2Content.style.display = 'none';
      step1Content.style.display = 'flex';
      displayNameContainer.style.display = 'none';
      step2Circle.style.backgroundColor = '#3f3f46';
      step2Circle.style.color = '#71717a';
      step2Text.style.color = '#71717a';
      selectedModels.clear();
      updateSelectedDisplay();
    });

    // Save selected models
    saveBtn.addEventListener('click', async () => {
      if (selectedModels.size === 0) {
        fetchStatus.textContent = 'Please select at least one model';
        fetchStatus.style.color = '#ef4444';
        return;
      }

      saveBtn.disabled = true;
      saveBtn.textContent = 'Adding models...';

    section.id = 'agy-custom-models-section';
    section.style.marginTop = '24px';
    section.style.display = 'flex';
    section.style.flexDirection = 'column';
    section.style.gap = '12px';

    const newHeaderRow = document.createElement('div');
    newHeaderRow.className = (headerRow as HTMLElement).className;
    newHeaderRow.style.cssText = (headerRow as HTMLElement).style.cssText;
    newHeaderRow.style.display = 'flex';
    newHeaderRow.style.justifyContent = 'space-between';
    newHeaderRow.style.alignItems = 'center';
    newHeaderRow.style.marginBottom = '8px';

    const originalHeading = headerRow.firstElementChild as HTMLElement;
    const newHeading = document.createElement(originalHeading ? originalHeading.tagName : 'div');
    if (originalHeading) {
      newHeading.className = originalHeading.className;
      newHeading.style.cssText = originalHeading.style.cssText;
    }
    newHeading.textContent = 'Custom Models';

    const newBtnGroup = document.createElement('div');
    const originalBtnGroup = headerRow.lastElementChild as HTMLElement;
    if (originalBtnGroup) {
      newBtnGroup.className = originalBtnGroup.className;
      newBtnGroup.style.cssText = originalBtnGroup.style.cssText;
    }
    newBtnGroup.style.display = 'flex';
    newBtnGroup.style.gap = '8px';
    newBtnGroup.style.alignItems = 'center';

    const addModelBtn = document.createElement('button');
    addModelBtn.id = 'agy-add-model-btn';
    addModelBtn.textContent = '☁️ Provider Manager';
    const refreshBtn = findRefreshButton();
    if (refreshBtn) {
      addModelBtn.className = refreshBtn.className;
      addModelBtn.style.cssText = refreshBtn.style.cssText;
    }
    addModelBtn.style.cursor = 'pointer';
    addModelBtn.addEventListener('click', () => {
      openProviderManagerModal();
    });
    newBtnGroup.appendChild(addModelBtn);
    newHeaderRow.appendChild(newHeading);
    newHeaderRow.appendChild(newBtnGroup);

    const contentArea = document.createElement('div');
    contentArea.id = 'agy-custom-models-content';
    contentArea.style.display = 'flex';
    contentArea.style.flexDirection = 'column';
    contentArea.style.gap = '8px';

    section.appendChild(newHeaderRow);
    section.appendChild(contentArea);

    if (contentBlock && contentBlock.nextSibling) {
      mainContainer.insertBefore(section, contentBlock.nextSibling);
    } else {
      mainContainer.appendChild(section);
    }

    await renderCustomModelsList();
  }

  function openProviderManagerModal(): void {
    const existing = document.getElementById('agy-modal-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'agy-modal-overlay';
    overlay.style.cssText = `
      position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
      background: rgba(0, 0, 0, 0.6); backdrop-filter: blur(6px); z-index: 999999;
      display: flex; justify-content: center; align-items: center;
      opacity: 1; transition: opacity 0.2s ease;
    `;

    const modal = document.createElement('div');
    modal.style.cssText = `
      background: #18181b; border: 1px solid #3f3f46; border-radius: 12px;
      width: 650px; max-height: 85vh; display: flex; flex-direction: column;
      box-shadow: 0 20px 25px -5px rgba(0,0,0,0.5); overflow: hidden; color: #f4f4f5;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      transform: scale(1) translateY(0); opacity: 1; transition: transform 0.2s ease, opacity 0.2s ease;
      outline: none;
    `;

    const header = document.createElement('div');
    header.style.cssText = `padding: 16px 24px; border-bottom: 1px solid #3f3f46; display: flex; justify-content: space-between; align-items: center;`;
    
    const titleRow = document.createElement('div');
    titleRow.style.cssText = `display: flex; align-items: center; gap: 8px;`;
    titleRow.innerHTML = `<h3 style="margin:0; font-size:18px; font-weight:600;">Provider Manager</h3>`;
    titleRow.setAttribute('role', 'heading');
    titleRow.setAttribute('aria-level', '3');
    
    const closeBtn = document.createElement('button');
    closeBtn.style.cssText = `background:none; border:none; color:#a1a1aa; font-size:24px; cursor:pointer; padding:0; line-height:1; border-radius:4px; transition: color 0.15s ease, background-color 0.15s ease;`;
    closeBtn.setAttribute('aria-label', 'Close provider manager');
    closeBtn.onclick = () => overlay.remove();
    
    header.appendChild(titleRow);
    header.appendChild(closeBtn);
    modal.appendChild(header);

    const body = document.createElement('div');
    body.style.cssText = `display: flex; flex-direction: column; flex: 1; overflow: hidden; position: relative;`;

    const listContainer = document.createElement('div');
    listContainer.style.cssText = `padding: 24px; overflow-y: auto; flex: 1; display: flex; flex-direction: column; gap: 16px;`;

    const formContainer = document.createElement('div');
    formContainer.style.cssText = `padding: 24px; overflow-y: auto; flex: 1; display: none; flex-direction: column; gap: 16px; background: #1c1c1f;`;

    body.appendChild(listContainer);
    body.appendChild(formContainer);
    modal.appendChild(body);
    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    // Animate in
    if (!prefersReducedMotion()) {
      overlay.style.opacity = '0';
      modal.style.opacity = '0';
      modal.style.transform = 'scale(0.9) translateY(20px)';
      modal.style.transition = 'transform 0.2s ease, opacity 0.2s ease';
      overlay.style.transition = 'opacity 0.2s ease';
      requestAnimationFrame(() => {
        overlay.style.opacity = '1';
        modal.style.opacity = '1';
        modal.style.transform = 'scale(1) translateY(0)';
      });
    } else {
      overlay.style.opacity = '1';
      modal.style.opacity = '1';
      modal.style.transform = 'scale(1) translateY(0)';
    }

    const closeModalAndCleanup = () => {
      overlay.style.opacity = '0';
      modal.style.transform = 'scale(0.9) translateY(20px)';
      document.removeEventListener('keydown', onKeydown);
      setTimeout(() => overlay.remove(), 200);
    };

    document.getElementById('agy-modal-close')!.addEventListener('click', closeModalAndCleanup);
    document.getElementById('agy-btn-cancel')!.addEventListener('click', closeModalAndCleanup);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) closeModalAndCleanup();
    });

    const onKeydown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        closeModalAndCleanup();
      }
    };
    document.addEventListener('keydown', onKeydown);

    // Element references for Step 1
    const updateSelectedDisplay = () => {
      if (selectedModels.size > 0) {
        selectedModelsDiv.style.display = 'flex';
        selectedListDiv.textContent = `${selectedModels.size} model(s) selected`;
        saveBtn.style.display = 'block';
      } else {
        selectedModelsDiv.style.display = 'none';
        saveBtn.style.display = 'none';
      }
    };

    // Back to step 1
    backToStep1Btn.addEventListener('click', () => {
      step2Content.style.display = 'none';
      step1Content.style.display = 'flex';
      displayNameContainer.style.display = 'none';
      step2Circle.style.backgroundColor = '#3f3f46';
      step2Circle.style.color = '#71717a';
      step2Text.style.color = '#71717a';
      selectedModels.clear();
      updateSelectedDisplay();
    });

    // Save selected models
    saveBtn.addEventListener('click', async () => {
      if (selectedModels.size === 0) {
        fetchStatus.textContent = 'Please select at least one model';
        fetchStatus.style.color = '#ef4444';
        return;
      }

      saveBtn.disabled = true;
      saveBtn.textContent = 'Adding models...';

      const suffix = displayNameSuffix.value.trim();
      const modelsToAdd = fetchedModels.filter(m => selectedModels.has(m.id));

      try {
        for (const model of modelsToAdd) {
          const displayName = model.name + (suffix ? ` ${suffix}` : '');
          
          await ipcRenderer.invoke('storage:save-custom-model', {
            name: model.id,
            displayName,
            provider: apiConfig.provider,
            apiKey: apiConfig.apiKey,
            apiUrl: apiConfig.apiUrl,
            externalModelName: model.id,
            allowUnauthorized: apiConfig.allowUnauthorized,
            inputModalities: model.inputModalities || ['text'],
          });
        }

        // Success - reload models and close
        closeModalAndCleanup();
      } catch (err) {
        fetchStatus.textContent = 'Error: ' + (err as Error).message;
        fetchStatus.style.color = '#ef4444';
        saveBtn.disabled = false;
        saveBtn.textContent = 'Add Selected Models';
      }
    });
  };

  // Close add model modal if open
  const closeAddModelModal = () => {
    const existingOverlay = document.getElementById('agy-modal-overlay');
    if (existingOverlay) {
      existingOverlay.remove();
    }
  };
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
    diagnostic?: any;
    lastChecked: number;
  }
  const modelHealthState = new Map<string, ModelHealth>();
  const failedModelDisplayNames = new Set<string>();




  let dropdownTimeout: any;
  const dropdownObserver = new MutationObserver((mutations) => {
    if (failedModelDisplayNames.size === 0) return;
    
    let hasNewNodes = false;
    for (const m of mutations) {
      if (m.addedNodes.length > 0) {
        hasNewNodes = true;
        break;
      }
    }
    if (!hasNewNodes) return;

    if (dropdownTimeout) clearTimeout(dropdownTimeout);
    dropdownTimeout = setTimeout(() => {
       const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
       let node;
       while ((node = walker.nextNode())) {
         const text = node.nodeValue?.trim();
         if (text && failedModelDisplayNames.has(text)) {
            const parent = node.parentNode as HTMLElement;
            if (parent && !parent.querySelector('.ag-model-warning')) {
               // Find error msg
               let errMsg = "Provider Error. Click to resolve.";
               for (const health of Array.from(modelHealthState.values())) {
                  if (health.status === 'error' && health.diagnostic) {
                     errMsg = health.diagnostic.errorType.toUpperCase() + ": " + health.diagnostic.message;
                     break;
                  }
               }
               const warning = document.createElement('span');
               warning.className = 'ag-model-warning';
               warning.style.cssText = 'cursor: pointer; margin-left: 6px; display: inline-flex; align-items: center; justify-content: center;';
               warning.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#eab308" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`;
               warning.title = errMsg + " (Click to fix)";
               warning.onclick = (e) => {
                 e.preventDefault();
                 e.stopPropagation();
                 openProviderManagerModal();
               };
               parent.appendChild(warning);
            }
         }
       }
    }, 150); // Debounce to prevent blocking the main thread
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
    const match = url.match(/models\/(MODEL_PLACEHOLDER_M[^:]+)/);
    const modelId = match ? match[1] : null;
    
    if (diagnostic.errorType === 'billing' || diagnostic.errorType === 'auth' || diagnostic.errorType === 'forbidden') {
      if (modelId) {
        const models = await getCustomModelsForInjection();
        const m = models.find(x => `MODEL_PLACEHOLDER_M${generateModelPlaceholderId(x)}` === modelId);
        if (m) {
          failedModelDisplayNames.add(m.displayName || m.name);
          modelHealthState.set(generateModelPlaceholderId(m), { status: 'error', lastChecked: Date.now(), diagnostic });
        }
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

    if (url.includes('GetAvailableModels') || url.includes('fetchAvailableModels')) {
      const origOnReady = xhr.onreadystatechange;
      xhr.onreadystatechange = async function (ev: Event) {
        if (xhr.readyState === 4 && xhr.status === 200) {
          const customModels = await getCustomModelsForInjection();
          if (customModels && customModels.length > 0) {
            try {
              const responseText = xhr.responseText;
              if (responseText && responseText.length > 10) {
                const parsed = JSON.parse(responseText) as Record<string, unknown>;
                const modelsObj = (parsed.models || parsed.availableModels || parsed.available_models || {}) as Record<string, unknown>;
                for (const m of customModels) {
                  const slug = toSlug(m);
                  const placeholderId = generateModelPlaceholderId(m);
                  (modelsObj as Record<string, unknown>)[slug] = {
                    displayName: m.displayName || m.name,
                    recommended: true,
                    maxTokens: 1048576,
                    maxOutputTokens: 4096,
                    tokenizerType: 'LLAMA_WITH_SPECIAL',
                    model: `MODEL_PLACEHOLDER_M${placeholderId}`,
                    apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                    modelProvider: 'MODEL_PROVIDER_GOOGLE',
                  };
                }
                // Override response
                Object.defineProperty(xhr, 'responseText', { value: JSON.stringify(parsed), writable: true });
                Object.defineProperty(xhr, 'response', { value: JSON.stringify(parsed), writable: true });
              }
            } catch { /* ignore parse errors */ }
          }
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
    const url = typeof input === 'string' ? input : (input as Request).url;
    try {
      const response = await origFetch.call(window, input, init);

      if ((url.includes('GetAvailableModels') || url.includes('fetchAvailableModels')) && response.ok) {
        const customModels = await getCustomModelsForInjection();
        if (customModels && customModels.length > 0) {
          try {
            const cloned = response.clone();
            const text = await cloned.text();
            if (text && text.length > 10) {
              const parsed = JSON.parse(text) as Record<string, unknown>;
              const modelsObj = (parsed.models || parsed.availableModels || parsed.available_models || {}) as Record<string, unknown>;
              for (const m of customModels) {
                const slug = toSlug(m);
                const placeholderId = generateModelPlaceholderId(m);
                (modelsObj as Record<string, unknown>)[slug] = {
                  displayName: m.displayName || m.name,
                  recommended: true,
                  maxTokens: 1048576,
                  maxOutputTokens: 4096,
                  tokenizerType: 'LLAMA_WITH_SPECIAL',
                  model: `MODEL_PLACEHOLDER_M${placeholderId}`,
                  apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                  modelProvider: 'MODEL_PROVIDER_GOOGLE',
                };
              }
              return new Response(JSON.stringify(parsed), {
                status: response.status,
                statusText: response.statusText,
                headers: response.headers,
              });
            }
          } catch { /* ignore parse errors */ }
        }
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
