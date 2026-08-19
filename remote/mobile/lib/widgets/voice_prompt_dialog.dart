import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/code_speech_formatter.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Dialogue de saisie vocale et de formatage intelligent de code.
/// Permet la dictée vocale / saisie assistée avec formatage automatique
/// des commandes, chemins de fichiers et identifiants techniques entre backticks.
class VoicePromptDialog extends StatefulWidget {
  final ValueChanged<String> onInsert;

  const VoicePromptDialog({super.key, required this.onInsert});

  static Future<void> show(BuildContext context, {required ValueChanged<String> onInsert}) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => VoicePromptDialog(onInsert: onInsert),
    );
  }

  @override
  State<VoicePromptDialog> createState() => _VoicePromptDialogState();
}

class _VoicePromptDialogState extends State<VoicePromptDialog> with SingleTickerProviderStateMixin {
  final TextEditingController _voiceTextController = TextEditingController();
  late AnimationController _pulseController;
  bool _isListening = false;
  String _formattedPreview = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _voiceTextController.addListener(() {
      final formatted = CodeSpeechFormatter.format(_voiceTextController.text);
      setState(() {
        _formattedPreview = formatted;
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _voiceTextController.dispose();
    super.dispose();
  }

  void _applyQuickTemplate(String text) {
    HapticFeedback.selectionClick();
    _voiceTextController.text = text;
  }

  void _confirmInsert() {
    final finalContent = _formattedPreview.isNotEmpty
        ? _formattedPreview
        : _voiceTextController.text.trim();
    if (finalContent.isNotEmpty) {
      HapticFeedback.mediumImpact();
      widget.onInsert(finalContent);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: viewInsets + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saisie Vocale & Formatage Code',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'Formate automatiquement les fichiers, commandes et camelCase',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Speech Input Field
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _isListening
                    ? AppColors.accent
                    : (isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
                width: _isListening ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _voiceTextController,
                  maxLines: 4,
                  minLines: 2,
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Dictez ou tapez votre consigne technique…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    border: InputBorder.none,
                  ),
                ),
                if (_formattedPreview.isNotEmpty &&
                    _formattedPreview != _voiceTextController.text) ...[
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 13, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Aperçu formaté :',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formattedPreview,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick prompt presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickChip('Exécute npm test et commit les changements'),
                const SizedBox(width: 8),
                _buildQuickChip('Analyse le fichier main.dart et corrige les warnings'),
                const SizedBox(width: 8),
                _buildQuickChip('Appelle getSessionHistory() pour vérifier l\'état'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bottom Action Buttons
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isListening = !_isListening;
                  });
                  HapticFeedback.lightImpact();
                },
                icon: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Icon(
                      _isListening ? Icons.graphic_eq : Icons.mic,
                      size: 16,
                      color: _isListening
                          ? AppColors.accent.withValues(alpha: 0.6 + 0.4 * _pulseController.value)
                          : scheme.onSurfaceVariant,
                    );
                  },
                ),
                label: Text(_isListening ? 'Écoute active…' : 'Dictée'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _confirmInsert,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Insérer dans le prompt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String text) {
    return ActionChip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 11.5),
      ),
      onPressed: () => _applyQuickTemplate(text),
    );
  }
}
