import 'package:flutter/material.dart';
import 'models/scheduled_task_item.dart';
import '../theme/app_colors.dart';

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
    final scheme = theme.colorScheme;
    final bgSurface = scheme.surface;
    final cardBg = scheme.surfaceContainer;
    final borderCol = scheme.outlineVariant;

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
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune tâche planifiée',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Les cron jobs récurrents et timers s\'afficheront ici.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
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
                                ? scheme.primary.withValues(alpha: 0.15)
                                : scheme.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: isCron
                                  ? scheme.primary.withValues(alpha: 0.3)
                                  : scheme.tertiary.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCron ? Icons.repeat : Icons.timer_outlined,
                                size: 12,
                                color: isCron ? scheme.primary : scheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isCron ? 'Cron Job' : 'Timer',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isCron ? scheme.primary : scheme.tertiary,
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
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              'Daemon',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (onCancelTask != null)
                          IconButton(
                            icon: Icon(Icons.close, size: 16, color: scheme.error),
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
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Details: Cron Expression or Duration
                    if (isCron)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.code,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              task.cronExpression!,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
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
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Bottom info: Iterations & Trigger Button
                    Row(
                      children: [
                        Icon(
                          Icons.insights,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${task.iterationsRun} itérations',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (onTriggerNow != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 14),
                            label: const Text('Trigger Now', style: TextStyle(fontSize: 12)),
                            onPressed: () => onTriggerNow!(task.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.primary,
                              side: BorderSide(color: scheme.primary, width: 0.9),
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
        backgroundColor: scheme.surfaceContainer,
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
