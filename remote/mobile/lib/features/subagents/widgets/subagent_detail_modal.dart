import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/protocol/daemon_api.dart';
import '../../../theme/app_colors.dart';
import '../models/subagent_item.dart';

/// Modal affichant les détails complets d'un sous-agent (mission, prompt, statut, durée, logs).
class SubagentDetailModal extends StatefulWidget {
  final SubagentItem agent;
  final DaemonApi? api;
  final String? cascadeId;
  final VoidCallback? onKill;

  const SubagentDetailModal({
    super.key,
    required this.agent,
    this.api,
    this.cascadeId,
    this.onKill,
  });

  static Future<void> show(
    BuildContext context, {
    required SubagentItem agent,
    DaemonApi? api,
    String? cascadeId,
    VoidCallback? onKill,
  }) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SubagentDetailModal(
        agent: agent,
        api: api,
        cascadeId: cascadeId,
        onKill: onKill,
      ),
    );
  }

  @override
  State<SubagentDetailModal> createState() => _SubagentDetailModalState();
}

class _SubagentDetailModalState extends State<SubagentDetailModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.agent.status.toLowerCase() == 'running') {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'running':
        return AppColors.accentBlue;
      case 'completed':
      case 'done':
      case 'terminé':
        return AppColors.positive;
      case 'waiting_for_input':
      case 'waiting_for_dependents':
      case 'waiting_for_message':
        return scheme.tertiary;
      case 'errored':
      case 'canceling':
        return scheme.error;
      case 'idle':
      default:
        return scheme.outline;
    }
  }

  String _formatStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return 'En cours';
      case 'completed':
      case 'done':
      case 'terminé':
        return 'Terminé';
      case 'waiting_for_input':
        return 'En attente (saisie)';
      case 'waiting_for_dependents':
        return 'En attente (dépendances)';
      case 'waiting_for_message':
        return 'En attente (message)';
      case 'errored':
        return 'Erreur';
      case 'canceling':
        return 'Annulation';
      case 'idle':
        return 'Inactif';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(widget.agent.status, scheme);
    final isRunning = widget.agent.status.toLowerCase() == 'running';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border.all(
          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
          width: 1,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.smart_toy_outlined, size: 22, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.agent.typeName ?? 'agent',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.agent.role,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isRunning)
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, _) => Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: _pulseAnimation.value),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 5),
                            Text(
                              _formatStatusLabel(widget.agent.status),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '•  ${widget.agent.displayWorkedFor}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Conversation / Subagent ID Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.fingerprint_rounded, size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID DU SOUS-AGENT',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.agent.id.isNotEmpty ? widget.agent.id : '(Généré à l\'exécution)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (widget.agent.id.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: 'Copier l\'ID',
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: widget.agent.id));
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ID copié dans le presse-papier'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    if (widget.agent.stateDetail != null && widget.agent.stateDetail!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: AppColors.accentBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal_rounded, size: 16, color: AppColors.accentBlueBright),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.agent.stateDetail!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: AppColors.accentBlueBright,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Text(
                      'Mission / Instructions',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: SelectableText(
                        widget.agent.prompt != null && widget.agent.prompt!.isNotEmpty
                            ? widget.agent.prompt!
                            : 'Aucun prompt explicite spécifié pour ce sous-agent.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Action row
                    Row(
                      children: [
                        if (widget.agent.prompt != null && widget.agent.prompt!.isNotEmpty)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: widget.agent.prompt!));
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Instructions copiées'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Copier Mission'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                              ),
                            ),
                          ),
                        if (isRunning && (widget.onKill != null || widget.api != null)) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                if (widget.onKill != null) {
                                  widget.onKill!();
                                } else if (widget.api != null && widget.agent.id.isNotEmpty) {
                                  widget.api!.sendCommand('/stop');
                                }
                              },
                              icon: const Icon(Icons.stop_circle_outlined, size: 16),
                              label: const Text('Arrêter'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: scheme.error,
                                foregroundColor: scheme.onError,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
