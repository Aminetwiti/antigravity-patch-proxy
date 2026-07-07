# Changelog

All notable changes to Antigravity will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.3] - 2026-07-07

### Changed
- Migrated codebase from JavaScript (dist/) to TypeScript (src/)
- Refactored monolithic `proxy.ts` into focused modules under `src/proxy/`
- Centralized magic numbers in `src/constants.ts`

### Added
- `src/proxy/urlBuilder.ts` — URL construction logic for custom model requests
- `src/proxy/protoInjector.ts` — Pure functions for protobuf injection into GetAvailableModels
- `src/proxy/idGenerator.ts` — Deterministic ID generation (DJB2 hash)
- `src/proxy/retryStrategy.ts` — Retry strategies (linear, exponential, 2x exponential)
- `src/proxy/protobuf.ts` — Protobuf encode/decode utilities
- `src/proxy/modelLoader.ts` — Custom model loading with encryption migration
- `src/proxy/types.ts` — Shared TypeScript types
- `src/proxy/shared.ts` — Cross-turn state management with TTL cleanup
- `src/proxy/registry.ts` — Provider translator registry
- `src/proxy/modelUtils.ts` — Model capability detection
- `src/proxy/translators/` — Provider-specific request/response translators
- 84 new unit tests covering URL construction, protobuf injection, ID generation, and retry strategies

### Security
- AES-256-GCM encryption for API keys in `custom_models.json`
- Automatic migration from plaintext to encrypted on first run
- BOM-stripping for cross-platform file compatibility

## [2.0.1] - 2026-XX-XX

### Added
- Custom model support for 15+ providers (OpenAI, Anthropic, Google, Ollama, OpenRouter, custom)
- Automatic retry with exponential backoff for 5xx and 429 responses
- Configurable retry count and timeout per model
- Binary patch for Language Server hostname redirection
- Health check endpoint (`/health`, `/healthz`)

### Fixed
- `ERR_HTTP_HEADERS_SENT` race condition in proxy response handling
- Memory leak from uncleaned stream contexts

## [1.x.x] - Initial Release

### Added
- Electron-based desktop application
- Local proxy server for intercepting Gemini API calls
- Custom model management UI
