# Antigravity Remote — Mobile Design System & Specification

> **Creative North Star : "The Quiet Console"**  
> Une extension native, sobre et précise de l'environnement de développement Antigravity IDE (Antigravity 2.0 / VSCode-bridge). L'interface mobile évite les surcharges visuelles ("AI wrappers" criards, néons saturés) au profit de surfaces sombres zinc, d'un contraste WCAG AAA et de micro-interactions tactiles rassurantes.

---

## 1. Palette de Couleurs & Tokens de Surface

Les couleurs sont rigoureusement alignées avec les tokens d'Antigravity IDE (`htmlcss.log` et [`DESIGN.md`](../DESIGN.md)).

```
Surface Base (0xFF09090B) ── Deepest Canvas (Zinc-950)
  └── Surface Raised (0xFF18181B) ── Sidebar, AppBar, Cards (Zinc-900)
        └── Surface Input (0xFF27272A) ── Champs de saisie, code blocks (Zinc-800)
              └── Surface Hover (0xFF3F3F46) ── État survol / sélection (Zinc-700)
```

### Table des Tokens

| Token | Dark Mode (`AppColors`) | Light Mode (`AppColors.context`) | Description |
|---|---|---|---|
| **Canvas** | `0xFF09090B` (`surfaceBase`) | `0xFFFFFFFF` | Arrière-plan principal de l'application |
| **Panel / Card** | `0xFF18181B` (`surfaceRaised`)| `0xFFF6F8FA` | Cartes, drawers, bottom sheets, barres d'outils |
| **Input / Block** | `0xFF27272A` (`surfaceInput`) | `0xFFEAEEF2` | Zone de texte de saisie, blocs de code |
| **Border Subtle** | `0xFF27272A` (`borderSubtle`) | `0xFFD0D7DE` | Séparateurs, bordures fines de cartes |
| **Border Strong** | `0xFF3F3F46` (`borderStrong`) | `0xFFAFB8C1` | Bordures actives, focus borders |
| **Ink Primary** | `0xFFF4F4F5` (`inkPrimary`)  | `0xFF1F2328` | Titres, messages utilisateurs et assistants |
| **Ink Secondary** | `0xFFD4D4D8` (`inkSecondary`)| `0xFF57606A` | Sous-titres, détails d'outils, métadonnées |
| **Ink Muted** | `0xFFA1A1AA` (`inkMuted`)    | `0xFF6E7781` | Numéros de ligne, icônes d'action inactives |
| **Accent Action** | `0xFF3B82F6` (`accentBlue`)  | `0xFF0969DA` | Boutons primaires, sélection active |
| **Positive / Ok** | `0xFF22C55E` (`positive`)    | `0xFF1A7F37` | Approbation d'outils, statut connecté |
| **Warning** | `0xFFEAB308` (`warning`)     | `0xFF9A6700` | Demande d'approbation en attente |
| **Danger / Refuse** | `0xFFEF4444` (`danger`)    | `0xFFCF222E` | Rejet d'outils, erreurs d'exécution |

### Badges Fournisseurs de Modèles (Model Identity)

| Fournisseur | Token | Couleur Hex |
|---|---|---|
| **Google Gemini** | `AppColors.providerGoogle` | `#4285F4` |
| **Anthropic Claude** | `AppColors.providerAnthropic` | `#D97757` |
| **OpenAI GPT** | `AppColors.providerOpenAI` | `#10A37F` |
| **OpenRouter** | `AppColors.providerOpenRouter` | `#FF7A45` |
| **Custom / Ollama** | `AppColors.providerCustom` | `#A855F7` / `#F0F0F0` |

---

## 2. Typographie & Hiérarchie

La typographie repose sur les polices système (`-apple-system`, `Roboto`, `Segoe UI`) avec une gestion stricte des échelles :

- **Labels & Badges de statut** : `10px`, `FontWeight.w600`, `letterSpacing: 0.5px`, majuscules.
- **Corps de texte / Assistant Markdown** : `14px`, `FontWeight.w400`, `height: 1.45`.
- **Blocs de code & Shell PTY** : Monospace (`Consolas`, `Menlo`, `Roboto Mono`), `12.5px`.
- **Titres de sections / Modales** : `15px` - `16px`, `FontWeight.w600`.

---

## 3. Composants d'Interface Signature

### 1. `ChatInputBar` (Barre de saisie interactive)
- **Sélecteur de modèle Antigravity 2.0** : Affiche le modèle sélectionné + niveau d'effort de raisonnement (*Faible*, *Moyen*, *Élevé*).
- **Actions rapides & Mentions** : Déclenchement automatique de l'autocomplétion sur `@` (fichiers, règles, serveurs MCP) et `/` (commandes slash).
- **Support Multi-pièces jointes** : Prévisualisation avec badge de taille, bouton de suppression et indicateur de progression.
- **Gestion Adaptative Clavier & Safe Area** :
  - Détection dynamique de l'état du clavier (`hasKeyboard`).
  - Marge inférieure compressée à `2.0px` lors de la frappe et adaptée à la `viewPadding.bottom` pour éviter tout overflow sur appareils pliables ou barres de gestes Android.

### 2. `ZenithalCanvas` (Atmosphère de fond)
- Dégradé radial subtil issu du haut de l'écran utilisant la palette officielle Antigravity (`#3186FF`, `#749BFF`) sur fond zinc sombre (`#09090B`).

### 3. `StatusDotBadge` (Statut en direct)
- Pastille translucide aux coins arrondis (`AppRadius.pill`) avec point lumineux pulsant (`isPulsing: true`) pour indiquer la synchronisation en temps réel avec le daemon.

### 4. `UnifiedDiffViewer` & `HunkApproval`
- Rendu fidèle des diffs de code avec surlignage VSCode exact (`diffInsertedLine`, `diffRemovedLine`).
- Approbation sélective par *hunk* ou en bloc (*Apply All / Reject All*).

### 5. `RemoteTerminalSheet` (Bridge PTY)
- Terminal xterm-like intégré avec barre d'accessoires de touches (`Ctrl`, `Esc`, `Tab`, `↑`, `↓`) et routage bidirectionnel WebSocket.

---

## 4. Règles d'Ergonomie et Accessibilité (Light & Dark Mode)

1. **Utilisation systématique des accessors dynamiques** : Toujours privilégier `AppColors.canvas(context)`, `AppColors.panel(context)`, `AppColors.text(context)` plutôt que des couleurs brutes afin de garantir une lisibilité sans faille en thème clair et sombre.
2. **Zone tactile minimale (Touch Target)** : Tous les boutons interactifs (`BouncingTap`, icônes d'action) maintiennent une zone active minimale de **44 × 44 dp**.
3. **Respect du `Reduce Motion`** : `AppMotion.shouldAnimate(context)` désactive automatiquement les micro-animations si l'utilisateur a activé la réduction des mouvements dans les paramètres système de son smartphone.
