import 'package:flutter/material.dart';

/// Centralized layout tokens, spacings, and edge insets for Antigravity Remote Mobile.
/// Eliminates hardcoded magic numbers across widget trees.
abstract class AppSpacing {
  // ─── Dimensions (dp) ───────────────────────────────────────────────────────
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space14 = 14.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;

  // ─── Border Radii ─────────────────────────────────────────────────────────
  static const double radiusXs = 4.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusFull = 999.0;

  static final BorderRadius borderRadiusXs = BorderRadius.circular(radiusXs);
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // ─── Horizontal Gaps (SizedBox) ───────────────────────────────────────────
  static const SizedBox hGap2 = SizedBox(width: space2);
  static const SizedBox hGap4 = SizedBox(width: space4);
  static const SizedBox hGap6 = SizedBox(width: space6);
  static const SizedBox hGap8 = SizedBox(width: space8);
  static const SizedBox hGap10 = SizedBox(width: space10);
  static const SizedBox hGap12 = SizedBox(width: space12);
  static const SizedBox hGap16 = SizedBox(width: space16);
  static const SizedBox hGap20 = SizedBox(width: space20);
  static const SizedBox hGap24 = SizedBox(width: space24);

  // ─── Vertical Gaps (SizedBox) ─────────────────────────────────────────────
  static const SizedBox vGap2 = SizedBox(height: space2);
  static const SizedBox vGap4 = SizedBox(height: space4);
  static const SizedBox vGap6 = SizedBox(height: space6);
  static const SizedBox vGap8 = SizedBox(height: space8);
  static const SizedBox vGap10 = SizedBox(height: space10);
  static const SizedBox vGap12 = SizedBox(height: space12);
  static const SizedBox vGap14 = SizedBox(height: space14);
  static const SizedBox vGap16 = SizedBox(height: space16);
  static const SizedBox vGap20 = SizedBox(height: space20);
  static const SizedBox vGap24 = SizedBox(height: space24);
  static const SizedBox vGap32 = SizedBox(height: space32);
  static const SizedBox vGap40 = SizedBox(height: space40);

  // ─── Edge Insets ──────────────────────────────────────────────────────────
  static const EdgeInsets edgeInsetsZero = EdgeInsets.zero;
  static const EdgeInsets edgeInsetsA4 = EdgeInsets.all(space4);
  static const EdgeInsets edgeInsetsA8 = EdgeInsets.all(space8);
  static const EdgeInsets edgeInsetsA12 = EdgeInsets.all(space12);
  static const EdgeInsets edgeInsetsA16 = EdgeInsets.all(space16);
  static const EdgeInsets edgeInsetsA20 = EdgeInsets.all(space20);
  static const EdgeInsets edgeInsetsA24 = EdgeInsets.all(space24);

  static const EdgeInsets edgeInsetsH8 = EdgeInsets.symmetric(horizontal: space8);
  static const EdgeInsets edgeInsetsH12 = EdgeInsets.symmetric(horizontal: space12);
  static const EdgeInsets edgeInsetsH16 = EdgeInsets.symmetric(horizontal: space16);
  static const EdgeInsets edgeInsetsH20 = EdgeInsets.symmetric(horizontal: space20);

  static const EdgeInsets edgeInsetsV4 = EdgeInsets.symmetric(vertical: space4);
  static const EdgeInsets edgeInsetsV8 = EdgeInsets.symmetric(vertical: space8);
  static const EdgeInsets edgeInsetsV12 = EdgeInsets.symmetric(vertical: space12);
  static const EdgeInsets edgeInsetsV16 = EdgeInsets.symmetric(vertical: space16);
}
