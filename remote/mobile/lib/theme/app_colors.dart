import 'package:flutter/material.dart';

/// Antigravity 2.0 Color Palette ("The Quiet Console")
/// Extracted from Antigravity IDE computed tokens (htmlcss.log) + DESIGN.md
abstract class AppColors {
  // ── Surfaces (Dark Zinc Console & VSCode Bridge)
  static const Color surfaceBase = Color(0xFF09090B);   // #09090b (Zinc-950, deepest canvas — --background #101010)
  static const Color surfaceRaised = Color(0xFF18181B); // #18181b (Zinc-900, app surface: sidebar, AppBar — #21252b)
  static const Color surfaceInput = Color(0xFF27272A);  // #27272a (Zinc-800, inputs, code blocks, panels — #1b1d23)
  static const Color surfaceHover = Color(0xFF3F3F46);  // #3f3f46 (Zinc-700, raised hover — #2c313a)
  static const Color sidebarBackground = Color(0xFF21252B); // #21252b (--vscode-sideBar-background)
  static const Color editorBackground = Color(0xFF282C34);  // #282c34 (--vscode-editor-background)
  static const Color listSelectionBg = Color(0xFF2C313A);   // #2c313a (--vscode-list-activeSelectionBackground)

  // ── Borders (PC --border / --border-strong / --vscode-editorWidget-border)
  static const Color borderSubtle = Color(0xFF27272A);  // #27272a (rgba(255,255,255,0.05))
  static const Color borderStrong = Color(0xFF3F3F46);  // #3f3f46 (#3a3f4b)

  // ── Ink / Text (PC --text-0 … --text-3 & VSCode Foregrounds)
  static const Color inkPrimary = Color(0xFFF4F4F5);   // #f4f4f5 (high contrast text — #ffffff / #cccccc)
  static const Color inkSecondary = Color(0xFFD4D4D8); // #d4d4d8 (Zinc 300 / #9da5b4 subtitles)
  static const Color inkMuted = Color(0xFFA1A1AA);     // #a1a1aa (Zinc 400 / #636d83 line numbers)
  static const Color inkFaint = Color(0xFF919BAF);     // #919baf (10px uppercase tracking labels)
  static const Color codeGold = Color(0xFFD7BA7D);     // #d7ba7d (--code-foreground / syntax strings)

  // ── Accents & Actions (PC --accent-blue / --vscode-button-background / #528bff)
  static const Color accentBlue = Color(0xFF3B82F6);     // #3b82f6 (primary action)
  static const Color accentBlueBright = Color(0xFF528BFF); // #528bff (--vscode-focusBorder / badge)
  static const Color buttonBackground = Color(0xFF4D78CC); // #4d78cc (--vscode-button-background)
  static const Color accentBlueDeep = Color(0xFF2563EB); // #2563eb (pressed state)

  // ── Status (PC --ok / --warn / --err / --info)
  static const Color positive = Color(0xFF22C55E);       // #22c55e (approve / connected — #7aae66)
  static const Color success = positive;
  static const Color warning = Color(0xFFEAB308);        // #eab308 (tool approval pending — #f3c949)
  static const Color danger = Color(0xFFEF4444);         // #ef4444 (refuse / error — #de5555)
  static const Color error = danger;
  static const Color dangerDeep = Color(0xFFDC2626);     // #dc2626
  static const Color info = Color(0xFF3B82F6);           // #3b82f6 (informational — #59a4f9)
  static const Color accent = accentBlue;

  // ── Diff Editor Tokens (--vscode-diffEditor-*)
  static const Color diffInsertedLine = Color(0x339BB955); // rgba(155, 185, 85, 0.2)
  static const Color diffRemovedLine = Color(0x33FF0000);  // rgba(255, 0, 0, 0.2)
  static const Color diffInsertedText = Color(0x3300809B); // rgba(0, 128, 155, 0.2)
  static const Color diffRemovedText = Color(0x66FF0000);  // rgba(255, 0, 0, 0.4)

  // ── Neutrals (scrims, shadows, camera overlay)
  static const Color overlayScrim = Color(0xFF000000);   // full-black scrim (camera, modal backdrop)
  static const Color shadowNeutral = Color(0xFF000000);  // drop shadows, elevation

  // ── On-fill ink (text/icons over accent & danger fills)
  static const Color onAccent = Color(0xFFFAFAFA);       // #fafafa (Zinc-50 — labels on primary)
  static const Color onDanger = Color(0xFFFAFAFA);       // #fafafa (Zinc-50 — labels on error)

  // ── Provider Accent Badges
  static const Color providerOpenAI = Color(0xFF10A37F);
  static const Color providerAnthropic = Color(0xFFD97757);
  static const Color providerGoogle = Color(0xFF4285F4);
  static const Color providerOllama = Color(0xFFF0F0F0);
  static const Color providerOpenRouter = Color(0xFFFF7A45);
  static const Color providerCustom = Color(0xFFA855F7);

  // ── Dynamic Contextual Accessors (prevents Light/Dark mode conflicts)
  static Color canvas(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceBase : const Color(0xFFFFFFFF);

  static Color panel(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceRaised : const Color(0xFFF6F8FA);

  static Color input(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceInput : const Color(0xFFEAEEF2);

  static Color text(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? inkPrimary : const Color(0xFF1F2328);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? inkSecondary : const Color(0xFF57606A);

  static Color textMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? inkMuted : const Color(0xFF6E7781);

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? borderSubtle : const Color(0xFFD0D7DE);

  static Color borderStrongContext(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? borderStrong : const Color(0xFFAFB8C1);

  static Color accentContext(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? accentBlue : const Color(0xFF0969DA);
}

/// Ergonomic syntax sugar for accessing theme colors and animation preference on any BuildContext
extension ThemeContextExtension on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get shouldAnimate => AppMotion.shouldAnimate(this);
}

/// Radius scale (PC ag-doctor-ui --r-sm/md/lg/xl/pill)
abstract class AppRadius {
  static const double xs = 2;    // micro tags, lines
  static const double sm = 4;    // inputs, chips
  static const double md = 6;    // buttons, nav items
  static const double lg = 10;   // cards, modals
  static const double xl = 14;   // hero panels
  static const double pill = 999;
}

/// Motion tokens (PC --t-fast/base/slow + --ease-out)
abstract class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeStandard = Curves.easeInOut;

  /// Vérifie si les animations système sont actives (support Reduce Motion / Accessibility).
  static bool shouldAnimate(BuildContext context) {
    return !MediaQuery.disableAnimationsOf(context);
  }
}
