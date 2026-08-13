import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modes d'envoi : immédiat ou mis en file pour exécution séquentielle.
enum SendMode { immediate, queued }

class ChatInputBar extends StatefulWidget {
  final Function(String message, {bool queued}) onSend;
  final bool isConnected;
  /// Feature queue : true si l'agent a un travail actif.
  final bool hasActiveStream;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isConnected = true,
    this.hasActiveStream = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final String _selectedModel = 'Gemini 3.1 Pro High';

  bool _isSendPressed = false;
  SendMode _sendMode = SendMode.immediate;
  // Feature Niveaux d'effort de raisonnement (Faible, Moyen, Élevé)
  String _reasoningEffort = 'Moyen'; // Options: 'Faible', 'Moyen', 'Élevé'
  // Feature attachement .txt
  String? _attachedFileName;
  String? _attachedFileContent;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final hasContent = text.isNotEmpty || _attachedFileContent != null;
    if (!hasContent) return;

    HapticFeedback.lightImpact();

    // Préfixe le contenu du fichier attaché avant le texte utilisateur.
    final fullMessage = _attachedFileContent != null
        ? '${_attachedFileName != null ? "[Fichier: $_attachedFileName]\n" : ""}'
              '$_attachedFileContent\n\n$text'.trim()
        : text;

    widget.onSend(fullMessage, queued: _sendMode == SendMode.queued);
    _controller.clear();
    setState(() {
      _attachedFileName = null;
      _attachedFileContent = null;
    });
  }

  /// Shortcut Cmd+L / Ctrl+L : citer le texte sélectionné
  void _quoteSelectedText() {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final text = _controller.text;
      if (text.isNotEmpty) {
        _controller.text = '> $text';
      }
      return;
    }
    final selectedText = _controller.text.substring(selection.start, selection.end);
    final quoted = selectedText.split('\n').map((l) => '> $l').join('\n');
    final newText = _controller.text.replaceRange(selection.start, selection.end, quoted);
    _controller.text = newText;
  }

  Color _badgeColorForExtension(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'json':
        return Colors.amber.shade700;
      case 'md':
        return Colors.blue.shade600;
      case 'csv':
        return Colors.green.shade700;
      default:
        return Colors.purple.shade600;
    }
  }

  IconData _iconForExtension(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'json':
        return Icons.data_object;
      case 'md':
        return Icons.article_outlined;
      case 'csv':
        return Icons.table_chart_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  /// Feature attachement .txt, .json, .md, .csv
  Future<void> _pickTextFile() async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: 'data.json');
        final contentCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Joindre un fichier (.txt, .json, .md, .csv)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du fichier (ex: data.json, doc.md, export.csv)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Contenu',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop({
                'name': nameCtrl.text.trim(),
                'content': contentCtrl.text,
              }),
              child: const Text('Joindre'),
            ),
          ],
        );
      },
    );
    if (result != null && result['content']!.isNotEmpty) {
      setState(() {
        _attachedFileName = result['name']!.isEmpty ? 'fichier.txt' : result['name']!;
        _attachedFileContent = result['content'];
      });
    }
  }

  void _showQueueSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Mode d'envoi",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Configurer le comportement d'exécution des messages.",
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _QueueTile(
              title: 'Envoyer immédiatement',
              subtitle: "Le message part dès l'envoi.",
              icon: Icons.send_outlined,
              selected: _sendMode == SendMode.immediate,
              onTap: () {
                setState(() => _sendMode = SendMode.immediate);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
            _QueueTile(
              title: "Mettre en file d'attente",
              subtitle: 'Le message sera exécuté après la tâche en cours.',
              icon: Icons.playlist_add_outlined,
              selected: _sendMode == SendMode.queued,
              onTap: () {
                setState(() => _sendMode = SendMode.queued);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 16),
            Text(
              "Effort de raisonnement par modèle",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: ['Faible', 'Moyen', 'Élevé'].map((effort) {
                final selected = _reasoningEffort == effort;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(effort),
                      selected: selected,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _reasoningEffort = effort);
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isQueued = _sendMode == SendMode.queued;

    return Container(
      margin: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: isQueued
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.5))
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge fichier attaché avec icône & couleur spécifiques à l'extension
                if (_attachedFileName != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _badgeColorForExtension(_attachedFileName!).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _badgeColorForExtension(_attachedFileName!).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconForExtension(_attachedFileName!),
                          size: 14,
                          color: _badgeColorForExtension(_attachedFileName!),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _attachedFileName!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() {
                            _attachedFileName = null;
                            _attachedFileContent = null;
                          }),
                          child: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                // Badge mode queue + "Envoyer maintenant"
                if (isQueued)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.playlist_add_check_outlined, size: 13, color: scheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          "En file d'attente",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // "Envoyer maintenant" — bypass la queue
                        InkWell(
                          onTap: () {
                            setState(() => _sendMode = SendMode.immediate);
                            _handleSend();
                          },
                          child: Text(
                            'Envoyer maintenant',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input TextField avec raccourci Cmd+L / Ctrl+L (autofocus: false pour éviter l'ouverture du clavier au chargement)
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.keyL, control: true): _quoteSelectedText,
                    const SingleActivator(LogicalKeyboardKey.keyL, meta: true): _quoteSelectedText,
                  },
                  child: TextField(
                    controller: _controller,
                    autofocus: false,
                    maxLines: 6,
                    minLines: 1,
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    decoration: InputDecoration(
                      hintText: widget.isConnected
                          ? (isQueued
                              ? "Message en file — sera exécuté après la tâche en cours"
                              : 'Ask anything, @ to mention, / for actions (Cmd+L pour citer)')
                          : 'Hors ligne — le message sera envoyé à la reconnexion',
                      hintStyle: TextStyle(
                        color: widget.isConnected ? Colors.grey : scheme.error,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      fillColor: Colors.transparent,
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Bottom Action Bar
                Row(
                  children: [
                    // Attach .txt
                    InkWell(
                      onTap: _pickTextFile,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Model & Reasoning Effort Pill
                    InkWell(
                      onTap: () => _showQueueSettings(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              isQueued
                                  ? Icons.playlist_add_check_outlined
                                  : Icons.psychology_outlined,
                              size: 15,
                              color: isQueued ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_selectedModel ($_reasoningEffort)',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down, size: 16, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Voice
                    IconButton(
                      icon: Icon(Icons.mic_none, size: 20, color: scheme.onSurfaceVariant),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),

                    // Send button
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isSendPressed = true),
                      onTapUp: (_) {
                        setState(() => _isSendPressed = false);
                        _handleSend();
                      },
                      onTapCancel: () => setState(() => _isSendPressed = false),
                      child: AnimatedScale(
                        scale: _isSendPressed ? 0.85 : 1.0,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOutQuart,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: widget.isConnected
                                  ? scheme.surfaceContainer
                                  : scheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isQueued ? Icons.playlist_add_check : Icons.arrow_forward,
                              size: 16,
                              color: widget.isConnected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Footer
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monitor_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('Local', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Main Agent', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: scheme.onSurfaceVariant),
                    ],
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

/// Tile de sélection du mode d'envoi dans le bottom sheet.
class _QueueTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _QueueTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}



