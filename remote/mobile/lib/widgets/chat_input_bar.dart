import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../core/protocol/daemon_api.dart';
import '../core/protocol/model_catalog.dart';
import '../services/settings_store.dart';
import '../features/chat_stream/models/mention_item.dart';
import '../features/chat_stream/widgets/action_pills_bar.dart';
import '../features/chat_stream/widgets/mention_autocomplete_overlay.dart';
import 'bouncing_tap.dart';
import 'custom_dropdown_overlay.dart';
import 'voice_prompt_dialog.dart';
import '../theme/app_colors.dart';

/// Modes d'envoi : immédiat ou mis en file pour exécution séquentielle.
enum SendMode { immediate, queued }

/// Données d'un fichier ou d'une image attachée avant l'envoi.
class _AttachedItem {
  final String name;
  final int size;
  final String? mimeType;
  final Uint8List? bytes;
  final String? base64Data;
  final bool isImage;
  final String? textContent;

  const _AttachedItem({
    required this.name,
    required this.size,
    this.mimeType,
    this.bytes,
    this.base64Data,
    required this.isImage,
    this.textContent,
  });
}

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
  State<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends State<ChatInputBar> {
  void openModelSelector() {
    if (mounted) {
      _showModelDropdown(context);
    }
  }

  final TextEditingController _controller = TextEditingController();
  String _selectedModel = 'Gemini 3.7 Flash';
  String? _selectedModelId = 'gemini-3.7-flash';
  int? _selectedModelEnum = 312;
  List<AntigravityModel> _availableModels = ModelCatalog.standardModels;

  bool _isSendPressed = false;
  SendMode _sendMode = SendMode.immediate;
  // Feature Niveaux d'effort de raisonnement (Faible, Moyen, Élevé)
  String _reasoningEffort = 'Moyen'; // Options: 'Faible', 'Moyen', 'Élevé'
  // Feature multi-attachements fichiers et images (Quiet Console)
  final List<_AttachedItem> _attachments = [];
  double? _uploadProgress;

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
    if ((oldWidget.cascadeId != widget.cascadeId || oldWidget.initialText != widget.initialText) &&
        widget.initialText != _controller.text) {
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
    _isSending = false;
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

  Future<void> _handleSend() async {
    if (_isSending) return;
    final rawText = _controller.text;
    final text = _sanitizeInput(rawText);
    final hasContent = text.isNotEmpty || _attachments.isNotEmpty;
    if (!hasContent) return;

    _isSending = true;
    HapticFeedback.lightImpact();

    // Normaliser les commandes slash avec saut de ligne \n ou tabulation \t
    String finalPayload = text;
    if (text.startsWith('/') && (text.contains('\n') || text.contains('\t'))) {
      final parts = text.split(RegExp(r'[\n\t]'));
      final cmd = parts.first.trim();
      final args = parts.sublist(1).join(' ').trim();
      finalPayload = '$cmd $args'.trim();
    }

    // Traitement et upload des attachements vers le daemon si connecté
    if (widget.api != null && widget.cascadeId != null && _attachments.isNotEmpty) {
      setState(() => _uploadProgress = 0.05);
      for (int i = 0; i < _attachments.length; i++) {
        final att = _attachments[i];
        if (att.base64Data != null) {
          try {
            if (att.isImage) {
              await widget.api!.uploadMedia(
                cascadeId: widget.cascadeId!,
                fileName: att.name,
                mimeType: att.mimeType ?? 'image/jpeg',
                base64Data: att.base64Data!,
              );
            } else {
              await widget.api!.uploadChunk(
                uploadId: 'up_${DateTime.now().millisecondsSinceEpoch}_$i',
                cascadeId: widget.cascadeId!,
                fileName: att.name,
                chunkIndex: 0,
                totalChunks: 1,
                totalBytes: att.size,
                base64Data: att.base64Data!,
              );
            }
          } catch (_) {}
        }
        if (mounted) {
          setState(() => _uploadProgress = (i + 1) / _attachments.length);
        }
      }
    }

    // Construction du payload textuel combiné
    final buffer = StringBuffer();
    final images = _attachments.where((a) => a.isImage).toList();
    final files = _attachments.where((a) => !a.isImage).toList();

    if (images.isNotEmpty) {
      if (images.length == 1) {
        buffer.writeln('[Image jointe: ${images.first.name}]');
      } else {
        buffer.writeln('[Images jointes: ${images.map((img) => img.name).join(', ')}]');
      }
    }

    for (final f in files) {
      if (f.textContent != null) {
        buffer.writeln('[Fichier: ${f.name}]\n${f.textContent}\n');
      } else {
        buffer.writeln('[Fichier joint: ${f.name} (${_formatBytes(f.size)})]');
      }
    }

    if (finalPayload.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(finalPayload);
    }

    final fullMessage = buffer.toString().trim();

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
    if (mounted) {
      FocusScope.of(context).unfocus(); // Ferme le clavier sur mobile après l'envoi
      setState(() {
        _attachments.clear();
        _uploadProgress = null;
        _isSending = false;
      });
    }
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
      case 'dart':
      case 'ts':
      case 'js':
      case 'py':
      case 'go':
        return scheme.primary;
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
      case 'dart':
      case 'ts':
      case 'js':
      case 'py':
      case 'go':
        return Icons.code_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  void _removeAttachment(int index) {
    if (index >= 0 && index < _attachments.length) {
      setState(() => _attachments.removeAt(index));
    }
  }

  void _clearAttachments() {
    setState(() => _attachments.clear());
  }

  /// Sélection d'images natives depuis la galerie (support multi-sélection)
  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedList = await picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (pickedList.isEmpty) return;

      final newItems = <_AttachedItem>[];
      for (final picked in pickedList) {
        final bytes = await picked.readAsBytes();
        final name = picked.name.isNotEmpty ? picked.name : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final mime = picked.mimeType ?? (name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
        final b64 = base64Encode(bytes);
        newItems.add(_AttachedItem(
          name: name,
          size: bytes.length,
          mimeType: mime,
          bytes: bytes,
          base64Data: b64,
          isImage: true,
        ));
      }

      setState(() => _attachments.addAll(newItems));
    } catch (_) {
      _pickImage();
    }
  }

  /// Prise de photo directe avec l'appareil photo
  Future<void> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final mime = 'image/jpeg';
      final b64 = base64Encode(bytes);

      setState(() {
        _attachments.add(_AttachedItem(
          name: name,
          size: bytes.length,
          mimeType: mime,
          bytes: bytes,
          base64Data: b64,
          isImage: true,
        ));
      });
    } catch (_) {
      _pickImage();
    }
  }

  /// Sélection de fichiers natifs du smartphone (support multi-fichiers)
  Future<void> _pickFileNative() async {
    try {
      final res = await FilePicker.pickFiles(
        withData: true,
        allowMultiple: true,
      );
      if (res == null || res.files.isEmpty) return;

      final newItems = <_AttachedItem>[];
      for (final f in res.files) {
        Uint8List? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          try {
            bytes = await File(f.path!).readAsBytes();
          } catch (_) {}
        }
        if (bytes == null || bytes.isEmpty) continue;
        final name = f.name;
        final size = f.size > 0 ? f.size : bytes.length;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final isImg = ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext);
        final b64 = base64Encode(bytes);
        String? textContent;
        if (['txt', 'json', 'md', 'csv', 'dart', 'ts', 'js', 'py', 'go', 'yaml', 'yml', 'html', 'css', 'xml', 'sh'].contains(ext) && bytes.length < 500000) {
          try {
            textContent = utf8.decode(bytes, allowMalformed: true);
          } catch (_) {}
        }
        newItems.add(_AttachedItem(
          name: name,
          size: size,
          mimeType: isImg ? (ext == 'png' ? 'image/png' : 'image/jpeg') : 'application/octet-stream',
          bytes: bytes,
          base64Data: b64,
          isImage: isImg,
          textContent: textContent,
        ));
      }

      setState(() => _attachments.addAll(newItems));
    } catch (_) {
      _pickTextFile();
    }
  }

  /// Collage automatique et intelligent depuis le presse-papier
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;

      if (text.startsWith('data:image/') && text.contains('base64,')) {
        final parts = text.split('base64,');
        final mime = parts.first.replaceAll('data:', '').replaceAll(';', '').trim();
        final b64 = parts.last.trim();
        Uint8List? bytes;
        try {
          bytes = base64Decode(b64);
        } catch (_) {}
        final ext = mime.contains('png') ? 'png' : 'jpg';
        final name = 'clipboard_${DateTime.now().millisecondsSinceEpoch}.$ext';
        setState(() {
          _attachments.add(_AttachedItem(
            name: name,
            size: bytes?.length ?? 0,
            mimeType: mime,
            bytes: bytes,
            base64Data: b64,
            isImage: true,
          ));
        });
      } else if (text.length > 100 || text.startsWith('{') || text.startsWith('[') || text.startsWith('<?') || text.contains('\n')) {
        final isJson = (text.startsWith('{') && text.endsWith('}')) || (text.startsWith('[') && text.endsWith(']'));
        final name = isJson ? 'clipboard_data.json' : 'clipboard_snippet.txt';
        final bytes = Uint8List.fromList(utf8.encode(text));
        setState(() {
          _attachments.add(_AttachedItem(
            name: name,
            size: bytes.length,
            mimeType: isJson ? 'application/json' : 'text/plain',
            bytes: bytes,
            base64Data: base64Encode(bytes),
            isImage: false,
            textContent: text,
          ));
        });
      } else {
        _insertTextAtCursor(text);
      }
    } catch (_) {}
  }

  /// Feature attachement .txt, .json, .md, .csv (Fallback manuel)
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
          content: SingleChildScrollView(
            child: Column(
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
      final name = result['name']!.isEmpty ? 'fichier.txt' : result['name']!;
      final content = result['content']!;
      final bytes = Uint8List.fromList(utf8.encode(content));
      setState(() {
        _attachments.add(_AttachedItem(
          name: name,
          size: bytes.length,
          mimeType: 'text/plain',
          bytes: bytes,
          base64Data: base64Encode(bytes),
          isImage: false,
          textContent: content,
        ));
      });
    }
  }

  /// Feature attachement image/photo (Fallback Base64)
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
          content: SingleChildScrollView(
            child: Column(
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

      Uint8List? rawBytes;
      try {
        rawBytes = base64Decode(base64Data);
      } catch (_) {}

      setState(() {
        _attachments.add(_AttachedItem(
          name: fileName,
          size: rawBytes?.length ?? 0,
          mimeType: mimeType,
          bytes: rawBytes,
          base64Data: base64Data,
          isImage: true,
        ));
      });
    }
  }

  /// Aperçu visuel Quiet Console des attachements sélectionnés (carte unique ou carousel scrollable)
  Widget _buildAttachmentPreview(ColorScheme scheme, bool isDark) {
    if (_attachments.isEmpty) return const SizedBox.shrink();

    final totalBytes = _attachments.fold<int>(0, (sum, item) => sum + item.size);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de progression d'upload si en cours
          if (_uploadProgress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _uploadProgress,
                        minHeight: 3,
                        backgroundColor: isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${((_uploadProgress ?? 0) * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),

          if (_attachments.length == 1)
            // Carte unique détaillée
            _buildSingleAttachmentCard(_attachments.first, 0, scheme, isDark)
          else
            // Multi-attachements : Header récapitulatif + Carousel horizontal
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.attach_file_rounded, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${_attachments.length} pièces jointes (${_formatBytes(totalBytes)})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      BouncingTap(
                        onTap: _clearAttachments,
                        child: Text(
                          'Tout effacer',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) => _buildCompactAttachmentCard(_attachments[idx], idx, scheme, isDark),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showAttachmentInspectDialog(_AttachedItem att, int index) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Icon(
                    att.isImage ? Icons.image_outlined : _iconForExtension(att.name),
                    size: 18,
                    color: _badgeColorForExtension(att.name, scheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      att.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _formatBytes(att.size),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content preview
            Flexible(
              child: att.isImage && att.bytes != null
                  ? Container(
                      constraints: const BoxConstraints(maxHeight: 380),
                      color: isDark ? const Color(0xFF101216) : scheme.surfaceContainerLow,
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.memory(
                            att.bytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      padding: const EdgeInsets.all(12),
                      color: isDark ? const Color(0xFF101216) : scheme.surfaceContainerLow,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          att.textContent ?? '[Fichier binaire (${_formatBytes(att.size)})]',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
                    label: Text(
                      'Supprimer',
                      style: TextStyle(color: scheme.error, fontSize: 12.5),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _removeAttachment(index);
                    },
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleAttachmentCard(_AttachedItem att, int index, ColorScheme scheme, bool isDark) {
    final sizeStr = _formatBytes(att.size);
    final isImg = att.isImage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAttachmentInspectDialog(att, index),
            child: isImg && att.bytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      att.bytes!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  )
                : Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _badgeColorForExtension(att.name, scheme).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _iconForExtension(att.name),
                      size: 20,
                      color: _badgeColorForExtension(att.name, scheme),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _showAttachmentInspectDialog(att, index),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    att.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                    ),
                  ),
                  if (sizeStr.isNotEmpty)
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          BouncingTap(
            onTap: () => _removeAttachment(index),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF26282E) : scheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAttachmentCard(_AttachedItem att, int index, ColorScheme scheme, bool isDark) {
    final isImg = att.isImage;

    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAttachmentInspectDialog(att, index),
            child: isImg && att.bytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      att.bytes!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  )
                : Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _badgeColorForExtension(att.name, scheme).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      _iconForExtension(att.name),
                      size: 16,
                      color: _badgeColorForExtension(att.name, scheme),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => _showAttachmentInspectDialog(att, index),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    att.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.inkPrimary : scheme.onSurface,
                    ),
                  ),
                  Text(
                    _formatBytes(att.size),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          BouncingTap(
            onTap: () => _removeAttachment(index),
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: scheme.primary),
                title: Text(
                  'Prendre une photo',
                  style: TextStyle(color: isDark ? AppColors.inkPrimary : scheme.onSurface, fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Appareil photo en direct', style: TextStyle(color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: scheme.primary),
                title: Text(
                  'Choisir des images',
                  style: TextStyle(color: isDark ? AppColors.inkPrimary : scheme.onSurface, fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Galerie photos multi-sélection (PNG, JPEG, WebP, GIF)', style: TextStyle(color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImageFromGallery();
                },
              ),
              ListTile(
                leading: Icon(Icons.file_present_outlined, color: scheme.primary),
                title: Text(
                  'Sélectionner des fichiers',
                  style: TextStyle(color: isDark ? AppColors.inkPrimary : scheme.onSurface, fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Code, JSON, Markdown, texte, PDF...', style: TextStyle(color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFileNative();
                },
              ),
              ListTile(
                leading: Icon(Icons.content_paste_rounded, color: scheme.primary),
                title: Text(
                  'Coller depuis le presse-papier',
                  style: TextStyle(color: isDark ? AppColors.inkPrimary : scheme.onSurface, fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Image Base64, JSON, texte ou extrait de code', style: TextStyle(color: isDark ? AppColors.inkMuted : scheme.onSurfaceVariant, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pasteFromClipboard();
                },
              ),
              ListTile(
                leading: Icon(Icons.edit_note_outlined, color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant),
                title: Text(
                  'Saisie manuelle (Base64 / Texte)',
                  style: TextStyle(color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant, fontSize: 13),
                ),
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
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SingleChildScrollView(
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

    final standard = _availableModels.where((m) => !m.isCustom).toList();
    final custom = _availableModels.where((m) => m.isCustom).toList();

    CustomDropdownOverlay.show(
      context: context,
      targetKey: _modelButtonKey,
      width: 300,
      maxHeight: 480,
      child: _ModelDropdownMenuContent(
        standardModels: standard,
        customModels: custom,
        selectedModel: _selectedModel,
        reasoningEffort: _reasoningEffort,
        onModelSelected: (model, effort) => _selectModelWithEffort(model, effort),
        onViewUsage: () {
          CustomDropdownOverlay.hide();
          _showUsageLimitsDialog(context);
        },
      ),
    );
  }

  Future<void> _selectModelWithEffort(AntigravityModel model, String? effort) async {
    HapticFeedback.selectionClick();
    final effectiveModel = effort != null ? model.withEffort(effort) : model;
    final short = effectiveModel.shortName;
    setState(() {
      _selectedModel = short;
      _selectedModelId = effectiveModel.id;
      _selectedModelEnum = effectiveModel.modelEnum;
      if (effort != null) {
        _reasoningEffort = effort;
      }
    });
    CustomDropdownOverlay.hide();

    widget.onModelChanged?.call(effectiveModel.displayName);

    // Persist choice in local settings
    await SettingsStore.save({
      'defaultModel': effectiveModel.displayName,
      if (effort != null) 'reasoningEffort': effort.toLowerCase(),
    });

    // Send /model and /effort commands to daemon
    try {
      await widget.api?.sendCommand('/model ${effectiveModel.id}');
      if (effort != null) {
        await widget.api?.sendCommand('/effort ${effort.toLowerCase()}');
      }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isQueued = _sendMode == SendMode.queued;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final rawInsetsBottom = View.of(context).viewInsets.bottom / MediaQuery.of(context).devicePixelRatio;
    final hasKeyboard = viewInsets.bottom > 50 || rawInsetsBottom > 50;
    final bottomMargin = hasKeyboard
        ? 2.0
        : (viewPadding.bottom > 0 ? 4.0 : 8.0);

    return SafeArea(
      top: false,
      bottom: !hasKeyboard,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 2, 12, bottomMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.projectName != null && widget.projectName!.isNotEmpty && !hasKeyboard)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: InkWell(
                  onTap: widget.onSelectProject,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceRaised
                          : AppColors.panel(context),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isDark
                            ? AppColors.borderSubtle
                            : AppColors.border(context),
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
                            color: isDark ? AppColors.inkPrimary : AppColors.text(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: isDark ? AppColors.inkMuted : AppColors.textMuted(context)),
                      ],
                    ),
                  ),
                ),
              ),
            if (!hasKeyboard)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ActionPillsBar(
                  onActionSelected: (cmd) {
                    _insertTextAtCursor(cmd);
                  },
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: hasKeyboard ? 6 : 12,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceRaised
                    : AppColors.panel(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isQueued
                      ? scheme.primary.withValues(alpha: 0.6)
                      : (isDark
                          ? AppColors.borderSubtle
                          : AppColors.border(context)),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Aperçu attachement Quiet Console (Image ou Fichier)
                  _buildAttachmentPreview(scheme, isDark),

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
                                      ? "Message queued — sends after agent finishes working"
                                      : 'Ask anything, @ to mention, / for actions')
                                  : 'Offline — message will be sent when reconnected',
                          hintStyle: TextStyle(
                            color:
                                widget.isConnected ? scheme.onSurfaceVariant.withValues(alpha: 0.8) : scheme.error,
                            fontSize: 13.5,
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
                  SizedBox(height: hasKeyboard ? 4 : 10),

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
                        fit: FlexFit.loose,
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
                                    _selectedModel,
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
                                  Icons.keyboard_arrow_up,
                                  size: 15,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Voice / Dictée vocale avec formatage intelligent de code
                      IconButton(
                        icon: Icon(
                          Icons.mic_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          VoicePromptDialog.show(
                            context,
                            onInsert: (formattedText) {
                              final current = _controller.text;
                              final newText = current.isEmpty
                                  ? formattedText
                                  : '$current $formattedText';
                              _controller.text = newText;
                              _controller.selection = TextSelection.collapsed(offset: newText.length);
                              widget.onDraftChanged?.call(newText);
                            },
                          );
                        },
                        tooltip: 'Dictée vocale & formatage code',
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
                                            : ((_controller.text.trim().isNotEmpty || _attachments.isNotEmpty) &&
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
                                        color: ((_controller.text.trim().isNotEmpty || _attachments.isNotEmpty) &&
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

class _ModelDropdownMenuContent extends StatefulWidget {
  final List<AntigravityModel> standardModels;
  final List<AntigravityModel> customModels;
  final String selectedModel;
  final String reasoningEffort;
  final void Function(AntigravityModel model, String? effort) onModelSelected;
  final VoidCallback onViewUsage;

  const _ModelDropdownMenuContent({
    required this.standardModels,
    required this.customModels,
    required this.selectedModel,
    required this.reasoningEffort,
    required this.onModelSelected,
    required this.onViewUsage,
  });

  @override
  State<_ModelDropdownMenuContent> createState() => _ModelDropdownMenuContentState();
}

class _ModelDropdownMenuContentState extends State<_ModelDropdownMenuContent> {
  String? _expandedBaseName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
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
          ...widget.standardModels.map((m) => _buildStandardModelRow(m, isDark, scheme, textTheme)),
          if (widget.customModels.isNotEmpty) ...[
            Divider(color: isDark ? const Color(0xFF2B2D31) : scheme.outlineVariant, height: 1),
            ...widget.customModels.map((m) => _buildCustomModelRow(m, isDark, scheme, textTheme)),
          ],
          Divider(color: isDark ? const Color(0xFF2B2D31) : scheme.outlineVariant, height: 1),
          _buildViewUsageRow(isDark, scheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildStandardModelRow(
    AntigravityModel model,
    bool isDark,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final isSelected = widget.selectedModel.toLowerCase().contains(model.baseName.toLowerCase()) ||
        widget.selectedModel.toLowerCase() == model.displayName.toLowerCase();
    final isExpanded = _expandedBaseName == model.baseName;

    final currentEffort = isSelected
        ? (widget.reasoningEffort.isNotEmpty ? _capitalize(widget.reasoningEffort) : (model.effort ?? 'Medium'))
        : (model.effort ?? 'Medium');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          selected: isSelected,
          label: '${model.baseName} $currentEffort',
          child: InkWell(
            onTap: () {
              if (model.supportsEffort) {
                setState(() {
                  _expandedBaseName = isExpanded ? null : model.baseName;
                });
              } else {
                widget.onModelSelected(model, null);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected && !isExpanded
                      ? (isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.baseName,
                              style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                                color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (model.supportsEffort) ...[
                            const SizedBox(width: 6),
                            Text(
                              currentEffort,
                              style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 12.5)).copyWith(
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (model.tag != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest,
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
                            const SizedBox(width: 3),
                            Icon(Icons.info_outline, size: 10, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    if (isSelected && !model.supportsEffort)
                      Icon(Icons.check, size: 16, color: scheme.primary)
                    else if (model.supportsEffort)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _expandedBaseName = isExpanded ? null : model.baseName;
                          });
                        },
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (model.supportsEffort && isExpanded)
          Container(
            margin: const EdgeInsets.only(left: 20, right: 10, top: 2, bottom: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181A1D) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF2B2D31) : scheme.outlineVariant,
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEffortTile(model, 'Low', isSelected, currentEffort, isDark, scheme, textTheme),
                _buildEffortTile(model, 'Medium', isSelected, currentEffort, isDark, scheme, textTheme),
                _buildEffortTile(model, 'High', isSelected, currentEffort, isDark, scheme, textTheme),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEffortTile(
    AntigravityModel model,
    String effortTier,
    bool isModelSelected,
    String currentEffort,
    bool isDark,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final isTierActive = isModelSelected && currentEffort.toLowerCase() == effortTier.toLowerCase();

    return InkWell(
      onTap: () => widget.onModelSelected(model, effortTier),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isTierActive ? (isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              effortTier,
              style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 12.5)).copyWith(
                fontWeight: isTierActive ? FontWeight.w600 : FontWeight.w400,
                color: isTierActive ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            if (isTierActive)
              Icon(Icons.check, size: 14, color: scheme.primary)
            else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomModelRow(
    AntigravityModel model,
    bool isDark,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final isSelected = widget.selectedModel.toLowerCase().contains(model.id.toLowerCase()) ||
        widget.selectedModel.toLowerCase().contains(model.displayName.toLowerCase());

    Color statusColor = scheme.primary;
    if (model.status == 'degraded') {
      statusColor = const Color(0xFFFFCC00);
    } else if (model.status == 'offline') {
      statusColor = scheme.error;
    } else {
      statusColor = const Color(0xFFFFCC00);
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: model.customLabel,
      child: InkWell(
        onTap: () => widget.onModelSelected(model, null),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? (isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest) : Colors.transparent,
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

  Widget _buildViewUsageRow(
    bool isDark,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Semantics(
      button: true,
      label: 'View Usage',
      child: InkWell(
        onTap: widget.onViewUsage,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
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

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

