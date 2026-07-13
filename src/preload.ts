/**
 * Preload script — runs in every BrowserWindow before the page loads.
 * Exposes a minimal, secure API via contextBridge so the renderer can
 * communicate with the main-process auto-updater without nodeIntegration.
 */

import { contextBridge, ipcRenderer, webFrame } from 'electron';

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
  fetchModels: (params: { apiUrl: string; provider: string; apiKey?: string; allowUnauthorized?: boolean }) => Promise<FetchModelsResult>;
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
                    <div style="font-size: 15px; font-weight: 600; color: #f4f4f5; margin-bottom: 4px;">No Custom Models</div>
                    <div style="font-size: 13px; color: #a1a1aa;">You currently don't have any custom models installed. Add a custom model above.</div>
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
            testBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>`;

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
            if (confirm(`Are you sure you want to delete the model "${model.displayName || model.name}"?`)) {
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
    addModelBtn.textContent = 'Add Model';
    const refreshBtn = findRefreshButton();
    if (refreshBtn) {
      addModelBtn.className = refreshBtn.className;
      addModelBtn.style.cssText = refreshBtn.style.cssText;
    }
    addModelBtn.style.cursor = 'pointer';
    addModelBtn.addEventListener('click', () => {
      openAddModelModal();
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

  function openAddModelModal(): void {
    // Remove existing modal if any
    const existing = document.getElementById('agy-modal-overlay');
    if (existing) existing.remove();

    // Modal overlay backdrop
    const overlay = document.createElement('div');
    overlay.id = 'agy-modal-overlay';
    overlay.style.position = 'fixed';
    overlay.style.top = '0';
    overlay.style.left = '0';
    overlay.style.width = '100vw';
    overlay.style.height = '100vh';
    overlay.style.backgroundColor = 'rgba(0, 0, 0, 0.6)';
    overlay.style.backdropFilter = 'blur(6px)';
    overlay.style.display = 'flex';
    overlay.style.justifyContent = 'center';
    overlay.style.alignItems = 'center';
    overlay.style.zIndex = '999999';
    overlay.style.opacity = '0';
    overlay.style.transition = 'opacity 0.2s ease-in-out';

    // Modal card container
    const modal = document.createElement('div');
    modal.id = 'agy-modal-card';
    modal.style.width = '520px';
    modal.style.maxHeight = '90vh';
    modal.style.overflowY = 'auto';
    modal.style.backgroundColor = '#18181b';
    modal.style.border = '1px solid #27272a';
    modal.style.borderRadius = '16px';
    modal.style.padding = '32px';
    modal.style.boxShadow = '0 20px 25px -5px rgba(0, 0, 0, 0.5), 0 10px 10px -5px rgba(0, 0, 0, 0.5)';
    modal.style.color = '#f4f4f5';
    modal.style.fontFamily = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';
    modal.style.transform = 'scale(0.9) translateY(20px)';
    modal.style.transition = 'transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)';

    modal.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px;">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div style="width: 28px; height: 28px; border-radius: 7px; display: flex; align-items: center; justify-content: center; background-color: #3b82f618; color: #3b82f6;">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v20M2 12h20"/></svg>
                    </div>
                    <h3 style="margin: 0; font-size: 20px; font-weight: 600; color: #f4f4f5;">Add Custom Model</h3>
                </div>
                <button id="agy-modal-close" style="background: transparent; border: none; color: #a1a1aa; cursor: pointer; font-size: 20px; line-height: 1; padding: 4px; display: flex; align-items: center; justify-content: center; transition: color 0.15s ease;">&times;</button>
            </div>

            <div style="display: flex; flex-direction: column; gap: 16px; margin-bottom: 24px;">
                <!-- Step Indicator -->
                <div style="display: flex; align-items: center; gap: 12px; padding-bottom: 16px; border-bottom: 1px solid #3f3f46;">
                    <div id="agy-step-1-indicator" style="display: flex; align-items: center; gap: 8px;">
                        <div style="width: 28px; height: 28px; border-radius: 50%; background-color: #3b82f6; color: white; display: flex; align-items: center; justify-content: center; font-size: 13px; font-weight: 600;">1</div>
                        <span style="font-size: 13px; font-weight: 500; color: #e4e4e7;">Configure API</span>
                    </div>
                    <div style="flex: 1; height: 2px; background-color: #3f3f46;"></div>
                    <div id="agy-step-2-indicator" style="display: flex; align-items: center; gap: 8px;">
                        <div id="agy-step-2-circle" style="width: 28px; height: 28px; border-radius: 50%; background-color: #3f3f46; color: #71717a; display: flex; align-items: center; justify-content: center; font-size: 13px; font-weight: 600;">2</div>
                        <span id="agy-step-2-text" style="font-size: 13px; font-weight: 500; color: #71717a;">Select Models</span>
                    </div>
                </div>

                <!-- Step 1: API Configuration -->
                <div id="agy-step-1-content" style="display: flex; flex-direction: column; gap: 16px;">
                    <!-- Provider Type -->
                    <div style="display: flex; flex-direction: column; gap: 6px;">
                        <label style="font-size: 13px; font-weight: 500; color: #a1a1aa;">Provider Type <span style="color: #ef4444;">*</span></label>
                        <select id="agy-provider-type" style="background-color: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #f4f4f5; padding: 10px 12px; font-size: 14px; outline: none; cursor: pointer; transition: border-color 0.15s ease;">
                            <option value="openai">OpenAI Compatible</option>
                            <option value="anthropic">Anthropic Compatible</option>
                        </select>
                    </div>

                    <!-- API URL -->
                    <div style="display: flex; flex-direction: column; gap: 6px;">
                        <label style="font-size: 13px; font-weight: 500; color: #a1a1aa;">API URL <span style="color: #ef4444;">*</span></label>
                        <input type="text" id="agy-api-url" placeholder="https://api.openai.com/v1/chat/completions" style="background-color: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #f4f4f5; padding: 10px 12px; font-size: 14px; outline: none; transition: border-color 0.15s ease;" />
                        <div id="agy-url-error" style="font-size: 11px; color: #ef4444; display: none;"></div>
                    </div>

                    <!-- API Key -->
                    <div style="display: flex; flex-direction: column; gap: 6px;">
                        <label style="font-size: 13px; font-weight: 500; color: #a1a1aa;">API Key <span style="color: #71717a;">(optional for local)</span></label>
                        <input type="password" id="agy-api-key" placeholder="sk-..." style="background-color: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #f4f4f5; padding: 10px 12px; font-size: 14px; outline: none; transition: border-color 0.15s ease;" />
                    </div>

                    <!-- Allow Unauthorized SSL -->
                    <div style="display: flex; align-items: center; gap: 8px; padding: 10px 12px; background-color: #27272a; border: 1px solid #3f3f46; border-radius: 8px;">
                        <input type="checkbox" id="agy-allow-unauthorized" style="width: 16px; height: 16px; cursor: pointer;" />
                        <label for="agy-allow-unauthorized" style="font-size: 13px; color: #d4d4d8; cursor: pointer; user-select: none;">Allow self-signed certificates</label>
                    </div>

                    <!-- Fetch Models Button -->
                    <button id="agy-fetch-models-btn" type="button" style="background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); border: none; color: white; padding: 12px 16px; border-radius: 8px; font-size: 14px; font-weight: 500; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; transition: all 0.15s ease; box-shadow: 0 4px 6px -1px rgba(59, 130, 246, 0.3);">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="16 8 12 12 8 8"/><line x1="12" y1="16" x2="12" y2="12"/></svg>
                        Fetch Available Models
                    </button>
                    <div id="agy-fetch-status" style="font-size: 12px; color: #a1a1aa; display: none; text-align: center;"></div>
                </div>

                <!-- Step 2: Model Selection -->
                <div id="agy-step-2-content" style="display: none; flex-direction: column; gap: 16px;">
                    <div style="font-size: 13px; color: #a1a1aa;">Select one or more models to add:</div>
                    
                    <!-- Models List -->
                    <div id="agy-models-list" style="display: flex; flex-direction: column; gap: 8px; max-height: 400px; overflow-y: auto; padding: 8px; background-color: #1c1c1f; border: 1px solid #3f3f46; border-radius: 8px;">
                        <!-- Models will be populated here -->
                    </div>

                    <!-- Back Button -->
                    <button id="agy-back-to-step1" type="button" style="background-color: #27272a; border: 1px solid #3f3f46; color: #d4d4d8; padding: 10px 16px; border-radius: 8px; font-size: 14px; font-weight: 500; cursor: pointer; transition: all 0.15s ease;">
                        ← Back to Configuration
                    </button>

                    <!-- Selected Models Display -->
                    <div id="agy-selected-models" style="display: none; flex-direction: column; gap: 8px; padding: 12px; background-color: #1c1c1f; border: 1px solid #22c55e; border-radius: 8px;">
                        <div style="font-size: 12px; font-weight: 600; color: #22c55e;">Selected Models:</div>
                        <div id="agy-selected-list" style="font-size: 12px; color: #d4d4d8;"></div>
                    </div>
                </div>

                <!-- Display Name Suffix (Optional, shown in step 2) -->
                <div id="agy-display-name-container" style="display: none; flex-direction: column; gap: 6px;">
                    <label style="font-size: 13px; font-weight: 500; color: #a1a1aa;">Display Name Suffix (optional)</label>
                    <input type="text" id="agy-display-name-suffix" placeholder="e.g. (via OpenRouter)" style="background-color: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #f4f4f5; padding: 10px 12px; font-size: 14px; outline: none; transition: border-color 0.15s ease;" />
                    <div style="font-size: 11px; color: #71717a;">Will be appended to model names</div>
                </div>
            </div>

            <div style="display: flex; gap: 12px; justify-content: flex-end; padding-top: 16px; border-top: 1px solid #3f3f46;">
                <button id="agy-btn-cancel" style="background: transparent; border: 1px solid #3f3f46; color: #d4d4d8; padding: 10px 20px; border-radius: 8px; font-size: 14px; font-weight: 500; cursor: pointer; transition: all 0.15s ease;">Cancel</button>
                <button id="agy-btn-save" style="background: linear-gradient(135deg, #22c55e 0%, #16a34a 100%); border: none; color: white; padding: 10px 24px; border-radius: 8px; font-size: 14px; font-weight: 500; cursor: pointer; transition: all 0.15s ease; box-shadow: 0 4px 6px -1px rgba(34, 197, 94, 0.3); display: none;">Add Selected Models</button>
            </div>
        `;

    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    // Animate in
    setTimeout(() => {
      overlay.style.opacity = '1';
      modal.style.transform = 'scale(1) translateY(0)';
    }, 10);

    // Close handler
    const closeModal = () => {
      overlay.style.opacity = '0';
      modal.style.transform = 'scale(0.9) translateY(20px)';
      setTimeout(() => overlay.remove(), 200);
    };

    document.getElementById('agy-modal-close')!.addEventListener('click', closeModal);
    document.getElementById('agy-btn-cancel')!.addEventListener('click', closeModal);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) closeModal();
    });

    // Element references for Step 1
    const providerTypeSelect = document.getElementById('agy-provider-type') as HTMLSelectElement;
    const urlInput = document.getElementById('agy-api-url') as HTMLInputElement;
    const keyInput = document.getElementById('agy-api-key') as HTMLInputElement;
    const allowUnauthorized = document.getElementById('agy-allow-unauthorized') as HTMLInputElement;
    const fetchModelsBtn = document.getElementById('agy-fetch-models-btn') as HTMLButtonElement;
    const fetchStatus = document.getElementById('agy-fetch-status')!;
    const urlError = document.getElementById('agy-url-error')!;

    // Element references for Step 2
    const step1Content = document.getElementById('agy-step-1-content')!;
    const step2Content = document.getElementById('agy-step-2-content')!;
    const step1Indicator = document.getElementById('agy-step-1-indicator')!;
    const step2Indicator = document.getElementById('agy-step-2-indicator')!;
    const step2Circle = document.getElementById('agy-step-2-circle')!;
    const step2Text = document.getElementById('agy-step-2-text')!;
    const modelsList = document.getElementById('agy-models-list')!;
    const backToStep1Btn = document.getElementById('agy-back-to-step1') as HTMLButtonElement;
    const selectedModelsDiv = document.getElementById('agy-selected-models')!;
    const selectedListDiv = document.getElementById('agy-selected-list')!;
    const displayNameContainer = document.getElementById('agy-display-name-container')!;
    const displayNameSuffix = document.getElementById('agy-display-name-suffix') as HTMLInputElement;
    const saveBtn = document.getElementById('agy-btn-save') as HTMLButtonElement;

    // Store fetched models and selected models
    let fetchedModels: Array<{ id: string; name: string; inputModalities?: string[] }> = [];
    let selectedModels: Set<string> = new Set();
    let apiConfig = { provider: '', apiUrl: '', apiKey: '', allowUnauthorized: false };

    // Step 1: Fetch models button
    fetchModelsBtn.addEventListener('click', async () => {
      const apiUrl = urlInput.value.trim();
      const apiKey = keyInput.value.trim();
      const provider = providerTypeSelect.value;

      if (!apiUrl) {
        urlError.textContent = 'Please enter an API URL';
        urlError.style.display = 'block';
        return;
      }

      urlError.style.display = 'none';
      fetchModelsBtn.disabled = true;
      fetchModelsBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg> Fetching...';
      fetchStatus.textContent = 'Connecting to API...';
      fetchStatus.style.color = '#a1a1aa';
      fetchStatus.style.display = 'block';

      try {
        const result = await ipcRenderer.invoke('storage:fetch-provider-models', {
          apiUrl,
          apiKey: apiKey || undefined,
          provider,
          allowUnauthorized: allowUnauthorized.checked,
        });

        if (result.success && result.models && result.models.length > 0) {
          fetchedModels = result.models;
          apiConfig = { provider, apiUrl, apiKey, allowUnauthorized: allowUnauthorized.checked };
          
          fetchStatus.textContent = `Found ${result.models.length} model(s)`;
          fetchStatus.style.color = '#22c55e';

          // Transition to Step 2
          setTimeout(() => {
            step1Content.style.display = 'none';
            step2Content.style.display = 'flex';
            displayNameContainer.style.display = 'flex';
            step2Circle.style.backgroundColor = '#3b82f6';
            step2Circle.style.color = 'white';
            step2Text.style.color = '#e4e4e7';

            // Populate models list
            modelsList.innerHTML = '';
            fetchedModels.forEach((model) => {
              const modelCard = document.createElement('div');
              modelCard.style.cssText = 'padding: 12px; background-color: #27272a; border: 2px solid #3f3f46; border-radius: 8px; cursor: pointer; transition: all 0.15s ease; display: flex; align-items: center; gap: 12px;';
              
              const checkbox = document.createElement('input');
              checkbox.type = 'checkbox';
              checkbox.style.cssText = 'width: 18px; height: 18px; cursor: pointer;';
              checkbox.dataset.modelId = model.id;

              const infoDiv = document.createElement('div');
              infoDiv.style.cssText = 'flex: 1; display: flex; flex-direction: column; gap: 4px;';
              
              const modelName = document.createElement('div');
              modelName.textContent = model.name || model.id;
              modelName.style.cssText = 'font-size: 14px; font-weight: 500; color: #f4f4f5;';
              
              const modelId = document.createElement('div');
              modelId.textContent = model.id;
              modelId.style.cssText = 'font-size: 12px; color: #71717a;';

              infoDiv.appendChild(modelName);
              if (model.name !== model.id) infoDiv.appendChild(modelId);

              // Show modalities badge
              if (model.inputModalities && model.inputModalities.length > 0 && model.inputModalities.some(m => m !== 'text')) {
                const badge = document.createElement('span');
                badge.textContent = model.inputModalities.join(', ');
                badge.style.cssText = 'font-size: 10px; padding: 2px 6px; background-color: #3b82f6; color: white; border-radius: 4px; display: inline-block;';
                infoDiv.appendChild(badge);
              }

              modelCard.appendChild(checkbox);
              modelCard.appendChild(infoDiv);

              // Toggle selection
              modelCard.addEventListener('click', (e) => {
                if (e.target !== checkbox) {
                  checkbox.checked = !checkbox.checked;
                }
                
                if (checkbox.checked) {
                  selectedModels.add(model.id);
                  modelCard.style.borderColor = '#22c55e';
                  modelCard.style.backgroundColor = '#22c55e18';
                } else {
                  selectedModels.delete(model.id);
                  modelCard.style.borderColor = '#3f3f46';
                  modelCard.style.backgroundColor = '#27272a';
                }

                updateSelectedDisplay();
              });

              modelsList.appendChild(modelCard);
            });
          }, 500);
        } else {
          fetchStatus.textContent = result.error || 'No models found';
          fetchStatus.style.color = '#ef4444';
        }
      } catch (err) {
        fetchStatus.textContent = 'Error: ' + (err as Error).message;
        fetchStatus.style.color = '#ef4444';
      } finally {
        setTimeout(() => {
          fetchModelsBtn.disabled = false;
          fetchModelsBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="16 8 12 12 8 8"/><line x1="12" y1="16" x2="12" y2="12"/></svg> Fetch Available Models';
        }, 1000);
      }
    });

    // Update selected models display
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
          
          await ipcRenderer.invoke('storage:add-custom-model', {
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
        closeModal();
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

  // --- Network Interceptor for Model Injection --------------------------

  const customModelsCache: { models: any[]; ts: number } = { models: [], ts: 0 };

  async function getCustomModelsForInjection(): Promise<any[]> {
    if (Date.now() - customModelsCache.ts < 30000) return customModelsCache.models;
    try {
      customModelsCache.models = await storageAPI.getCustomModels();
      customModelsCache.ts = Date.now();
    } catch { /* ignore */ }
    return customModelsCache.models;
  }

  // Intercept XHR to inject custom models into GetAvailableModels responses
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
                  const provider = (m.provider || 'custom') as string;
                  const displayName = ((m.displayName || m.name || '') as string).trim();
                  const apiUrl = ((m.apiUrl || '') as string).trim();
                  const baseName = ((m.externalModelName || m.name || '') as string)
                    .replace(/^models\//, '')
                    .replace(/[^a-zA-Z0-9]+/g, '-')
                    .replace(/^-+|-+$/g, '')
                    .toLowerCase();
                  const uniquenessHash = hashCodeStr(`${provider}:${displayName}:${apiUrl}`);
                  const slug = `custom-${provider}-${baseName}-${uniquenessHash % 100000}`;
                  const placeholderId = 400 + (Math.abs(hashCodeStr(`${provider}-${displayName}`)) % 200);
                  (modelsObj as Record<string, unknown>)[slug] = {
                    displayName,
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
    }
    return origXHRSend.call(xhr, body);
  };

  // Intercept fetch responses for model endpoints
  const origFetch = window.fetch;
  window.fetch = async function (input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const url = typeof input === 'string' ? input : (input as Request).url;
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
              const provider = (m.provider || 'custom') as string;
              const displayName = ((m.displayName || m.name || '') as string).trim();
              const apiUrl = ((m.apiUrl || '') as string).trim();
              const baseName = ((m.externalModelName || m.name || '') as string)
                .replace(/^models\//, '')
                .replace(/[^a-zA-Z0-9]+/g, '-')
                .replace(/^-+|-+$/g, '')
                .toLowerCase();
              const uniquenessHash = hashCodeStr(`${provider}:${displayName}:${apiUrl}`);
              const slug = `custom-${provider}-${baseName}-${uniquenessHash % 100000}`;
              const placeholderId = 400 + (Math.abs(hashCodeStr(`${provider}-${displayName}`)) % 200);
              (modelsObj as Record<string, unknown>)[slug] = {
                displayName,
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
    }
    return response;
  };

  function hashCodeStr(s: string): number {
    let h = 5381;
    for (let i = 0; i < s.length; i++) {
      h = (h << 5) + h + s.charCodeAt(i);
      h = h & h;
    }
    return Math.abs(h);
  }

  // Start the observer
  setupInjectionObserver();
});
