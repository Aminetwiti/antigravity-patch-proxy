import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

/// Barre de statut des tâches de fond (Sticky) inspirée fidèlement d'Antigravity IDE
class BackgroundTasksBar extends StatefulWidget {
  final List<String> runningTasks;
  final ValueChanged<String>? onTapTask;
  final ValueChanged<String>? onStopTask;
  final VoidCallback? onViewTasks;

  const BackgroundTasksBar({
    super.key,
    required this.runningTasks,
    this.onTapTask,
    this.onStopTask,
    this.onViewTasks,
  });

  @override
  State<BackgroundTasksBar> createState() => _BackgroundTasksBarState();
}

class _BackgroundTasksBarState extends State<BackgroundTasksBar> with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  bool _expanded = false;
  final Map<String, DateTime> _taskStartTimes = {};
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _trackTasks(widget.runningTasks);
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.runningTasks.isNotEmpty) {
        setState(() {});
      }
    });
  }

  void _trackTasks(List<String> tasks) {
    final now = DateTime.now();
    for (final t in tasks) {
      _taskStartTimes.putIfAbsent(t, () => now);
    }
    _taskStartTimes.removeWhere((key, _) => !tasks.contains(key));
  }

  @override
  void didUpdateWidget(covariant BackgroundTasksBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _trackTasks(widget.runningTasks);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  String _formatElapsed(String task) {
    final start = _taskStartTimes[task];
    if (start == null) return '';
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '${mins}m ${remSecs}s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.runningTasks.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.runningTasks.length;
    final taskLabel = count == 1 ? '1 task running' : '$count tasks running';
    final viewInsets = MediaQuery.of(context).viewInsets;
    final rawInsetsBottom = View.of(context).viewInsets.bottom / MediaQuery.of(context).devicePixelRatio;
    final hasKeyboard = viewInsets.bottom > 50 || rawInsetsBottom > 50;
    final isActuallyExpanded = _expanded && !hasKeyboard;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: hasKeyboard ? 2 : 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderStrong : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête "1 task running" avec chevron
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              if (count > 1) {
                setState(() => _expanded = !_expanded);
              } else if (widget.onTapTask != null) {
                widget.onTapTask!(widget.runningTasks.first);
              } else if (widget.onViewTasks != null) {
                widget.onViewTasks!();
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: hasKeyboard ? 4 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ligne 1 : "1 task running" + chevron
                  Row(
                    children: [
                      Text(
                        taskLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isActuallyExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (!isActuallyExpanded) ...[
                    SizedBox(height: hasKeyboard ? 3 : 6),
                    // Ligne 2 : Spinner + commande + chronomètre
                    Row(
                      children: [
                        RotationTransition(
                          turns: _spinController,
                          child: const Icon(
                            Icons.sync,
                            size: 13,
                            color: AppColors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.runningTasks.first,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_formatElapsed(widget.runningTasks.first).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceHover : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatElapsed(widget.runningTasks.first),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'monospace',
                                color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (count == 1 && widget.onStopTask != null) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.onStopTask!(widget.runningTasks.first);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                'Stop',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Liste déroulante multi-tâches
          if (isActuallyExpanded && count > 1) ...[
            Divider(
              height: 1,
              color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            ...widget.runningTasks.map((task) {
              final elapsed = _formatElapsed(task);
              return InkWell(
                onTap: () => widget.onTapTask?.call(task),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(
                        Icons.terminal_rounded,
                        size: 13,
                        color: isDark ? AppColors.accentBlueBright : scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (elapsed.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          elapsed,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (widget.onStopTask != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            widget.onStopTask!(task);
                          },
                          child: const Icon(Icons.stop_rounded, size: 14, color: AppColors.danger),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
