import 'dart:async';

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
  // Bug #13 : guard timeout — si le daemon ne répond pas en 5 s, on débloque
  // le bouton pour ne pas laisser l'utilisateur coincé.
  Timer? _submitTimeout;

  /// Détecte les commandes de lecture courantes pour réduire les demandes redondantes.
  bool _isReadCommand(String cmd) {
    final trimmed = cmd.trim().toLowerCase();
    return trimmed.startsWith('cat ') ||
        trimmed.startsWith('ls ') ||
        trimmed.startsWith('grep ') ||
        trimmed.startsWith('pwd') ||
        trimmed.startsWith('git status') ||
        trimmed.startsWith('git diff');
  }

  IconData _iconForTool(String toolName) {
    final lower = toolName.toLowerCase();
    if (lower.contains('bash') || lower.contains('command') || lower.contains('run')) {
      return Icons.terminal;
    } else if (lower.contains('file') || lower.contains('read') || lower.contains('write')) {
      return Icons.folder_outlined;
    } else if (lower.contains('browser') || lower.contains('web') || lower.contains('search')) {
      return Icons.language;
    }
    return Icons.build_outlined;
  }

  @override
  void didUpdateWidget(ToolApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.callId != widget.request.callId) {
      _isSubmitting = false;
      _alwaysAllow = _isReadCommand(widget.request.command);
      _submitTimeout?.cancel();
    }
  }

  void _handleDecision(ToolDecision decision) async {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);
    // Bug #13 : timeout guard — débloque après 5 s si pas de réponse daemon.
    _submitTimeout?.cancel();
    _submitTimeout = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isSubmitting = false);
    });
    try {
      await widget.onDecision(
        decision,
        scope: _alwaysAllow ? ApprovalScope.session : ApprovalScope.once,
      );
    } finally {
      _submitTimeout?.cancel();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _submitTimeout?.cancel();
    super.dispose();
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
          // Header Badge avec icône d'outil dédiée
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
                    Icon(_iconForTool(request.toolName), size: 14, color: AppColors.warning),
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
          // Bug #1 : SelectableText → sélection/copie directe sans bouton.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: SelectableText(
              request.command.replaceAll('\\n', '\n'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // "Always allow for this session" — Bug #13 : tooltip explicatif.
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
              Tooltip(
                message:
                    'Si activé, le daemon approuvera automatiquement\n'
                    'toutes les commandes "${request.toolName}" pour\n'
                    'cette session sans vous redemander.',
                child: Switch(
                  value: _alwaysAllow,
                  onChanged: (v) {
                    HapticFeedback.lightImpact();
                    setState(() => _alwaysAllow = v);
                  },
                  activeColor: AppColors.warning,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
                    // Bug #13 : fontWeight.w700 pour contraste suffisant sur fond danger 12%.
                    child: Text(
                      'Approbation expirée — auto-refusée par le daemon (5 min)',
                      style: TextStyle(fontSize: 11.5, color: AppColors.danger, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Actions Buttons (Approuver / Refuser) — Adaptive Layout
          LayoutBuilder(
            builder: (context, constraints) {
              final denyBtn = Semantics(
                label: 'Refuser l\'exécution de ${request.toolName}',
                button: true,
                child: OutlinedButton.icon(
                  key: const Key('deny-btn'),
                  onPressed: _isSubmitting || widget.isExpired
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
              );

              final allowBtn = Semantics(
                label: 'Approuver l\'exécution de ${request.toolName}',
                button: true,
                child: ElevatedButton.icon(
                  key: const Key('allow-btn'),
                  onPressed: _isSubmitting || widget.isExpired
                      ? null
                      : () => _handleDecision(ToolDecision.allow),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkPrimary),
                        )
                      : const Icon(Icons.check, size: 16, color: AppColors.inkPrimary),
                  label: Text(
                    _isSubmitting ? 'En cours...' : 'Approuver',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.positive,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              );

              if (constraints.maxWidth < 280) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    allowBtn,
                    const SizedBox(height: 8),
                    denyBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: denyBtn),
                  const SizedBox(width: 12),
                  Expanded(child: allowBtn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Modal "Poser une question" : sélection d'option claire + bouton "Continuer" désactivé tant qu'aucune option n'est choisie.
class AskQuestionModal extends StatefulWidget {
  final String question;
  final List<String> options;
  final Function(String selectedOption) onSubmit;

  const AskQuestionModal({
    super.key,
    required this.question,
    required this.options,
    required this.onSubmit,
  });

  @override
  State<AskQuestionModal> createState() => _AskQuestionModalState();
}

class _AskQuestionModalState extends State<AskQuestionModal> {
  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.question,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          ...widget.options.map((opt) {
            final isSelected = _selectedOption == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedOption = opt),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedOption == null
                  ? null
                  : () {
                      widget.onSubmit(_selectedOption!);
                      Navigator.of(context).pop();
                    },
              child: const Text('Continuer'),
            ),
          ),
        ],
      ),
    );
  }
}
