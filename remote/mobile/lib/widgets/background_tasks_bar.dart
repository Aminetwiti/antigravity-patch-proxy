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

    final count = runningTasks.length;
    final firstTask = runningTasks.first;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.accentBlue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onViewTasks,
              child: Text(
                '$count running • $firstTask',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkPrimary,
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
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Icon(Icons.stop_rounded, size: 14, color: AppColors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
