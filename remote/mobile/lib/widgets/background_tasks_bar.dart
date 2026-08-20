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

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.runningTasks.length;
    final taskLabel = count == 1 ? '1 task running' : '$count tasks running';
    final viewInsets = MediaQuery.of(context).viewInsets;
    final rawInsetsBottom = View.of(context).viewInsets.bottom / MediaQuery.of(context).devicePixelRatio;
    final hasKeyboard = viewInsets.bottom > 50 || rawInsetsBottom > 50;
    final isActuallyExpanded = (count == 1 || _expanded) && !hasKeyboard;

    Widget buildTaskItem(String task) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => widget.onTapTask?.call(task),
          child: Row(
            children: [
              // Arc spinner rotatif élégant
              RotationTransition(
                turns: _spinController,
                child: Icon(
                  Icons.sync,
                  size: 13,
                  color: isDark ? const Color(0xFF8E8E93) : scheme.outline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: isDark ? const Color(0xFFD4D4D4) : scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onStopTask != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onStopTask!(task);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Text(
                      'Stop',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: hasKeyboard ? 2 : 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2024) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      padding: EdgeInsets.fromLTRB(14, hasKeyboard ? 6 : 10, 14, hasKeyboard ? 6 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : "N tasks running" + Chevron
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
              if (count == 1 && widget.onTapTask != null) {
                widget.onTapTask!(widget.runningTasks.first);
              } else if (widget.onViewTasks != null) {
                widget.onViewTasks!();
              }
            },
            child: Row(
              children: [
                Text(
                  taskLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF9E9E9E) : scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(
                  isActuallyExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isDark ? const Color(0xFF757575) : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          // Liste des tâches actives style Antigravity 2.0 (image 2)
          if (isActuallyExpanded) ...[
            SizedBox(height: hasKeyboard ? 4 : 8),
            if (count > 3)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final task in widget.runningTasks) buildTaskItem(task),
                  ],
                ),
              )
            else
              for (final task in widget.runningTasks) buildTaskItem(task),
          ],
        ],
      ),
    );
  }
}
