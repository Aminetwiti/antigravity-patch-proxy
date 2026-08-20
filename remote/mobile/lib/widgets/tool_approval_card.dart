import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/messages.dart';
import '../theme/app_colors.dart';
import 'app_toast.dart';

class ToolApprovalCard extends StatefulWidget {
  final ToolApprovalRequest request;
  final Function(
    ToolDecision decision, {
    ApprovalScope scope,
    String denyReason,
  }) onDecision;
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
  bool _showDenyReason = false;
  int _selectedOption = 1; // 1 = once, 2 = conversation, 3 = project, 4 = global, 5 = deny
  bool _isSubmitting = false;
  // Guard timeout : si le daemon ne répond pas en 5 s, on débloque le bouton.
  Timer? _submitTimeout;
  final TextEditingController _denyReasonController = TextEditingController();

  bool get _isUrlApproval {
    final lowerTool = widget.request.toolName.toLowerCase();
    final lowerType = widget.request.approvalType.toLowerCase();
    return lowerTool.contains('url') ||
        lowerTool == 'browse' ||
        lowerTool == 'open_browser_url' ||
        lowerTool == 'read_url_content' ||
        lowerType.contains('url') ||
        lowerType == 'browse' ||
        lowerType == 'open_browser_url' ||
        widget.request.url != null;
  }

  String _extractTargetDisplay(String raw) {
    if (raw.isEmpty) return widget.request.description;
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.host.isNotEmpty) {
        return uri.host;
      }
    }
    return trimmed.replaceAll(r'\n', '\n');
  }

  IconData _iconForTool(String toolName) {
    if (_isUrlApproval) return Icons.lock_outline;
    final lower = toolName.toLowerCase();
    if (lower.contains('bash') || lower.contains('command') || lower.contains('run')) {
      return Icons.terminal;
    } else if (lower.contains('file') || lower.contains('read') || lower.contains('write')) {
      return Icons.folder_outlined;
    } else if (lower.contains('browser') || lower.contains('web') || lower.contains('search')) {
      return Icons.language;
    }
    return Icons.security_outlined;
  }

  String _titleForTool() {
    if (_isUrlApproval) {
      return 'Allow reading this URL?';
    }
    final lower = widget.request.toolName.toLowerCase();
    if (lower.contains('run') || lower.contains('command')) {
      return 'Allow executing this command?';
    }
    if (lower.contains('file') || lower.contains('write')) {
      return 'Allow file modification?';
    }
    return 'Allow executing ${widget.request.toolName}?';
  }

  @override
  void didUpdateWidget(ToolApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.callId != widget.request.callId) {
      _isSubmitting = false;
      _selectedOption = 1;
      _alwaysAllow = false;
      _showDenyReason = false;
      _denyReasonController.clear();
      _submitTimeout?.cancel();
    }
  }

  void _handleDecision(ToolDecision decision, {ApprovalScope scope = ApprovalScope.once, String denyReason = ''}) async {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);
    _submitTimeout?.cancel();
    _submitTimeout = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.show(
          context,
          message: 'Le serveur n\'a pas répondu. Veuillez réessayer.',
          type: ToastType.error,
        );
      }
    });
    try {
      await widget.onDecision(
        decision,
        scope: scope,
        denyReason: denyReason,
      );
    } finally {
      _submitTimeout?.cancel();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleSubmitSelected() {
    if (_isSubmitting || widget.isExpired) return;
    if (_isUrlApproval) {
      switch (_selectedOption) {
        case 1:
          _handleDecision(ToolDecision.allow, scope: ApprovalScope.once);
          break;
        case 2:
          _handleDecision(ToolDecision.allow, scope: ApprovalScope.session);
          break;
        case 3:
          _handleDecision(ToolDecision.allow, scope: ApprovalScope.project);
          break;
        case 4:
          _handleDecision(ToolDecision.allow, scope: ApprovalScope.global);
          break;
        case 5:
          _handleDecision(
            ToolDecision.deny,
            denyReason: _denyReasonController.text.trim(),
          );
          break;
        default:
          _handleDecision(ToolDecision.allow, scope: ApprovalScope.once);
      }
    } else {
      _handleDecision(
        ToolDecision.allow,
        scope: _alwaysAllow ? ApprovalScope.session : ApprovalScope.once,
      );
    }
  }

  @override
  void dispose() {
    _submitTimeout?.cancel();
    _denyReasonController.dispose();
    super.dispose();
  }

  Widget _buildOptionRow({
    required int index,
    required String label,
    required ColorScheme scheme,
  }) {
    final isSelected = _selectedOption == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          key: Key('approval-option-$index'),
          onTap: widget.isExpired || _isSubmitting
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedOption = index);
                },
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? AppColors.accentBlue.withValues(alpha: 0.15)
                      : scheme.primaryContainer.withValues(alpha: 0.4))
                  : (isDark ? AppColors.surfaceRaised : scheme.surfaceContainerHighest.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? (isDark ? AppColors.accentBlueBright : scheme.primary)
                    : (isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.4)),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Numéro badge
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? AppColors.accentBlue : scheme.primary)
                        : (isDark ? AppColors.surfaceHover : scheme.surfaceContainerHighest),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : (isDark ? AppColors.inkMuted : scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Libellé de l'option
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? (isDark ? AppColors.inkPrimary : scheme.onSurface)
                          : (isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                // Indicateur Radio
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected
                      ? (isDark ? AppColors.accentBlueBright : scheme.primary)
                      : (isDark ? AppColors.inkMuted.withValues(alpha: 0.5) : scheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetDisplay = _extractTargetDisplay(request.url ?? request.command);

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isExpired
                ? scheme.error.withValues(alpha: 0.7)
                : _isSubmitting
                    ? (isDark ? AppColors.accentBlue : scheme.primary)
                    : (isDark ? AppColors.borderStrong : scheme.outlineVariant),
            width: 1.5,
          ),
          boxShadow: _isSubmitting
              ? [
                  BoxShadow(
                    color: (isDark ? AppColors.accentBlue : scheme.primary).withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête : Cadenas / Outil + Titre
            Row(
              children: [
                Icon(
                  _iconForTool(request.toolName),
                  size: 16,
                  color: _isUrlApproval
                      ? (isDark ? AppColors.accentBlueBright : scheme.primary)
                      : (isDark ? AppColors.warning : scheme.tertiary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _titleForTool(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Cible : Encadré Domaine / URL / Commande
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
                ),
              ),
              child: SelectableText(
                targetDisplay,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Choix d'approbation (5 options si URL, switch si Commande standard)
            if (_isUrlApproval) ...[
              _buildOptionRow(
                index: 1,
                label: 'Yes, allow this time',
                scheme: scheme,
              ),
              _buildOptionRow(
                index: 2,
                label: 'Yes, and always allow in this conversation',
                scheme: scheme,
              ),
              _buildOptionRow(
                index: 3,
                label: 'Yes, and always allow in this project',
                scheme: scheme,
              ),
              _buildOptionRow(
                index: 4,
                label: 'Yes, and always allow',
                scheme: scheme,
              ),
              _buildOptionRow(
                index: 5,
                label: 'No (tell the agent what to do instead)',
                scheme: scheme,
              ),

              // Champ d'instruction si option 5
              if (_selectedOption == 5) ...[
                const SizedBox(height: 6),
                TextField(
                  key: const Key('deny-reason-field'),
                  controller: _denyReasonController,
                  maxLines: 2,
                  minLines: 1,
                  autofocus: true,
                  enabled: !_isSubmitting && !widget.isExpired,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tell the agent what to do instead (optional)',
                    hintText: 'e.g.: Analyze the design language without downloading scripts',
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.reply_outlined,
                      size: 16,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.accentBlue : scheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSubmitSelected(),
                ),
              ],
            ] else ...[
              // Switch standard "Toujours autoriser pour cette session"
              Row(
                children: [
                  Icon(Icons.autorenew, size: 14, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Toujours autoriser ${request.toolName} pour cette session',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
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
                      activeColor: scheme.tertiary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              if (_showDenyReason) ...[
                const SizedBox(height: 6),
                TextField(
                  key: const Key('deny-reason-field'),
                  controller: _denyReasonController,
                  maxLines: 2,
                  minLines: 1,
                  autofocus: true,
                  enabled: !_isSubmitting && !widget.isExpired,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: "Expliquer à l'agent (optionnel)",
                    hintText: 'Ex. : fais un revert d\u2019abord, puis réessaie',
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.reply_outlined,
                      size: 16,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleDecision(
                    ToolDecision.deny,
                    denyReason: _denyReasonController.text.trim(),
                  ),
                ),
              ],
            ],

            // ── Bandeau Expiré
            if (widget.isExpired) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_off_outlined, size: 15, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Approbation expirée — auto-refusée par le daemon (5 min)',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ── Boutons d'action : Refuser & Approuver
            Row(
              children: [
                // Bouton Refuser
                OutlinedButton(
                  key: const Key('deny-btn'),
                  onPressed: _isSubmitting || widget.isExpired
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          if (!_isUrlApproval && !_showDenyReason) {
                            // Premier clic sur une commande standard : afficher champ d'instruction
                            setState(() => _showDenyReason = true);
                          } else {
                            _handleDecision(
                              ToolDecision.deny,
                              denyReason: _denyReasonController.text.trim(),
                            );
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? AppColors.borderStrong : scheme.outlineVariant,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Refuser',
                    style: TextStyle(
                      color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Bouton Approuver / Submit
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('allow-btn'),
                    onPressed: _isSubmitting || widget.isExpired
                        ? null
                        : _handleSubmitSelected,
                    icon: _isSubmitting
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? AppColors.onAccent : scheme.onPrimary,
                            ),
                          )
                        : Icon(
                            (_isUrlApproval && _selectedOption == 5) ? Icons.close : Icons.keyboard_return,
                            size: 15,
                            color: isDark ? AppColors.onAccent : scheme.onPrimary,
                          ),
                    label: Text(
                      _isSubmitting
                          ? 'En cours...'
                          : ((_isUrlApproval && _selectedOption == 5) ? 'Refuser' : 'Approuver'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.onAccent : scheme.onPrimary,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_isUrlApproval && _selectedOption == 5)
                          ? (isDark ? AppColors.danger : scheme.error)
                          : (isDark ? AppColors.accentBlue : scheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
              child: Semantics(
                button: true,
                selected: isSelected,
                label: opt,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedOption = opt);
                  },
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
