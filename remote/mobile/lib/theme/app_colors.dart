import 'package:flutter/material.dart';

/// Antigravity 2.0 Color Palette ("The Quiet Console")
/// Direct token mapping from DESIGN.md
abstract class AppColors {
  // ── Surfaces (Dark Zinc Console)
  static const Color surfaceBase = Color(0xFF18181B);   // #18181b (Zinc 900)
  static const Color surfaceRaised = Color(0xFF1C1C1F); // #1c1c1f (Cards, AppBars)
  static const Color surfaceInput = Color(0xFF27272A);  // #27272a (Inputs, Code blocks)

  // ── Borders
  static const Color borderSubtle = Color(0xFF27272A);  // #27272a
  static const Color borderStrong = Color(0xFF3F3F46);  // #3f3f46

  // ── Ink / Text
  static const Color inkPrimary = Color(0xFFF4F4F5);   // #f4f4f5 (High contrast text)
  static const Color inkSecondary = Color(0xFFD4D4D8); // #d4d4d8 (Zinc 300 - Subtitles, details)
  static const Color inkMuted = Color(0xFFA1A1AA);     // #a1a1aa (Zinc 400 - Placeholders, disabled)

  // ── Accents & Actions
  static const Color accentBlue = Color(0xFF3B82F6);     // #3b82f6 (Primary action)
  static const Color accentBlueDeep = Color(0xFF2563EB); // #2563eb (Pressed state)
  static const Color positive = Color(0xFF22C55E);       // #22c55e (Approuver / Connected)
  static const Color warning = Color(0xFFEAB308);        // #eab308 (Tool approval pending)
  static const Color danger = Color(0xFFEF4444);         // #ef4444 (Refuser / Error)
  static const Color dangerDeep = Color(0xFFDC2626);     // #dc2626

  // ── Provider Accent Badges
  static const Color providerOpenAI = Color(0xFF10A37F);
  static const Color providerAnthropic = Color(0xFFD97757);
  static const Color providerGoogle = Color(0xFF4285F4);
  static const Color providerOllama = Color(0xFFF0F0F0);
  static const Color providerOpenRouter = Color(0xFFFF7A45);
  static const Color providerCustom = Color(0xFFA855F7);
}
