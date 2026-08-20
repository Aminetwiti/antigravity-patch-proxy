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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        gradient: AppGradients.cardCool(isDark: isDark),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF3186FF).withValues(alpha: 0.3) : scheme.primary.withValues(alpha: 0.25),
          width: 1,
        ),
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
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3186FF).withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF3186FF)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.1,
                          ),
                        ),
                        Text(
                          'PLAN D\'EXÉCUTION AGENT',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: isDark ? const Color(0xFF749BFF) : const Color(0xFF3186FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),

          // Summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              summary,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? const Color(0xFFD4D4D8) : scheme.onSurfaceVariant,
                height: 1.45,
              ),
              maxLines: 4,
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: AppGradients.accentCta,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3186FF).withValues(alpha: isDark ? 0.35 : 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Proceed ⌘↵',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined, size: 13.5, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Text(
                          'Lire le plan',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

/// Carte interactive de Walkthrough dans le chat (Antigravity 2.0 Desktop Style)
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        gradient: AppGradients.cardCool(isDark: isDark),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF00B95C).withValues(alpha: 0.3) : const Color(0xFF00B95C).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onViewWalkthrough();
        },
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B95C).withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.verified_outlined, size: 16, color: Color(0xFF00B95C)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const Text(
                          'RÉSUMÉ DES CHANGEMENTS & VALIDATION',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Color(0xFF00B95C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFFD4D4D8) : scheme.onSurfaceVariant,
                  height: 1.45,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF14241B) : const Color(0xFFE6F7EC),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: const Color(0xFF00B95C).withValues(alpha: isDark ? 0.4 : 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined, size: 13, color: Color(0xFF00B95C)),
                        SizedBox(width: 5),
                        Text(
                          'Consulter le Walkthrough',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF00B95C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Session-result card — matches the Antigravity IDE inline summary:
/// "3 files changed  +467  -223  >"  with a [Review] button.
/// Collapsed by default; tapping the row expands the file list.
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

class _FilesChangedCardState extends State<FilesChangedCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _anim;
  late final Animation<double> _sizeFactor;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _sizeFactor = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _anim.forward() : _anim.reverse();
    HapticFeedback.selectionClick();
  }

  IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'dart': return Icons.flutter_dash_outlined;
      case 'go': return Icons.code_rounded;
      case 'ts': case 'tsx': case 'js': case 'jsx': return Icons.javascript_rounded;
      case 'json': case 'yaml': case 'yml': case 'toml': return Icons.settings_suggest_outlined;
      case 'md': case 'txt': return Icons.article_outlined;
      case 'sh': case 'bat': case 'ps1': return Icons.terminal_rounded;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.files.length;
    final label = '$count ${count > 1 ? 'files changed' : 'file changed'}';

    final positiveColor = isDark ? AppColors.positive : const Color(0xFF1A7F37);
    final negativeColor = isDark ? AppColors.danger : const Color(0xFFCF222E);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.borderStrong : scheme.outlineVariant,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ───────────────────────────────────────────────
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // File-count label
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Additions
                  if (widget.additions > 0) ...[
                    Text(
                      '+${widget.additions}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: positiveColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  // Deletions
                  if (widget.deletions > 0)
                    Text(
                      '-${widget.deletions}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: negativeColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  const Spacer(),
                  // Expand chevron
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Review button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onReview();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceInput
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderSubtle
                              : scheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rate_review_outlined,
                              size: 12, color: scheme.primary),
                          const SizedBox(width: 4),
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
          ),

          // ── Expandable file list ──────────────────────────────────────
          SizeTransition(
            sizeFactor: _sizeFactor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: scheme.outlineVariant),
                ...widget.files.map((file) {
                  final normalized = file.replaceAll('\\', '/');
                  final lastSlash = normalized.lastIndexOf('/');
                  final fileName = lastSlash >= 0
                      ? normalized.substring(lastSlash + 1)
                      : normalized;
                  final dirPath = lastSlash >= 0
                      ? normalized.substring(0, lastSlash)
                      : '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          _iconFor(fileName),
                          size: 13,
                          color: scheme.primary.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: fileName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                if (dirPath.isNotEmpty)
                                  TextSpan(
                                    text: '  $dirPath',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
              ],
            ),
          ),
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
