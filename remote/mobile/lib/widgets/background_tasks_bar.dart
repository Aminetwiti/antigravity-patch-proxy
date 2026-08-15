import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

/// Barre de statut des tâches de fond (Sticky) inspirée d'AG2R
class BackgroundTasksBar extends StatelessWidget {
  final List<String> runningTasks;
  final VoidCallback? onStopTask;
  final VoidCallback? onViewTasks;

  const BackgroundTasksBar({
    super.key,
    required this.runningTasks,
    this.onStopTask,
    this.onViewTasks,
  });

  @override
  Widget build(BuildContext context) {
    if (runningTasks.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = runningTasks.length;
    final firstTask = runningTasks.first;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: isDark ? AppColors.borderStrong : scheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onViewTasks,
              child: Text(
                '$count running • $firstTask',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (onStopTask != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onStopTask!();
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isDark ? AppColors.borderSubtle : scheme.outlineVariant),
                ),
                child: Icon(Icons.stop_rounded, size: 14, color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
