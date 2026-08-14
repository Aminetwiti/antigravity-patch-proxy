import 'package:flutter/material.dart';

/// Antigravity 2.0 Color Palette ("The Quiet Console")
/// Direct token mapping from DESIGN.md + ag-doctor-ui (PC) styles.css
abstract class AppColors {
  // ── Surfaces (Dark Zinc Console — PC ag-doctor-ui tokens)
  static const Color surfaceBase = Color(0xFF09090B);   // #09090b (Zinc-950, deepest canvas — PC --bg-0)
  static const Color surfaceRaised = Color(0xFF18181B); // #18181b (Zinc-900, app surface: sidebar, AppBar — PC --bg-1)
  static const Color surfaceInput = Color(0xFF27272A);  // #27272a (Zinc-800, inputs, code blocks, panels — PC --bg-2)
  static const Color surfaceHover = Color(0xFF3F3F46);  // #3f3f46 (Zinc-700, raised hover — PC --bg-3)

  // ── Borders (PC --border / --border-strong)
  static const Color borderSubtle = Color(0xFF27272A);  // #27272a
  static const Color borderStrong = Color(0xFF3F3F46);  // #3f3f46

  // ── Ink / Text (PC --text-0 … --text-3)
  static const Color inkPrimary = Color(0xFFF4F4F5);   // #f4f4f5 (high contrast text)
  static const Color inkSecondary = Color(0xFFD4D4D8); // #d4d4d8 (Zinc 300 — subtitles, details)
  static const Color inkMuted = Color(0xFFA1A1AA);     // #a1a1aa (Zinc 400 — placeholders, disabled)
  static const Color inkFaint = Color(0xFF919BAF);     // #919baf (PC --text-3 — 10px labels, ≥4.5:1 on #09090b)

  // ── Accents & Actions (PC --accent-blue / --accent-blue-bright)
  static const Color accentBlue = Color(0xFF3B82F6);     // #3b82f6 (primary action)
  static const Color accentBlueDeep = Color(0xFF2563EB); // #2563eb (pressed state)

  // ── Status (PC --ok / --warn / --err / --info)
  static const Color positive = Color(0xFF22C55E);       // #22c55e (approve / connected)
  static const Color warning = Color(0xFFEAB308);        // #eab308 (tool approval pending)
  static const Color danger = Color(0xFFEF4444);         // #ef4444 (refuse / error)
  static const Color dangerDeep = Color(0xFFDC2626);     // #dc2626
  static const Color info = Color(0xFF3B82F6);           // #3b82f6 (informational)

  // ── Neutrals (scrims, shadows, camera overlay — PC --scrim / --shadow)
  static const Color overlayScrim = Color(0xFF000000);   // full-black scrim (camera, modal backdrop)
  static const Color shadowNeutral = Color(0xFF000000);  // drop shadows, elevation

  // ── On-fill ink (text/icons over accent & danger fills — PC --on-accent)
  static const Color onAccent = Color(0xFFFAFAFA);       // #fafafa (Zinc-50 — labels on primary)
  static const Color onDanger = Color(0xFFFAFAFA);       // #fafafa (Zinc-50 — labels on error)

  // ── Provider Accent Badges
  static const Color providerOpenAI = Color(0xFF10A37F);
  static const Color providerAnthropic = Color(0xFFD97757);
  static const Color providerGoogle = Color(0xFF4285F4);
  static const Color providerOllama = Color(0xFFF0F0F0);
  static const Color providerOpenRouter = Color(0xFFFF7A45);
  static const Color providerCustom = Color(0xFFA855F7);
}

/// Radius scale (PC ag-doctor-ui --r-sm/md/lg/xl/pill)
abstract class AppRadius {
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
}
