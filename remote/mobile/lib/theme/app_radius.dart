import 'package:flutter/widgets.dart';

/// AppRadius : Tokens de rayons de bordure standardisés pour Antigravity Mobile.
/// Remplace l'intégralité des BorderRadius.circular hardcodés.
abstract class AppRadius {
  // Rayons bruts (double)
  static const double r4 = 4.0;
  static const double r6 = 6.0;
  static const double r8 = 8.0;
  static const double r10 = 10.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;
  static const double rFull = 999.0;

  // BorderRadius composés
  static const roundedXs = BorderRadius.all(Radius.circular(r4));
  static const roundedSm = BorderRadius.all(Radius.circular(r6));
  static const roundedMd = BorderRadius.all(Radius.circular(r8));
  static const roundedLg = BorderRadius.all(Radius.circular(r12));
  static const roundedXl = BorderRadius.all(Radius.circular(r16));
  static const rounded2xl = BorderRadius.all(Radius.circular(r24));
  static const roundedPill = BorderRadius.all(Radius.circular(rFull));

  // Modales et BottomSheets
  static const bottomSheetTop = BorderRadius.vertical(top: Radius.circular(r16));
  static const dialog = BorderRadius.all(Radius.circular(r12));
}
