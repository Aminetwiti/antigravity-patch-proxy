import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/chat_stream/models/banner_notification.dart';
import '../theme/app_colors.dart';

/// Composant bannière d'alerte polymorphe et modulaire pour Antigravity Remote.
/// Conforme 1:1 avec les tokens "The Quiet Console" de l'IDE Desktop.
class AppNotificationBanner extends StatelessWidget {
  final BannerNotificationData data;
  final bool isCompact;

  const AppNotificationBanner({
    super.key,
    required this.data,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    Color borderColor;
    Color iconColor;
    IconData iconData;

    switch (data.type) {
      case BannerType.quotaExceeded:
        borderColor = isDark ? const Color(0xFF5C1D24) : scheme.error.withValues(alpha: 0.4);
        iconColor = isDark ? const Color(0xFFFCA5A5) : scheme.error;
        iconData = Icons.indeterminate_check_box_outlined;
        break;
      case BannerType.modelCapacity:
        borderColor = isDark ? const Color(0xFF6B4E1B) : const Color(0xFFEAB308).withValues(alpha: 0.4);
        iconColor = const Color(0xFFEAB308);
        iconData = Icons.cloud_off_rounded;
        break;
      case BannerType.apiKeyInvalid:
        borderColor = isDark ? const Color(0xFF5C1D24) : scheme.error.withValues(alpha: 0.4);
        iconColor = isDark ? const Color(0xFFFCA5A5) : scheme.error;
        iconData = Icons.key_off_rounded;
        break;
      case BannerType.fallbackActive:
        borderColor = isDark ? const Color(0xFF1D3E6B) : AppColors.accentBlue.withValues(alpha: 0.4);
        iconColor = AppColors.accentBlue;
        iconData = Icons.swap_horiz_rounded;
        break;
      case BannerType.contextLimit:
        borderColor = isDark ? const Color(0xFF6B4E1B) : const Color(0xFFEAB308).withValues(alpha: 0.4);
        iconColor = const Color(0xFFEAB308);
        iconData = Icons.memory_rounded;
        break;
    }

    final surfaceBg = isDark
        ? const Color(0xF2191A1E)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.95);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: isCompact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : scheme.onSurface,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              if (data.errorId != null && !isCompact)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: data.errorId!));
                    HapticFeedback.lightImpact();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 11, color: isDark ? AppColors.inkMuted : scheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          'ID',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? AppColors.inkMuted : scheme.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (!isCompact) ...[
            const SizedBox(height: 6),
            Text(
              data.message,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? const Color(0xFFD4D4D8) : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: data.actions.map((action) {
              final isPrimary = action.isPrimary;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    action.onPressed();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? AppColors.accentBlue
                          : (isDark ? Colors.white.withValues(alpha: 0.1) : scheme.surfaceContainerHigh),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                        color: isPrimary ? Colors.white : (isDark ? const Color(0xFFE0E0E0) : scheme.onSurface),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
