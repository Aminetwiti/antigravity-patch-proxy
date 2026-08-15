import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

/// Carte interactive d'Implementation Plan dans le chat avec bouton d'action Proceed
class ImplementationPlanCard extends StatelessWidget {
  final String title;
  final String summary;
  final VoidCallback onProceed;
  final VoidCallback onViewPlan;

  const ImplementationPlanCard({
    super.key,
    this.title = 'Implementation Plan',
    required this.summary,
    required this.onProceed,
    required this.onViewPlan,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: isDark ? AppColors.borderStrong : scheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: onViewPlan,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),

          // Summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onProceed();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Proceed ⌘↵',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onViewPlan,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: isDark ? AppColors.borderSubtle : scheme.outlineVariant, width: 1),
                    ),
                    child: Text(
                      'Lire le plan',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte interactive de Walkthrough dans le chat
class WalkthroughCard extends StatelessWidget {
  final String title;
  final String summary;
  final VoidCallback onViewWalkthrough;

  const WalkthroughCard({
    super.key,
    this.title = 'Walkthrough',
    required this.summary,
    required this.onViewWalkthrough,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: isDark ? AppColors.borderStrong : scheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onViewWalkthrough,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 16, color: AppColors.positive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte interactive de fichiers modifiés avec bouton Review
class FilesChangedCard extends StatefulWidget {
  final List<String> files;
  final int additions;
  final int deletions;
  final VoidCallback onReview;

  const FilesChangedCard({
    super.key,
    required this.files,
    this.additions = 0,
    this.deletions = 0,
    required this.onReview,
  });

  @override
  State<FilesChangedCard> createState() => _FilesChangedCardState();
}

class _FilesChangedCardState extends State<FilesChangedCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.files.length;
    final title = '$count ${count > 1 ? 'files changed' : 'file changed'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: isDark ? AppColors.borderStrong : scheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${widget.additions} -${widget.deletions}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.positive : const Color(0xFF1A7F37),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onReview();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: isDark ? AppColors.borderSubtle : scheme.outlineVariant, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rate_review_outlined, size: 12, color: scheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          'Review',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // File list (if expanded)
          if (_expanded && widget.files.isNotEmpty) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            ...widget.files.map((file) {
              final fileName = file.split(RegExp(r'[\\/]')).last;
              final path = file.length > fileName.length ? file : '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined, size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (path.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          path,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

/// Carte interactive de suivi des sous-tâches (TaskTrackerCard)
class TaskTrackerCard extends StatelessWidget {
  final String title;
  final String summary;
  final bool isComplete;
  final VoidCallback? onTap;

  const TaskTrackerCard({
    super.key,
    this.title = 'Task',
    required this.summary,
    this.isComplete = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: isDark ? AppColors.borderStrong : scheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isComplete ? Icons.task_alt : Icons.checklist_rtl_outlined,
                    size: 16,
                    color: isComplete
                        ? (isDark ? AppColors.positive : const Color(0xFF1A7F37))
                        : (isDark ? AppColors.warning : const Color(0xFF9A6700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (isComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.positive : const Color(0xFF1A7F37)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Complete',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.positive : const Color(0xFF1A7F37),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
