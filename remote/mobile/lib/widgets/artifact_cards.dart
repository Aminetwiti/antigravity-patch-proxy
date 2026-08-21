import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

/// Carte interactive d'Implementation Plan dans le chat (Antigravity 2.0 Desktop Style)
class ImplementationPlanCard extends StatelessWidget {
  final String title;
  final String? summary;
  final VoidCallback? onProceed;
  final VoidCallback onViewPlan;

  const ImplementationPlanCard({
    super.key,
    this.title = 'Implementation Plan',
    this.summary,
    this.onProceed,
    required this.onViewPlan,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161B) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF262930) : scheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onViewPlan();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                    ),
                  ),
                ),
                if (onProceed != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      onProceed!();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2838) : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Proceed',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte interactive de Walkthrough dans le chat (Antigravity 2.0 Desktop Style)
class WalkthroughCard extends StatelessWidget {
  final String title;
  final String? summary;
  final VoidCallback onViewWalkthrough;

  const WalkthroughCard({
    super.key,
    this.title = 'Walkthrough',
    this.summary,
    required this.onViewWalkthrough,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161B) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF262930) : scheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onViewWalkthrough();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 16,
                  color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                  ),
                ),
              ],
            ),
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
  final ValueChanged<String>? onOpenFile;

  const FilesChangedCard({
    super.key,
    required this.files,
    this.additions = 0,
    this.deletions = 0,
    required this.onReview,
    this.onOpenFile,
  });

  @override
  State<FilesChangedCard> createState() => _FilesChangedCardState();
}

class _FilesChangedCardState extends State<FilesChangedCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _anim;
  late final Animation<double> _sizeFactor;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
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

  Color _iconColorFor(String name, bool isDark) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'dart': return const Color(0xFF29B6F6);
      case 'go': return const Color(0xFF00ADD8);
      case 'ts': case 'tsx': return const Color(0xFF3178C6);
      case 'js': case 'jsx': return const Color(0xFFF7DF1E);
      case 'json': case 'yaml': case 'yml': case 'toml': return const Color(0xFFA074C4);
      case 'md': case 'txt': return const Color(0xFF519ABA);
      case 'sh': case 'bat': case 'ps1': return const Color(0xFF4CAF50);
      default: return isDark ? const Color(0xFF9E9FA9) : const Color(0xFF6E707A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.files.length;
    final label = '$count ${count > 1 ? 'files changed' : 'file changed'}';

    const positiveColor = Color(0xFF22C55E);
    const negativeColor = Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161B) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF262930) : scheme.outlineVariant,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row (Antigravity 2.0 exact UI) ───────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // File-count label
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                          ),
                        ),
                        // Additions & Deletions
                        if (widget.additions > 0 || widget.deletions > 0) ...[
                          const SizedBox(width: 6),
                          if (widget.additions > 0) ...[
                            Text(
                              '+${widget.additions}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: positiveColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                          if (widget.deletions > 0) ...[
                            if (widget.additions > 0) const SizedBox(width: 4),
                            Text(
                              '-${widget.deletions}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: negativeColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(width: 4),
                        // Chevron
                        AnimatedRotation(
                          turns: _expanded ? 0 : -0.25,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: isDark ? const Color(0xFF8E929E) : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Review button (Desktop Antigravity pill style)
                Material(
                  color: isDark ? const Color(0xFF1F2228) : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: widget.onReview,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333742) : scheme.outlineVariant,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.difference_outlined,
                            size: 13,
                            color: isDark ? const Color(0xFFB0B4C0) : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4.5),
                          Text(
                            'Review',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Expandable file list ──────────────────────────────────────
          SizeTransition(
            sizeFactor: _sizeFactor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...widget.files.map((file) {
                  final normalized = file.replaceAll('\\', '/');
                  final lastSlash = normalized.lastIndexOf('/');
                  final fileName = lastSlash >= 0
                      ? normalized.substring(lastSlash + 1)
                      : normalized;
                  final dirPath = lastSlash >= 0
                      ? normalized.substring(0, lastSlash)
                      : '';

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onOpenFile?.call(file),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4.5),
                        child: Row(
                          children: [
                            Icon(
                              _iconFor(fileName),
                              size: 13,
                              color: _iconColorFor(fileName, isDark),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: fileName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    if (dirPath.isNotEmpty)
                                      TextSpan(
                                        text: '  ...$dirPath',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? const Color(0xFF7E818D)
                                              : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          fontFamily: 'monospace',
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
                  );
                }),
                const SizedBox(height: 4),
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
