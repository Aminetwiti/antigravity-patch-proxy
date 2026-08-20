import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../models/subagent_item.dart';

/// Carte visuelle affichant l'arborescence des sous-agents en temps réel
/// directement dans l'interface de discussion (inspiré de Claude Code / Codex).
class SubagentTreeCard extends StatefulWidget {
  final List<SubagentItem> subagents;
  final VoidCallback? onOpenFullTree;
  final ValueChanged<SubagentItem>? onSelectSubagent;

  const SubagentTreeCard({
    super.key,
    required this.subagents,
    this.onOpenFullTree,
    this.onSelectSubagent,
  });

  @override
  State<SubagentTreeCard> createState() => _SubagentTreeCardState();
}

class _SubagentTreeCardState extends State<SubagentTreeCard> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.subagents.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.subagents.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderStrong : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar: "Subagents  4  v"
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Subagents',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceHover : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                  ),
                  const Spacer(),
                  if (widget.onOpenFullTree != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      onPressed: widget.onOpenFullTree,
                      tooltip: 'Ouvrir le DAG complet',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),

          // Subagents List
          if (_isExpanded) ...[
            Divider(
              height: 1,
              color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: widget.subagents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final subagent = widget.subagents[index];
                final isRunning = subagent.status.toLowerCase() == 'running';
                final isErrored = subagent.status.toLowerCase() == 'errored' || subagent.status.toLowerCase() == 'canceling';
                final currentTool = subagent.stateDetail;

                return InkWell(
                  onTap: () => widget.onSelectSubagent?.call(subagent),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Role Title & Worked duration / Current tool
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                subagent.role,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (isRunning && currentTool != null && currentTool.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.code_rounded,
                                      size: 11,
                                      color: AppColors.accentBlueBright,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        currentTool,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: AppColors.accentBlueBright,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Text(
                                  isRunning ? 'Working...' : subagent.displayWorkedFor,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 10),

                        // Right: Status Icon (pulsing live badge / checkmark / error)
                        if (isRunning)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF132338) : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: AppColors.accentBlueBright.withValues(alpha: 0.45),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.accentBlueBright,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x6638BDF8),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4.5),
                                const Text(
                                  'Actif',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accentBlueBright,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isErrored)
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: AppColors.danger,
                          )
                        else
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                            color: isDark ? AppColors.inkMuted : scheme.outline,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
