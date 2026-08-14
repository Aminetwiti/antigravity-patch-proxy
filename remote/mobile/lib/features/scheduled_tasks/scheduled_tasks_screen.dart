import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'models/scheduled_task_item.dart';

class ScheduledTasksScreen extends StatelessWidget {
  final List<ScheduledTaskItem> tasks;
  final ValueChanged<String>? onCancelTask;
  final ValueChanged<String>? onTriggerNow;
  final Future<void> Function()? onRefresh;

  const ScheduledTasksScreen({
    super.key,
    required this.tasks,
    this.onCancelTask,
    this.onTriggerNow,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgSurface = isDark ? AppColors.surfaceBase : theme.colorScheme.surface;
    final cardBg = isDark ? AppColors.surfaceRaised : theme.colorScheme.surfaceContainer;
    final borderCol = isDark ? AppColors.borderSubtle : theme.colorScheme.outlineVariant;

    final content = tasks.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 48,
                    color: isDark ? AppColors.inkMuted : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune tâche planifiée',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.inkPrimary : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Les cron jobs récurrents et timers s\'afficheront ici.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.inkMuted : theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              final isCron = task.cronExpression != null && task.cronExpression!.isNotEmpty;

              return Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: borderCol, width: 1),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: Schedule Type badge + Task ID + Cancel Action
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCron
                                ? AppColors.accentBlue.withValues(alpha: 0.15)
                                : AppColors.positive.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: isCron
                                  ? AppColors.accentBlue.withValues(alpha: 0.3)
                                  : AppColors.positive.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCron ? Icons.repeat : Icons.timer_outlined,
                                size: 12,
                                color: isCron ? AppColors.accentBlue : AppColors.positive,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isCron ? 'Cron Job' : 'Timer',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isCron ? AppColors.accentBlue : AppColors.positive,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (task.isDaemon) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHover,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Text(
                              'Daemon',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (onCancelTask != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
                            tooltip: 'Annuler la tâche',
                            onPressed: () => onCancelTask!(task.id),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Prompt Title
                    Text(
                      task.prompt,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.inkPrimary : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Details: Cron Expression or Duration
                    if (isCron)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceInput : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.code,
                              size: 13,
                              color: isDark ? AppColors.inkFaint : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              task.cronExpression!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (task.durationSeconds != null)
                      Text(
                        'Durée: ${task.durationSeconds}s',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.inkMuted : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Bottom info: Iterations & Trigger Button
                    Row(
                      children: [
                        Icon(
                          Icons.insights,
                          size: 14,
                          color: isDark ? AppColors.inkFaint : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${task.iterationsRun} itérations',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.inkMuted : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (onTriggerNow != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 14),
                            label: const Text('Trigger Now', style: TextStyle(fontSize: 12)),
                            onPressed: () => onTriggerNow!(task.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentBlue,
                              side: const BorderSide(color: AppColors.accentBlue, width: 0.9),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );

    return Scaffold(
      backgroundColor: bgSurface,
      appBar: AppBar(
        title: Text('Scheduled Tasks (${tasks.length})'),
        backgroundColor: isDark ? AppColors.surfaceRaised : theme.colorScheme.surfaceContainer,
        elevation: 0,
      ),
      body: onRefresh != null
          ? RefreshIndicator(
              onRefresh: onRefresh!,
              child: content,
            )
          : content,
    );
  }
}
