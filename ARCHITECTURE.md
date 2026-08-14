# Antigravity Application Architecture

## Overview
Antigravity is a desktop application built on Electron, Node.js, and TypeScript. It features an in-app HTTP Gateway Proxy that translates model API protocols (Gemini, OpenAI, Anthropic) seamlessly, persistent custom model providers, and lightweight IPC bridge architecture.

---

## Directory & Component Breakdown (`src/`)

```
src/
├── main/                        # Electron Main Process Entry & Windows
│   ├── main.ts                  # Main process bootstrap & application lifecycle
│   ├── windowManager.ts         # Window bounds, loading overlay, & viewport state
│   ├── tray.ts                  # System tray icon & active agent counter
│   ├── menu.ts                  # Application menus & global keyboard shortcuts
│   └── updater.ts               # Electron auto-updater event listeners
│
├── ipc/                         # Inter-Process Communication (IPC Layer)
│   ├── index.ts                 # Centralized IPC registration orchestrator
│   └── handlers/                # Domain-driven IPC Handlers
│       ├── modelHandler.ts      # Provider & custom model IPC (CRUD, export/import base64)
│       ├── settingsHandler.ts   # Persistent user preferences & dialogs
│       ├── doctorHandler.ts     # System diagnostics & ag-doctor metrics
│       └── systemHandler.ts     # Window controls, shell execution, & notifications
│
├── gateway/                     # HTTP Proxy Engine & Protocol Router
│   ├── server.ts                # HTTP Proxy server bootstrap & graceful connection shutdown
│   ├── router.ts                # Route dispatcher for completion & discovery endpoints
│   ├── handlers/                # Request handlers per API protocol (Gemini, OpenAI, Claude)
│   └── middleware/              # Authentication, header injection, & log throttling
│
├── services/                    # Core Domain Services & Stores
│   ├── modelStore.ts            # Atomic custom model & provider store (`withWriteLock`)
│   ├── cryptoStore.ts           # SafeStorage OS keychain encryption & base64 fallback
│   ├── settingsService.ts       # Application configuration service
│   └── languageServer.ts        # LSP / IDE integration client
│
├── preload/                     # Renderer Preload & ContextBridge
│   ├── index.ts                 # Preload module entry point
│   ├── api.ts                   # Type-safe `contextBridge` exposure (`window.nativeStorage`, etc.)
│   └── doctor-ui.ts             # Doctor UI management panel & modal components
│
├── shared/                      # Shared Utilities, Schemas & Constants
│   ├── logger.ts                # Structured facade logger (`createLogger`)
│   ├── constants.ts             # Application-wide configuration constants
│   ├── schemaValidator.ts       # Runtime JSON schema validation
│   ├── paths.ts                 # User data & application path resolvers
│   └── utils.ts                 # Pure helper functions
│
└── presets/                     # Pre-configured model presets & reasoning parameters
```

---

## Architectural Principles

1. **Zero Unnecessary Dependencies (YAGNI)**
   - Modular Node.js native primitives (`http`, `events`, `crypto`, `path`, `fs/promises`) and Electron native APIs.
   - Clean abstractions without framework bloat.

2. **Concurrency Safety & Atomic Persistence**
   - Concurrent writes to `custom_models.json` use promise-chained mutex locks (`withWriteLock`) in `src/services/modelStore.ts` to eliminate race conditions.

3. **Secure Encryption at Rest**
   - API keys are encrypted using OS keychain credentials via Electron `safeStorage`. Fallback encoding is provided for systems without keychains.

4. **Modular IPC Architecture**
   - IPC channels are segregated by domain (`modelHandler`, `settingsHandler`, `doctorHandler`, `systemHandler`), eliminating monolithic handler files.

5. **Slim Preload Scripts**
   - The root `preload.ts` is lightweight, delegating contextBridge registrations to `src/preload/api.ts`.

---

## Antigravity Remote 2.0 Architecture (`remote/`)

Antigravity Remote introduces a 3-tier architecture extending the desktop IDE to mobile devices:

```
IDE Chat UI ↔ Language Server (Hub :55256) ◄── gRPC-Web ── Daemon Go (:8090 / Cloudflare Tunnel)
                                                                 ▲
                                                                 │ WebSocket (JSON RPC)
                                                                 ▼
                                                    Mobile Client (Flutter App)
```

1. **Go Daemon Bridge (`remote/daemon`)**:
   - **Discovery & Watchdog**: Probes local processes to identify the active `language_server` Hub instance, port, and CSRF token. Runs a 10s watchdog to detect token rotations.
   - **Protocol Translator**: Connects over gRPC-Web with manual Protobuf wire encoding to translate mobile WebSocket messages into `StartCascade`, `SendUserCascadeMessage`, `SubmitToolApproval`, `GetAvailableModels`, and file operations.
   - **Tunnel Bridge**: Seamlessly spins up Cloudflare Quick Tunnels (`cloudflared.exe`) and prints paired terminal QR codes for zero-config remote access.
   - **StepRecovery**: Retains in-memory ring buffers of trajectory events to replay lost messages after transient mobile network disconnections.

2. **Flutter Mobile Companion (`remote/mobile`)**:
   - **Antigravity 2.0 Design System**: Replicated design tokens directly from IDE computed stylesheets (`htmlcss.log`) — including `#101010` canvas, `#21252B` sidebars, `#528BFF` focus borders, `#D7BA7D` syntax highlights, and IDE-native diff editor coloration.
   - **Typed Protocol Client (`DaemonApi`)**: Full WebSocket client handling request/response correlations, real-time token streams, tool approval queues, and outbox persistence.
   - **Core Screens**: Quiet Console chat stream, session manager, file tree with syntax icons & code viewer, MCP server explorer, scheduled tasks dashboard, and diagnostic export.
