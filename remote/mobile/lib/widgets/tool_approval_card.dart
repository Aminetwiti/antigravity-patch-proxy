import 'package:flutter/material.dart';
import '../core/protocol/messages.dart';
import '../theme/app_colors.dart';

class ToolApprovalCard extends StatefulWidget {
  final ToolApprovalRequest request;
  final Function(ToolDecision decision, {ApprovalScope scope}) onDecision;

  const ToolApprovalCard({
    super.key,
    required this.request,
    required this.onDecision,
  });

  @override
  State<ToolApprovalCard> createState() => _ToolApprovalCardState();
}

class _ToolApprovalCardState extends State<ToolApprovalCard> {
  bool _alwaysAllow = false;
  bool _isSubmitting = false;

  void _handleDecision(ToolDecision decision) async {
    if (_isSubmitting) return;
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning, width: 1.5),
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
                onChanged: (v) => setState(() => _alwaysAllow = v),
                activeColor: AppColors.warning,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Actions Buttons (Approuver / Refuser)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : () => _handleDecision(ToolDecision.deny),
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
                  onPressed: _isSubmitting ? null : () => _handleDecision(ToolDecision.allow),
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
