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
    HapticFeedback.selectionClick();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (defaultIcon, iconColor, bg) = switch (type) {
      ToastType.info => (
          Icons.info_outline,
          scheme.primary,
          scheme.surfaceContainerHighest,
        ),
      ToastType.success => (
          Icons.check_circle_outline,
          scheme.primary,
          scheme.surfaceContainerHighest,
        ),
      ToastType.warning => (
          Icons.warning_amber_rounded,
          scheme.tertiary,
          scheme.surfaceContainerHighest,
        ),
      ToastType.error => (
          Icons.error_outline,
          scheme.error,
          scheme.surfaceContainerHighest,
        ),
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 6,
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        duration: duration,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon ?? defaultIcon, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                  color: scheme.onSurface,
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
