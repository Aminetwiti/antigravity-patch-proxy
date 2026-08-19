import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

enum ToastType { info, success, warning, error }

/// Floating pill-shaped Toast component matching Material 3 and Antigravity 2.0 aesthetics.
class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    switch (type) {
      case ToastType.info:
        HapticFeedback.selectionClick();
        break;
      case ToastType.success:
        HapticFeedback.lightImpact();
        break;
      case ToastType.warning:
        HapticFeedback.mediumImpact();
        break;
      case ToastType.error:
        HapticFeedback.heavyImpact();
        break;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (defaultIcon, iconColor, bg) = switch (type) {
      ToastType.info => (
          Icons.info_outline,
          isDark ? AppColors.accentBlueBright : scheme.primary,
          isDark ? const Color(0xFF1B202B) : scheme.surfaceContainerHighest,
        ),
      ToastType.success => (
          Icons.check_circle_outline,
          AppColors.positive,
          isDark ? const Color(0xFF14241B) : scheme.surfaceContainerHighest,
        ),
      ToastType.warning => (
          Icons.warning_amber_rounded,
          AppColors.warning,
          isDark ? const Color(0xFF2B2114) : scheme.surfaceContainerHighest,
        ),
      ToastType.error => (
          Icons.error_outline,
          isDark ? const Color(0xFFFCA5A5) : scheme.error,
          isDark ? const Color(0xFF2C1417) : scheme.surfaceContainerHighest,
        ),
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        elevation: 8,
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(
            color: isDark ? const Color(0xFF323B4E) : scheme.outlineVariant,
            width: 1,
          ),
        ),
        duration: duration,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon ?? defaultIcon, size: 16, color: iconColor),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                message,
                style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 12.5)).copyWith(
                  color: isDark ? const Color(0xFFF0F4F8) : scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
