# Antigravity Remote Mobile App â€” Flutter Specification & Infrastructure

> **Phase : Avant Coder (Pre-Coding Phase)**  
> **Target Path :** `remote/mobile`  
> **Framework :** Flutter (Dart)

---

## 1. Architecture & Skills Available

### Architecture Standard (Ponytail Clean Architecture)
```
remote/mobile/
â”œâ”€â”€ lib/
â”‚   â”œâ”€â”€ main.dart                      # Entry point & App root
â”‚   â”œâ”€â”€ config/                        # Environments & App constants
â”‚   â”‚   â”œâ”€â”€ env_config.dart            # Multi-environment switcher (dev, local, prod)
â”‚   â”‚   â””â”€â”€ constants.dart             # API paths, timeouts, keys
â”‚   â”œâ”€â”€ theme/                         # Antigravity 2.0 Design System
â”‚   â”‚   â”œâ”€â”€ app_colors.dart            # Dark console palette tokens
â”‚   â”‚   â”œâ”€â”€ app_typography.dart        # System typography & monospace styles
â”‚   â”‚   â””â”€â”€ app_theme.dart             # ThemeData definition
â”‚   â”œâ”€â”€ core/                          # Low-level network & storage
â”‚   â”‚   â”œâ”€â”€ network/                   # WebSocket & HTTP gRPC-Web client
â”‚   â”‚   â”œâ”€â”€ framing/                   # Varint & gRPC-Web length delimiting
â”‚   â”‚   â””â”€â”€ storage/                   # Local preferences & credentials cache
â”‚   â”œâ”€â”€ features/                      # Modular features (BLoC / Provider)
â”‚   â”‚   â”œâ”€â”€ discovery/                 # Daemon pairing & QR connect
â”‚   â”‚   â”œâ”€â”€ sessions/                  # Cascade session list & creation
â”‚   â”‚   â”œâ”€â”€ chat_stream/               # Real-time prompt stream & tool approval
â”‚   â”‚   â””â”€â”€ workspace/                 # File tree & diff viewer
â”‚   â””â”€â”€ shared/                        # Reusable widgets (cards, buttons, status pills)
```

---

## 2. Antigravity 2.0 Palette & Design Tokens ("The Quiet Console")

Below are the exact colors derived from `DESIGN.md` ready for Flutter `AppColors`:

```dart
import 'package:flutter/material.dart';

abstract class AppColors {
  // Surfaces (Zinc Dark Console)
  static const Color surfaceBase = Color(0xFF18181B);   // #18181b
  static const Color surfaceRaised = Color(0xFF1C1C1F); // #1c1c1f
  static const Color surfaceInput = Color(0xFF27272A);  // #27272a

  // Borders
  static const Color borderSubtle = Color(0xFF27272A);  // #27272a
  static const Color borderStrong = Color(0xFF3F3F46);  // #3f3f46

  // Ink / Text
  static const Color inkPrimary = Color(0xFFF4F4F5);   // #f4f4f5
  static const Color inkSecondary = Color(0xFFA1A1AA); // #a1a1aa
  static const Color inkMuted = Color(0xFF71717A);     // #71717a

  // Accents & Actions
  static const Color accentBlue = Color(0xFF3B82F6);     // #3b82f6
  static const Color accentBlueDeep = Color(0xFF2563EB); // #2563eb
  static const Color positive = Color(0xFF22C55E);       // #22c55e (Approuver / ConnectÃ©)
  static const Color warning = Color(0xEAB308);        // #eab308 (Attente validation)
  static const Color danger = Color(0xFFEF4444);         // #ef4444 (Refuser / Erreur)

  // Providers
  static const Color providerOpenAI = Color(0xFF10A37F);
  static const Color providerAnthropic = Color(0xFFD97757);
  static const Color providerGoogle = Color(0xFF4285F4);
  static const Color providerOllama = Color(0xFFF0F0F0);
  static const Color providerOpenRouter = Color(0xFFFF7A45);
  static const Color providerCustom = Color(0xFFA855F7);
}
```

---

## 3. Functionality Roadmap

| Priority | Feature | Description | RPC / Protocol Endpoint |
|:---|:---|:---|:---|
| **P0** | DÃ©couverte Daemon & Connexion | Scanner IP:Port du Daemon Go + token CSRF | `ws://<pc-ip>:8080/ws` |
| **P0** | CrÃ©ation / Liste de Sessions | Instancier & lister les sessions (Cascades) | `GetAllCascadeTrajectories` / `StartCascade` |
| **P0** | Streaming de Prompts | Flux temps-rÃ©el des tokens & Ã©vÃ©nements agent | `SendUserCascadeMessage` |
| **P0** | Validation d'Outils (Tool Approval) | Carte interactive d'approbation `run_command` | `SubmitToolApproval` (ALLOW / DENY) |
| **P1** | Arborescence Workspace | Affichage de la structure des dossiers & fichiers | `GetWorkspaceTree` |
| **P1** | Diffs de Code | Visualisation des modifications apportÃ©es par l'agent | Diff stream events |
| **P2** | Multi-Environment & Tunnel WAN | Mode Cloudflare Tunnel / Tailscale pour accÃ¨s distant | Secure WSS Connection |

---

## 4. Environment Setup Specifications

Three distinct build configurations will be supported via Dart defines (`--dart-define-from-file`):

### 1. `config/env_dev.json` (DÃ©veloppement local LAN)
```json
{
  "ENVIRONMENT": "development",
  "DAEMON_HOST": "192.168.1.50",
  "DAEMON_PORT": 8090,
  "USE_SSL": false,
  "ENABLE_LOGGING": true
}
```

### 2. `config/env_emulator.json` (Ã‰mulateur Android local)
```json
{
  "ENVIRONMENT": "emulator",
  "DAEMON_HOST": "10.0.2.2",
  "DAEMON_PORT": 8090,
  "USE_SSL": false,
  "ENABLE_LOGGING": true
}
```

### 3. `config/env_prod.json` (Production / Tunnel WAN)
```json
{
  "ENVIRONMENT": "production",
  "DAEMON_HOST": "antigravity-remote.domain.com",
  "DAEMON_PORT": 443,
  "USE_SSL": true,
  "ENABLE_LOGGING": false
}
```

