import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/protocol/daemon_api.dart';

/// Boîte de dialogue pour créer un commit Git avec génération automatique par IA.
class GitCommitDialog extends StatefulWidget {
  final DaemonApi? api;
  final String workspacePath;
  final ValueChanged<String>? onCommitted;

  const GitCommitDialog({
    super.key,
    required this.api,
    this.workspacePath = '.',
    this.onCommitted,
  });

  static Future<String?> show(
    BuildContext context, {
    required DaemonApi? api,
    String workspacePath = '.',
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => GitCommitDialog(
        api: api,
        workspacePath: workspacePath,
        onCommitted: (msg) => Navigator.of(ctx).pop(msg),
      ),
    );
  }

  @override
  State<GitCommitDialog> createState() => _GitCommitDialogState();
}

class _GitCommitDialogState extends State<GitCommitDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isGenerating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generateMessage() async {
    if (widget.api == null) return;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    HapticFeedback.selectionClick();

    try {
      final msg = await widget.api!.generateCommitMessage();
      if (!mounted) return;
      if (msg.isNotEmpty) {
        setState(() {
          _controller.text = msg;
          _isGenerating = false;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _errorMessage = 'Aucune modification indexée ou message vide.';
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _isGenerating = false;
      });
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.mediumImpact();
    widget.onCommitted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant, width: 0.8),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Icon(Icons.commit_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Créer un commit Git',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Message de commit conventionnel :',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              autofocus: true,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: scheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'feat: ajouter la nouvelle fonctionnalité...',
                hintStyle: TextStyle(fontSize: 12, color: scheme.outline),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _generateMessage,
                  icon: _isGenerating
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: Text(
                    _isGenerating ? 'Génération IA...' : 'Générer avec l\'IA',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(fontSize: 11, color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Valider le Commit'),
        ),
      ],
    );
  }
}
