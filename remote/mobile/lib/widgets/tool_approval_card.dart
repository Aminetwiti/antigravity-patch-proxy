import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/messages.dart';
import '../theme/app_colors.dart';

class ToolApprovalCard extends StatefulWidget {
  final ToolApprovalRequest request;
  final Function(ToolDecision decision, {ApprovalScope scope}) onDecision;
  // true après approval_expired du daemon : la demande a été auto-refusée
  // (timeout) — la carte passe en lecture seule.
  final bool isExpired;

  const ToolApprovalCard({
    super.key,
    required this.request,
    required this.onDecision,
    this.isExpired = false,
  });

  @override
  State<ToolApprovalCard> createState() => _ToolApprovalCardState();
}

class _ToolApprovalCardState extends State<ToolApprovalCard> {
  bool _alwaysAllow = false;
  bool _isSubmitting = false;

  @override
  void didUpdateWidget(ToolApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.callId != widget.request.callId) {
      // Sécurité Critique (Scénario 6) : Réinitialiser l'état local si Flutter
      // recycle ce composant pour une NOUVELLE demande d'approbation.
      // Sans ça, une demande destructive pourrait hériter du `_alwaysAllow` = true
      // d'une précédente demande innocente !
      _isSubmitting = false;
      _alwaysAllow = false;
    }
  }

  void _handleDecision(ToolDecision decision) async {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);
    try {
      await widget.onDecision(
        decision,
        scope: _alwaysAllow ? ApprovalScope.session : ApprovalScope.once,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutExpo,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isExpired
              ? AppColors.danger.withValues(alpha: 0.7)
              : _isSubmitting
                  ? AppColors.positive.withValues(alpha: 0.5)
                  : AppColors.warning,
          width: 1.5,
        ),
        boxShadow: _isSubmitting
            ? [BoxShadow(color: AppColors.positive.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 1)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security, size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      'APPROVAL REQUIRED (${request.toolName})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Command Box
          Text(
            'Command to execute:',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Text(
              request.command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // "Always allow for this session"
          Row(
            children: [
              const Icon(Icons.autorenew, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Toujours autoriser ${request.toolName} pour cette session',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                value: _alwaysAllow,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() => _alwaysAllow = v);
                },
                activeColor: AppColors.warning,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // État expiré : le daemon a auto-refusé (timeout) — bandeau rouge.
          if (widget.isExpired) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.timer_off_outlined, size: 14, color: AppColors.danger),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Approbation expirée — auto-refusée par le daemon (5 min)',
                      style: TextStyle(fontSize: 11.5, color: AppColors.danger, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Actions Buttons (Approuver / Refuser)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isSubmitting || widget.isExpired
                          ? null
                          : () => _handleDecision(ToolDecision.deny),
                  icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
                  label: const Text(
                    'Refuser',
                    style: TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting || widget.isExpired
                      ? null
                      : () => _handleDecision(ToolDecision.allow),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, size: 16, color: Colors.white),
                  label: Text(
                    _isSubmitting ? 'En cours...' : 'Approuver',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.positive,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
