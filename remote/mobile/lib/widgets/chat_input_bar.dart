import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/protocol/daemon_api.dart';
import '../core/protocol/model_catalog.dart';
import '../services/settings_store.dart';
import '../features/chat_stream/models/mention_item.dart';
import '../features/chat_stream/widgets/action_pills_bar.dart';
import '../features/chat_stream/widgets/mention_autocomplete_overlay.dart';
import 'custom_dropdown_overlay.dart';
import '../theme/app_colors.dart';

/// Modes d'envoi : immédiat ou mis en file pour exécution séquentielle.
enum SendMode { immediate, queued }

/// Entrée de la palette de commandes slash (/btw, /plan, ...).
class _SlashCommand {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SlashCommand(this.icon, this.title, this.subtitle);
}

/// Registre unique des commandes slash — filtré en tapant (P2).
const List<_SlashCommand> _slashCommands = [
  _SlashCommand(Icons.chat_bubble_outline_rounded, '/btw', 'Side question without breaking flow'),
  _SlashCommand(Icons.quiz_outlined, '/grill-me', 'Interactive planning interview'),
  _SlashCommand(Icons.flag_outlined, '/goal', 'Autonomous goal until fully achieved'),
  _SlashCommand(Icons.schedule_outlined, '/schedule', 'Set recurring timer / background cron'),
  _SlashCommand(Icons.rate_review_outlined, '/review', 'Audit code diffs and complexity'),
  _SlashCommand(Icons.edit_note_rounded, '/plan', 'Draft technical implementation plan'),
  _SlashCommand(Icons.design_services, '/design', 'Generate UI components & screens'),
  _SlashCommand(Icons.code, '/code', 'Generate Code Implementation'),
  _SlashCommand(Icons.search, '/search', 'Semantic project search'),
];

class ChatInputBar extends StatefulWidget {
  /// Signature unique : message + mode file + modèle sélectionné.
  /// C2 (audit clean-code-guard) : typée — plus de `Function` opaque ni de
  /// try/catch en cascade côté appelant.
  final void Function(
    String message, {
    bool queued,
    String? modelUID,
    int? modelEnum,
  }) onSend;
  final bool isConnected;

  /// Feature queue : true si l'agent a un travail actif.
  final bool hasActiveStream;

  final DaemonApi? api;
  final String? cascadeId;
  final ValueChanged<String>? onModelChanged;
  final VoidCallback? onStop;

  /// P6 : texte initial (brouillon persisté) à charger dans le champ.
  final String initialText;

  /// P6 : notifie le parent de chaque frappe pour persister le brouillon.
  final ValueChanged<String>? onDraftChanged;

  /// Nom du projet / workspace actif affiché au-dessus de la barre
  final String? projectName;
  final VoidCallback? onSelectProject;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isConnected = true,
    this.hasActiveStream = false,
    this.api,
    this.cascadeId,
    this.onModelChanged,
    this.onStop,
    this.initialText = '',
    this.onDraftChanged,
    this.projectName,
    this.onSelectProject,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  String _selectedModel = 'Gemini 3.7 Flash';
  String? _selectedModelId = 'gemini-3.7-flash';
  int? _selectedModelEnum = 312;
  List<AntigravityModel> _availableModels = ModelCatalog.standardModels;

  bool _isSendPressed = false;
  SendMode _sendMode = SendMode.immediate;
  // Feature Niveaux d'effort de raisonnement (Faible, Moyen, Élevé)
  String _reasoningEffort = 'Moyen'; // Options: 'Faible', 'Moyen', 'Élevé'
  // Feature attachement .txt
  String? _attachedFileName;
  String? _attachedFileContent;

  final GlobalKey _modelButtonKey = GlobalKey();
  final GlobalKey _textFieldKey = GlobalKey();

  // Quel dropdown est actuellement ouvert (si ouvert via le clavier).
  // Permet de fermer mention/action à la frappe sans toucher au dropdown
  // modèle (ouvert au tap, pas au clavier).
  bool _mentionOrActionOpen = false;
  bool _isSending = false;
  Timer? _sendDebounceTimer;
  String _lastDraftText = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialText.isNotEmpty) {
      // P6 : restaure le brouillon persisté avant d'écouter les frappes.
      _controller.text = widget.initialText;
      _lastDraftText = widget.initialText;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    _controller.addListener(_onTextChanged);
    widget.onDraftChanged?.call(_controller.text);
    _loadModelsAndPreferences();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText && widget.initialText != _controller.text) {
      _controller.text = widget.initialText;
      _lastDraftText = widget.initialText;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    if (oldWidget.api != widget.api || oldWidget.isConnected != widget.isConnected) {
      _loadModelsAndPreferences();
    }
  }

  Future<void> _loadModelsAndPreferences() async {
    List<AntigravityModel> models = _availableModels;
    if (widget.api != null) {
      try {
        final fetched = await ModelCatalog.getAllAvailableModels(widget.api);
        if (fetched.isNotEmpty) {
          models = fetched;
          if (mounted) {
            setState(() {
              _availableModels = models;
            });
          }
        }
      } catch (_) {}
    }

    try {
      final s = await SettingsStore.load();
      final savedModel = s['defaultModel'] as String?;
      if (savedModel != null && savedModel.isNotEmpty && mounted) {
        final matched = ModelCatalog.findModel(savedModel, customModels: models);
        setState(() {
          _selectedModel = matched.shortName;
          _selectedModelId = matched.id;
          _selectedModelEnum = matched.modelEnum;
        });
      }
    } catch (_) {}
  }

  void _onTextChanged() {
    final text = _controller.text;
    // P6 : notifier le parent uniquement si le contenu textuel a réellement changé
    // (évite d'écrire sur disque à chaque déplacement de curseur ou sélection).
    if (text != _lastDraftText) {
      _lastDraftText = text;
      widget.onDraftChanged?.call(text);
      if (mounted) setState(() {});
    }

    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed == false) {
      return;
    }
    final textBeforeCursor = text.substring(0, selection.start);
    if (textBeforeCursor.endsWith('@') ||
        textBeforeCursor.contains(RegExp(r'\B@\w*$'))) {
      final atIndex = textBeforeCursor.lastIndexOf('@');
      final query = atIndex >= 0 ? textBeforeCursor.substring(atIndex + 1) : '';
      _showMentionDropdown(query);
    } else if (textBeforeCursor.startsWith('/') ||
        textBeforeCursor.contains(RegExp(r'\n/\w*$'))) {
      // P2 : extraire le début de commande tapé pour filtrer la palette.
      final slashIndex = textBeforeCursor.lastIndexOf('/');
      final query =
          slashIndex >= 0 ? textBeforeCursor.substring(slashIndex + 1) : '';
      _showActionDropdown(query);
    } else {
      // On tape autre chose : fermer les dropdowns mention/action restés
      // ouverts (le dropdown modèle, ouvert au tap, n'est pas concerné).
      if (_mentionOrActionOpen) {
        _mentionOrActionOpen = false;
        CustomDropdownOverlay.hide();
      }
    }
  }

  @override
  void dispose() {
    _sendDebounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _sanitizeInput(String raw) {
    // Supprime les lignes vides en trop lors du collage de texte brut multi-lignes
    return raw.replaceAll(RegExp(r'(\r?\n){3,}'), '\n\n').trim();
  }

  void _handleSend() {
    if (_isSending) return;
    final rawText = _controller.text;
    final text = _sanitizeInput(rawText);
    final hasContent = text.isNotEmpty || _attachedFileContent != null;
    if (!hasContent) return;

    _isSending = true;
    HapticFeedback.lightImpact();

    // Normaliser les commandes barriques avec saut de ligne \n ou tabulation \t
    String finalPayload = text;
    if (text.startsWith('/') && (text.contains('\n') || text.contains('\t'))) {
      final parts = text.split(RegExp(r'[\n\t]'));
      final cmd = parts.first.trim();
      final args = parts.sublist(1).join(' ').trim();
      finalPayload = '$cmd $args'.trim();
    }

    // Préfixe le contenu du fichier attaché avant le texte utilisateur.
    final fullMessage =
        _attachedFileContent != null
            ? '${_attachedFileName != null ? "[Fichier: $_attachedFileName]\n" : ""}'
                    '$_attachedFileContent\n\n$finalPayload'
                .trim()
            : finalPayload;

    // C2 : signature désormais unique et typée — l'ancien try/catch en cascade
    // (compat rétro) n'a plus de raison d'être.
    widget.onSend(
      fullMessage,
      queued: _sendMode == SendMode.queued || widget.hasActiveStream,
      modelUID: _selectedModelId,
      modelEnum: _selectedModelEnum,
    );
    _controller.clear();
    _lastDraftText = '';
    // P6 : le message a été envoyé → purge le brouillon persisté.
    widget.onDraftChanged?.call('');
    FocusScope.of(
      context,
    ).unfocus(); // Ferme le clavier sur mobile après l'envoi
    setState(() {
      _attachedFileName = null;
      _attachedFileContent = null;
    });

    _sendDebounceTimer?.cancel();
    _sendDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _isSending = false;
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
    final selectedText = _controller.text.substring(
      selection.start,
      selection.end,
    );
    final quoted = selectedText.split('\n').map((l) => '> $l').join('\n');
    final newText = _controller.text.replaceRange(
      selection.start,
      selection.end,
      quoted,
    );
    _controller.text = newText;
  }

  Color _badgeColorForExtension(String name, ColorScheme scheme) {
    if (name.endsWith('/') || !name.contains('.')) {
      return scheme.tertiary;
    }
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'json':
        return scheme.tertiary;
      case 'md':
        return scheme.primary;
      case 'csv':
        return scheme.secondary;
      default:
        return scheme.tertiary;
    }
  }

  IconData _iconForExtension(String name) {
    if (name.endsWith('/') || !name.contains('.')) return Icons.folder_outlined;
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
        final scheme = Theme.of(ctx).colorScheme;
        final nameCtrl = TextEditingController(text: 'data.json');
        final contentCtrl = TextEditingController();
        return AlertDialog(
          backgroundColor: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          title: Text(
            'Joindre un fichier (.txt, .json, .md, .csv)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Nom du fichier (ex: data.json, doc.md)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 6,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
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
              onPressed:
                  () => Navigator.of(ctx).pop({
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
        _attachedFileName =
            result['name']!.isEmpty ? 'fichier.txt' : result['name']!;
        _attachedFileContent = result['content'];
      });
    }
  }

  /// Feature attachement image/photo (Multimodal)
  Future<void> _pickImage() async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final nameCtrl = TextEditingController(text: 'screenshot.png');
        final mimeCtrl = TextEditingController(text: 'image/png');
        final base64Ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          title: Text(
            'Joindre une image / photo',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Nom du fichier (ex: photo.png, img.jpg)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mimeCtrl,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Type MIME (ex: image/png, image/jpeg)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: base64Ctrl,
                maxLines: 4,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Données Base64',
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
                'fileName': nameCtrl.text.trim().isEmpty ? 'screenshot.png' : nameCtrl.text.trim(),
                'mimeType': mimeCtrl.text.trim().isEmpty ? 'image/png' : mimeCtrl.text.trim(),
                'base64Data': base64Ctrl.text.trim(),
              }),
              child: const Text('Joindre'),
            ),
          ],
        );
      },
    );

    if (result != null && result['base64Data']!.isNotEmpty) {
      final fileName = result['fileName']!;
      final mimeType = result['mimeType']!;
      final base64Data = result['base64Data']!;

      if (widget.api != null && widget.cascadeId != null) {
        widget.api!.uploadMedia(
          cascadeId: widget.cascadeId!,
          fileName: fileName,
          mimeType: mimeType,
          base64Data: base64Data,
        );
      }

      setState(() {
        _attachedFileName = fileName;
        _attachedFileContent = '[Image: $fileName ($mimeType)]';
      });
    }
  }

  void _showAttachmentMenu() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image_outlined, color: scheme.primary),
                title: Text('Joindre une image / photo', style: TextStyle(color: scheme.onSurface)),
                subtitle: Text('PNG, JPEG, WebP, GIF', style: TextStyle(color: scheme.onSurfaceVariant)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.description_outlined, color: scheme.onSurface),
                title: Text('Joindre un fichier', style: TextStyle(color: scheme.onSurface)),
                subtitle: Text('.txt, .json, .md, .csv', style: TextStyle(color: scheme.onSurfaceVariant)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickTextFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                  children:
                      ['Faible', 'Moyen', 'Élevé'].map((effort) {
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

  void _insertTextAtCursor(String insertText) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid) {
      // find where the @ or / started
      int start = selection.start;
      while (start > 0 && text[start - 1] != '@' && text[start - 1] != '/') {
        start--;
      }
      if (start > 0) start--; // include the @ or /

      final newText = text.replaceRange(start, selection.end, '$insertText ');
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: start + insertText.length + 1,
      );
    } else {
      final prefix = text.isEmpty ? '' : '$text ';
      _controller.text = '$prefix$insertText ';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  void _showMentionDropdown([String query = '']) {
    _mentionOrActionOpen = true;
    final items = const [
      MentionItem(type: MentionType.file, label: 'main.dart', detail: 'lib/main.dart'),
      MentionItem(type: MentionType.file, label: 'pubspec.yaml', detail: 'Configuration & dependencies'),
      MentionItem(type: MentionType.file, label: 'README.md', detail: 'Project documentation'),
      MentionItem(type: MentionType.rule, label: 'clean_code', detail: '.agents/rules/clean_code.md'),
      MentionItem(type: MentionType.rule, label: 'ponytail', detail: 'Lazy senior dev / YAGNI architecture'),
      MentionItem(type: MentionType.rule, label: 'security', detail: 'Sandbox & security policies'),
      MentionItem(type: MentionType.mcp, label: 'coolify', detail: 'Coolify deploy & server management'),
      MentionItem(type: MentionType.mcp, label: 'github', detail: 'GitHub issues & PR automation'),
      MentionItem(type: MentionType.mcp, label: 'postgres', detail: 'PostgreSQL database inspection'),
      MentionItem(type: MentionType.conversation, label: 'previous_session', detail: 'Include previous turn context'),
      MentionItem(type: MentionType.terminal, label: 'active_terminal', detail: 'Include active terminal buffer'),
    ];

    CustomDropdownOverlay.show(
      context: context,
      targetKey: _textFieldKey,
      width: 280,
      maxHeight: 260,
      child: MentionAutocompleteOverlay(
        query: query,
        items: items,
        onSelected: (item) {
          _insertTextAtCursor(item.tag);
          CustomDropdownOverlay.hide();
        },
      ),
    );
  }

  void _showActionDropdown([String query = '']) {
    _mentionOrActionOpen = true;
    final q = query.toLowerCase();
    // P2 : filtre au fur et à mesure — '/pl' ne montre que /plan.
    final filtered = _slashCommands
        .where((c) => q.isEmpty || c.title.toLowerCase().contains(q))
        .toList();

    CustomDropdownOverlay.show(
      context: context,
      targetKey: _textFieldKey,
      width: 250,
      maxHeight: 200,
      child: Material(
        color: Colors.transparent,
        child: filtered.isEmpty
            ? _buildEmptySlashState(query)
            : ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'Slash Commands & Actions',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final c in filtered)
                    _buildPopupItem(
                      c.icon,
                      c.title,
                      c.subtitle,
                      () {
                        _insertTextAtCursor('${c.title} ');
                        CustomDropdownOverlay.hide();
                      },
                    ),
                ],
              ),
      ),
    );
  }

  /// État vide de la palette slash : aucune commande ne matche le début tapé.
  Widget _buildEmptySlashState(String query) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.search_off, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Aucune commande ne correspond à '/$query'",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title: $subtitle',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: (textTheme.bodySmall ?? const TextStyle(fontSize: 11)).copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showModelDropdown(BuildContext context) {
    _mentionOrActionOpen = false;
    _loadModelsAndPreferences();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final standard = _availableModels.where((m) => !m.isCustom).toList();
    final custom = _availableModels.where((m) => m.isCustom).toList();

    CustomDropdownOverlay.show(
      context: context,
      targetKey: _modelButtonKey,
      width: 290,
      maxHeight: 460,
      child: Material(
        color: Colors.transparent,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Model',
                style: (textTheme.labelSmall ?? const TextStyle(fontSize: 12)).copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            ...standard.map((m) => _buildModelRow(m)),
            if (custom.isNotEmpty) ...[
              Divider(color: scheme.outlineVariant, height: 1),
              ...custom.map((m) => _buildCustomModelRow(m)),
            ],
            Divider(color: scheme.outlineVariant, height: 1),
            _buildViewUsageRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildModelRow(AntigravityModel model) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _selectedModel.toLowerCase().contains(model.shortName.toLowerCase()) ||
        _selectedModel.toLowerCase() == model.displayName.toLowerCase();

    return Semantics(
      button: true,
      selected: isSelected,
      label: model.displayName,
      child: InkWell(
        onTap: () => _selectModel(model),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? scheme.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model.displayName,
                    style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                      color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (model.tag != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          model.tag!,
                          style: (textTheme.labelSmall ?? const TextStyle(fontSize: 10)).copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.info_outline, size: 10, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (isSelected)
                  Icon(Icons.check, size: 16, color: scheme.primary)
                else
                  Icon(Icons.chevron_right, size: 14, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomModelRow(AntigravityModel model) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _selectedModel.toLowerCase().contains(model.id.toLowerCase()) ||
        _selectedModel.toLowerCase().contains(model.displayName.toLowerCase());

    Color statusColor = scheme.primary;
    if (model.status == 'degraded') {
      statusColor = scheme.tertiary;
    } else if (model.status == 'offline') {
      statusColor = scheme.error;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: model.customLabel,
      child: InkWell(
        onTap: () => _selectModel(model),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? scheme.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    model.customLabel,
                    style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 12.5)).copyWith(
                      color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewUsageRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'View Usage',
      child: InkWell(
        onTap: () {
          CustomDropdownOverlay.hide();
          _showUsageLimitsDialog(context);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.query_stats_outlined, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'View Usage',
                    style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 14, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectModel(AntigravityModel model) async {
    HapticFeedback.selectionClick();
    final short = model.shortName;
    setState(() {
      _selectedModel = short;
      _selectedModelId = model.id;
      _selectedModelEnum = model.modelEnum;
    });
    CustomDropdownOverlay.hide();

    widget.onModelChanged?.call(model.displayName);

    // Persist choice in local settings
    await SettingsStore.save({'defaultModel': model.displayName});

    // Send /model command to daemon to synchronize active session model without conflict
    try {
      await widget.api?.sendCommand('/model ${model.id}');
    } catch (_) {}
  }

  void _showUsageLimitsDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => _UsageLimitsModal(api: widget.api),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isQueued = _sendMode == SendMode.queued;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final hasKeyboard = viewInsets.bottom > 0;

    return SafeArea(
      top: false,
      bottom: !hasKeyboard,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 2, 12, hasKeyboard ? 2 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.projectName != null && widget.projectName!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: hasKeyboard ? 3 : 6, left: 4),
                child: InkWell(
                  onTap: widget.onSelectProject,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1B1D22)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2C2F36)
                            : scheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_outlined, size: 14, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          widget.projectName!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(bottom: hasKeyboard ? 3 : 6),
              child: ActionPillsBar(
                onActionSelected: (cmd) {
                  _insertTextAtCursor(cmd);
                },
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: hasKeyboard ? 8 : 12,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isQueued
                      ? scheme.primary.withValues(alpha: 0.6)
                      : scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badge fichier attaché avec icône & couleur spécifiques à l'extension
                  if (_attachedFileName != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _badgeColorForExtension(
                          _attachedFileName!,
                          scheme,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _badgeColorForExtension(
                            _attachedFileName!,
                            scheme,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconForExtension(_attachedFileName!),
                            size: 14,
                            color: _badgeColorForExtension(
                              _attachedFileName!,
                              scheme,
                            ),
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
                          Semantics(
                            label: 'Supprimer le fichier attaché',
                            button: true,
                            child: InkWell(
                              onTap:
                                  () => setState(() {
                                    _attachedFileName = null;
                                    _attachedFileContent = null;
                                  }),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Badge mode queue + "Envoyer maintenant"
                  if (isQueued)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.playlist_add_check_outlined,
                            size: 13,
                            color: scheme.primary,
                          ),
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
                      const SingleActivator(
                            LogicalKeyboardKey.keyL,
                            control: true,
                          ):
                          _quoteSelectedText,
                      const SingleActivator(
                            LogicalKeyboardKey.keyL,
                            meta: true,
                          ):
                          _quoteSelectedText,
                    },
                    child: Container(
                      key: _textFieldKey,
                      child: TextField(
                        controller: _controller,
                        autofocus: false,
                        maxLines: 6,
                        minLines: 1,
                        style: TextStyle(fontSize: 14, color: scheme.onSurface),
                        decoration: InputDecoration(
                          hintText:
                              widget.isConnected
                                  ? (isQueued
                                      ? "Message en file — sera exécuté après la tâche en cours"
                                      : 'Poser une question, @ mentionner, / actions…')
                                  : 'Hors ligne — le message sera envoyé à la reconnexion',
                          hintStyle: TextStyle(
                            color:
                                widget.isConnected ? scheme.onSurfaceVariant : scheme.error,
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
                  ),
                  const SizedBox(height: 12),

                  // Bottom Action Bar
                  Row(
                    children: [
                      // Attach media/file
                      InkWell(
                        onTap: _showAttachmentMenu,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.add,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),

                      // Model & Reasoning Effort Pill
                      Flexible(
                        child: InkWell(
                          key: _modelButtonKey,
                          onTap: () => _showModelDropdown(context),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isQueued
                                      ? Icons.playlist_add_check_outlined
                                      : Icons.psychology_outlined,
                                  size: 15,
                                  color:
                                      isQueued
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '$_selectedModel ($_reasoningEffort)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Voice (placeholder — pas de backend audio : retour haptique
                      // et notification claire au lieu d'un contrôle silencieux)
                      IconButton(
                        icon: Icon(
                          Icons.mic_none,
                          size: 20,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Saisie vocale — bientôt disponible dans Antigravity Remote'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        tooltip: 'Saisie vocale — bientôt disponible',
                      ),
                      // If streaming and user has typed text, show both Stop and Queue/Send buttons
                      if (widget.hasActiveStream && _controller.text.trim().isNotEmpty) ...[
                        // Dedicated Stop button
                        IconButton(
                          key: const Key('stop-generation-button'),
                          icon: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: scheme.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.stop_rounded,
                              size: 16,
                              color: AppColors.onDanger,
                            ),
                          ),
                          tooltip: 'Arrêter la génération (Emergency Stop)',
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            widget.onStop?.call();
                          },
                        ),
                        const SizedBox(width: 4),
                      ],

                      // Primary action button (Send / Queue / Stop)
                      Semantics(
                        button: true,
                        label: widget.hasActiveStream && _controller.text.trim().isEmpty
                            ? 'Arrêter la génération'
                            : (isQueued || widget.hasActiveStream
                                ? 'Ajouter à la file d\'attente'
                                : 'Envoyer le message'),
                        child: Tooltip(
                          message: widget.hasActiveStream && _controller.text.trim().isEmpty
                              ? 'Arrêter la génération (Emergency Stop)'
                              : (widget.hasActiveStream || isQueued
                                  ? 'Ajouter à la file d\'attente'
                                  : 'Envoyer'),
                          child: GestureDetector(
                            key: widget.hasActiveStream && _controller.text.trim().isEmpty
                                ? const Key('stop-generation-button')
                                : const Key('send-message-button'),
                            onTapDown: (_) => setState(() => _isSendPressed = true),
                            onTapUp: (_) {
                              setState(() => _isSendPressed = false);
                              if (widget.hasActiveStream && _controller.text.trim().isEmpty) {
                                if (widget.onStop != null) {
                                  HapticFeedback.heavyImpact();
                                  widget.onStop!();
                                }
                              } else {
                                _handleSend();
                              }
                            },
                            onTapCancel:
                                () => setState(() => _isSendPressed = false),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              child: Center(
                                child: AnimatedScale(
                                  scale: _isSendPressed ? 0.85 : 1.0,
                                  duration: const Duration(milliseconds: 100),
                                  curve: Curves.easeOutQuart,
                                  child: GestureDetector(
                                    onLongPress: () => _showQueueSettings(context),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: widget.hasActiveStream && _controller.text.trim().isEmpty
                                            ? scheme.error
                                            : (_controller.text.trim().isNotEmpty &&
                                                    widget.isConnected
                                                ? scheme.primary
                                                : scheme.surfaceContainerHighest),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        (isQueued || (widget.hasActiveStream && _controller.text.trim().isNotEmpty))
                                            ? Icons.playlist_add_check
                                            : (widget.hasActiveStream && _controller.text.trim().isEmpty
                                                ? Icons.stop_rounded
                                                : Icons.arrow_forward),
                                        size: 15,
                                        color: (_controller.text.trim().isNotEmpty &&
                                                    widget.isConnected) ||
                                                (widget.hasActiveStream && _controller.text.trim().isEmpty)
                                            ? AppColors.onAccent
                                            : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                ),
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


          ],
        ),
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
          color:
              selected
                  ? scheme.primaryContainer.withValues(alpha: 0.4)
                  : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
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
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Antigravity 2.0 Quotas / Limits flyout sheet (matching the desktop IDE UI).
/// Charge le résumé des quotas réel via getUserQuotaSummary() dès l'ouverture
/// (dynamique) et retombe sur les valeurs statiques si le daemon est
/// injoignable ou ne renvoie pas de données exploitables.
class _UsageLimitsModal extends StatefulWidget {
  const _UsageLimitsModal({this.api});

  final DaemonApi? api;

  @override
  State<_UsageLimitsModal> createState() => _UsageLimitsModalState();
}

class _UsageLimitsModalState extends State<_UsageLimitsModal> {
  Map<String, dynamic>? _quota;
  String? _plan;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    final api = widget.api;
    if (api == null) return;
    // Run independently so a missing/slow getUserStatus doesn't block quota.
    api.getUserQuotaSummary().then((q) {
      if (!mounted || q.isEmpty) return;
      setState(() => _quota = q);
    }).catchError((_) {});
    api.getUserStatus().then((s) {
      if (!mounted) return;
      final user = s['user'];
      if (user is Map) {
        final plan = user['plan'];
        if (plan is String && plan.isNotEmpty) {
          setState(() => _plan = plan);
        }
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gemini Models',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (_plan != null) ...[
              const SizedBox(height: 2),
              Text(
                'Plan $_plan',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildUsageTile(
              context: context,
              title: 'Limite hebdomadaire restante',
              subtitle: 'Quota hebdomadaire disponible',
              percent: _quotaPercent('weeklyPercent'),
            ),
            const SizedBox(height: 10),
            _buildUsageTile(
              context: context,
              title: 'Limite sur 5 heures',
              subtitle: 'Quota sur fenêtre de 5 heures',
              percent: _quotaPercent('fiveHourPercent'),
            ),
            const SizedBox(height: 20),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 16),
            Text(
              'Claude and GPT models',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _buildUsageTile(
              context: context,
              title: 'Limite hebdomadaire restante',
              subtitle: 'Quota hebdomadaire disponible',
              percent: _quotaPercent('weeklyPercentClaude'),
            ),
            const SizedBox(height: 10),
            _buildUsageTile(
              context: context,
              title: 'Limite sur 5 heures',
              subtitle: 'Quota complet de 5 heures disponible',
              percent: _quotaPercent('fiveHourPercentClaude'),
            ),
          ],
        ),
      ),
    );
  }

  /// Extrait un pourcentage entier depuis le résumé de quota (fallback null).
  /// Accepte num/num comme la réponse protobuf décodée du daemon.
  int? _quotaPercent(String key) {
    final raw = _quota?[key];
    if (raw is num) return raw.round().clamp(0, 100);
    if (raw is String) return int.tryParse(raw)?.clamp(0, 100);
    return null;
  }

  Widget _buildUsageTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    int? percent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final value = percent;
    Color progressColor = scheme.primary;
    if (value != null && value < 30) {
      progressColor = scheme.error;
    } else if (value != null && value < 60) {
      progressColor = scheme.tertiary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: value == null ? '$title: indisponible' : '$title: $value%',
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: value == null ? 0.0 : value / 100.0,
                    backgroundColor: scheme.surfaceContainer,
                    color: progressColor,
                    strokeWidth: 3,
                  ),
                ),
                Text(
                  value == null ? '—' : '$value%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

