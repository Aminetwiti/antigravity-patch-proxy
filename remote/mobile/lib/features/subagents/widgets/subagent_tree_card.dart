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

  Color _getStatusColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'running':
        return scheme.primary;
      case 'waiting_for_input':
      case 'waiting_for_dependents':
      case 'waiting_for_message':
        return scheme.tertiary;
      case 'errored':
      case 'canceling':
        return scheme.error;
      case 'completed':
        return AppColors.positive;
      case 'idle':
      default:
        return scheme.outline;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return Icons.autorenew;
      case 'waiting_for_input':
      case 'waiting_for_dependents':
      case 'waiting_for_message':
        return Icons.pause_circle_outline;
      case 'errored':
      case 'canceling':
        return Icons.error_outline;
      case 'completed':
        return Icons.check_circle_outline;
      case 'idle':
      default:
        return Icons.radio_button_unchecked;
    }
  }

  String _formatStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return 'En cours';
      case 'waiting_for_input':
        return 'En attente';
      case 'completed':
        return 'Terminé';
      case 'errored':
        return 'Erreur';
      case 'idle':
        return 'Inactif';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subagents.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final activeCount = widget.subagents.where((s) => s.status.toLowerCase() == 'running').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: activeCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Arborescence Sous-Agents (${widget.subagents.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (activeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$activeCount actif(s)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (widget.onOpenFullTree != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      onPressed: widget.onOpenFullTree,
                      tooltip: 'Ouvrir le DAG complet',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Tree nodes
          if (_isExpanded) ...[
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              itemCount: widget.subagents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final subagent = widget.subagents[index];
                final isLast = index == widget.subagents.length - 1;
                final statusColor = _getStatusColor(subagent.status, scheme);
                final isRunning = subagent.status.toLowerCase() == 'running';

                return InkWell(
                  onTap: () => widget.onSelectSubagent?.call(subagent),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tree branch prefix
                        Text(
                          isLast ? '└─ ' : '├─ ',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: scheme.outline,
                          ),
                        ),
                        // Status icon
                        Icon(
                          _getStatusIcon(subagent.status),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 8),
                        // Role & Detail
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    subagent.role,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  if (subagent.typeName != null && subagent.typeName != subagent.role) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${subagent.typeName})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    _formatStatusLabel(subagent.status),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isRunning ? FontWeight.bold : FontWeight.normal,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              if (subagent.stateDetail != null && subagent.stateDetail!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subagent.stateDetail!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
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
