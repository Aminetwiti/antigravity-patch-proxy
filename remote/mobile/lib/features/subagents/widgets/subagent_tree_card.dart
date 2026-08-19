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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.subagents.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
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
                      color: isDark ? const Color(0xFFE6EDF3) : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF21262D) : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF4B5563),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7681),
                  ),
                  const Spacer(),
                  if (widget.onOpenFullTree != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      onPressed: widget.onOpenFullTree,
                      tooltip: 'Ouvrir le DAG complet',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7681),
                    ),
                ],
              ),
            ),
          ),

          // Subagents List
          if (_isExpanded) ...[
            const Divider(height: 1, color: Color(0xFF30363D)),
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

                return InkWell(
                  onTap: () => widget.onSelectSubagent?.call(subagent),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Role Title & Worked duration
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
                                  color: isDark ? const Color(0xFFF4F4F5) : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isRunning ? 'Working...' : subagent.displayWorkedFor,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7681),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 10),

                        // Right: Status Icon (checkmark circle / spinner / error)
                        if (isRunning)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.accentBlueBright,
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
                            color: isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7681),
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
