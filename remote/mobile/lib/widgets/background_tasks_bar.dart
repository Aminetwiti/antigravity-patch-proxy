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

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.runningTasks.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.runningTasks.length;
    final taskLabel = count == 1 ? '1 task running' : '$count tasks running';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderStrong : const Color(0xFF30363D),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          color: isDark ? AppColors.inkPrimary : const Color(0xFFE6EDF3),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isDark ? AppColors.inkMuted : const Color(0xFF8B949E),
                      ),
                    ],
                  ),
                  if (!_expanded) ...[
                    const SizedBox(height: 6),
                    // Ligne 2 : Spinner + commande
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
                              color: isDark ? AppColors.inkMuted : const Color(0xFF8B949E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
          if (_expanded && count > 1) ...[
            const Divider(height: 1, color: Color(0xFF26282E)),
            ...widget.runningTasks.map((task) {
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
                        color: isDark ? AppColors.inkMuted : const Color(0xFF8B949E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: isDark ? AppColors.inkPrimary : const Color(0xFFE6EDF3),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.onStopTask != null) ...[
                        const SizedBox(width: 6),
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
