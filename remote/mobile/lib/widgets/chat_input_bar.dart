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

/// Modes d'envoi : immédiat ou mis en file pour exécution séquentielle.
enum SendMode { immediate, queued }

class ChatInputBar extends StatefulWidget {
  final Function(String message, {bool queued}) onSend;
  final bool isConnected;

  /// Feature queue : true si l'agent a un travail actif.
  final bool hasActiveStream;

  final DaemonApi? api;
  final String? cascadeId;
  final ValueChanged<String>? onModelChanged;
  final VoidCallback? onStop;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isConnected = true,
    this.hasActiveStream = false,
    this.api,
    this.cascadeId,
    this.onModelChanged,
    this.onStop,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  String _selectedModel = 'Gemini 3.7 Flash';
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadModelsAndPreferences();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.isConnected != widget.isConnected) {
      _loadModelsAndPreferences();
    }
  }

  Future<void> _loadModelsAndPreferences() async {
    try {
      final s = await SettingsStore.load();
      final savedModel = s['defaultModel'] as String?;
      if (savedModel != null && savedModel.isNotEmpty && mounted) {
        setState(() {
          _selectedModel = savedModel.split(' ').take(3).join(' ');
        });
      }
    } catch (_) {}

    if (widget.api != null) {
      final models = await ModelCatalog.getAllAvailableModels(widget.api);
      if (mounted && models.isNotEmpty) {
        setState(() {
          _availableModels = models;
        });
      }
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed == false) {
      // Don't close if they just clicked inside the model dropdown
      // Actually, we'll just let the dropdown manage its own state when clicking away
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
      _showActionDropdown();
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
    _controller.dispose();
    super.dispose();
  }

  String _sanitizeInput(String raw) {
    // Supprime les lignes vides en trop lors du collage de texte brut multi-lignes
    return raw.replaceAll(RegExp(r'(\r?\n){3,}'), '\n\n').trim();
  }

  void _handleSend() {
    final rawText = _controller.text;
    final text = _sanitizeInput(rawText);
    final hasContent = text.isNotEmpty || _attachedFileContent != null;
    if (!hasContent) return;

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

    widget.onSend(fullMessage, queued: _sendMode == SendMode.queued);
    _controller.clear();
    FocusScope.of(
      context,
    ).unfocus(); // Ferme le clavier sur mobile après l'envoi
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

  void _showActionDropdown() {
    _mentionOrActionOpen = true;
    CustomDropdownOverlay.show(
      context: context,
      targetKey: _textFieldKey,
      width: 250,
      maxHeight: 200,
      child: Material(
        color: Colors.transparent,
        child: ListView(
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
            _buildPopupItem(
              Icons.chat_bubble_outline_rounded,
              '/btw',
              'Side question without breaking flow',
              () {
                _insertTextAtCursor('/btw ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.quiz_outlined,
              '/grill-me',
              'Interactive planning interview',
              () {
                _insertTextAtCursor('/grill-me ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.flag_outlined,
              '/goal',
              'Autonomous goal until fully achieved',
              () {
                _insertTextAtCursor('/goal ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.schedule_outlined,
              '/schedule',
              'Set recurring timer / background cron',
              () {
                _insertTextAtCursor('/schedule ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.rate_review_outlined,
              '/review',
              'Audit code diffs and complexity',
              () {
                _insertTextAtCursor('/review ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.edit_note_rounded,
              '/plan',
              'Draft technical implementation plan',
              () {
                _insertTextAtCursor('/plan ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.design_services,
              '/design',
              'Generate UI components & screens',
              () {
                _insertTextAtCursor('/design ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.code,
              '/code',
              'Generate Code Implementation',
              () {
                _insertTextAtCursor('/code ');
                CustomDropdownOverlay.hide();
              },
            ),
            _buildPopupItem(
              Icons.search,
              '/search',
              'Semantic project search',
              () {
                _insertTextAtCursor('/search ');
                CustomDropdownOverlay.hide();
              },
            ),
          ],
        ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelDropdown(BuildContext context) {
    _mentionOrActionOpen = false;
    _loadModelsAndPreferences();

    final scheme = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  fontSize: 12,
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
    final isSelected = _selectedModel.toLowerCase().contains(model.shortName.toLowerCase()) ||
        _selectedModel.toLowerCase() == model.displayName.toLowerCase();

    return InkWell(
      onTap: () => _selectModel(model),
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
                style: TextStyle(
                  fontSize: 13,
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
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
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
    );
  }

  Widget _buildCustomModelRow(AntigravityModel model) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedModel.toLowerCase().contains(model.id.toLowerCase()) ||
        _selectedModel.toLowerCase().contains(model.displayName.toLowerCase());

    Color statusColor = scheme.primary;
    if (model.status == 'degraded') {
      statusColor = scheme.tertiary;
    } else if (model.status == 'offline') {
      statusColor = scheme.error;
    }

    return InkWell(
      onTap: () => _selectModel(model),
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
                style: TextStyle(
                  fontSize: 12.5,
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
    );
  }

  Widget _buildViewUsageRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        CustomDropdownOverlay.hide();
        _showUsageLimitsDialog(context);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.query_stats_outlined, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'View Usage',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: scheme.outline),
          ],
        ),
      ),
    );
  }

  Future<void> _selectModel(AntigravityModel model) async {
    HapticFeedback.selectionClick();
    final short = model.shortName;
    setState(() => _selectedModel = short);
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
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => const _UsageLimitsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isQueued = _sendMode == SendMode.queued;

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ActionPillsBar(
                onActionSelected: (cmd) {
                  _insertTextAtCursor(cmd);
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border:
                    isQueued
                        ? Border.all(
                          color: scheme.primary.withValues(alpha: 0.5),
                        )
                        : null,
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
                          InkWell(
                            onTap:
                                () => setState(() {
                                  _attachedFileName = null;
                                  _attachedFileContent = null;
                                }),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: scheme.onSurfaceVariant,
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
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '$_selectedModel ($_reasoningEffort)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
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

                      // Voice (placeholder — pas de backend audio : tooltip
                      // honnête au lieu d'un contrôle mort silencieux)
                      IconButton(
                        icon: Icon(
                          Icons.mic_none,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: () {},
                        tooltip: 'Saisie vocale — bientôt disponible',
                      ),
                      // Stop button (Emergency Stop)
                      if (widget.hasActiveStream && widget.onStop != null) ...[
                        Tooltip(
                          message: 'Arrêter la génération (Emergency Stop)',
                          child: InkWell(
                            key: const Key('stop-generation-button'),
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              widget.onStop!();
                            },
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.stop_circle_outlined, size: 16, color: scheme.error),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Arrêter',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],

                      // Send button
                      GestureDetector(
                        onTapDown: (_) => setState(() => _isSendPressed = true),
                        onTapUp: (_) {
                          setState(() => _isSendPressed = false);
                          _handleSend();
                        },
                        onTapCancel:
                            () => setState(() => _isSendPressed = false),
                        child: AnimatedScale(
                          scale: _isSendPressed ? 0.85 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOutQuart,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: GestureDetector(
                              onLongPress: () => _showQueueSettings(context),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color:
                                      widget.isConnected
                                          ? scheme.primary
                                          : scheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isQueued
                                      ? Icons.playlist_add_check
                                      : Icons.arrow_forward,
                                  size: 16,
                                  color:
                                      widget.isConnected
                                          ? scheme.onPrimary
                                          : scheme.onSurfaceVariant.withValues(
                                            alpha: 0.5,
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

            // Footer
            Container(
              margin: const EdgeInsets.only(top: 8, left: 4, right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message:
                        'Exécution locale (statique — bientôt configurable)',
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monitor_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Local',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message:
                        'Agent principal (statique — bientôt configurable)',
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Main Agent',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
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
class _UsageLimitsModal extends StatelessWidget {
  const _UsageLimitsModal();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
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
            const SizedBox(height: 12),
            _buildUsageTile(
              context: context,
              title: 'Limite hebdomadaire restante',
              subtitle: 'Quota hebdomadaire disponible',
              percent: 51,
            ),
            const SizedBox(height: 10),
            _buildUsageTile(
              context: context,
              title: 'Limite sur 5 heures',
              subtitle: 'Quota sur fenêtre de 5 heures',
              percent: 95,
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
              percent: 81,
            ),
            const SizedBox(height: 10),
            _buildUsageTile(
              context: context,
              title: 'Limite sur 5 heures',
              subtitle: 'Quota complet de 5 heures disponible',
              percent: 100,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int percent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Color progressColor = scheme.primary;
    if (percent < 30) {
      progressColor = scheme.error;
    } else if (percent < 60) {
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
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: percent / 100.0,
                  backgroundColor: scheme.surfaceContainer,
                  color: progressColor,
                  strokeWidth: 3,
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

