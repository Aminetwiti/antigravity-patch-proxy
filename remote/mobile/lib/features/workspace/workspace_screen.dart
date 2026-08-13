import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../core/protocol/daemon_api.dart';
import '../../widgets/custom_dropdown_overlay.dart';

class WorkspaceScreen extends StatefulWidget {
  final DaemonApi? api;
  final String workspacePath;

  const WorkspaceScreen({super.key, this.api, this.workspacePath = '.'});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _selectedFilePath = '';
  bool _isLoadingTree = true;
  bool _isLoadingCode = false;
  String? _loadError;
  List<Map<String, dynamic>> _files = [];
  String _codeContent = '// Sélectionnez un fichier';
  // Bug #5 : recherche substring dans l'arbre
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // Find-in-page (Cmd+F) dans le viewer de code
  final TextEditingController _findController = TextEditingController();
  String _findQuery = '';
  bool _showFindBar = false;
  final GlobalKey _workspaceButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _findController.addListener(() {
      setState(() => _findQuery = _findController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _findController.dispose();
    super.dispose();
  }

  // Basename réel du workspace (antigravity-add-model-main, pas le path complet).
  String get _workspaceLabel {
    final p = widget.workspacePath.trim();
    if (p.isEmpty || p == '.') return 'antigravity-add-model-main';
    final cleaned = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final i = cleaned.lastIndexOf(RegExp(r'[/\\]'));
    return i >= 0 ? cleaned.substring(i + 1) : cleaned;
  }

  Future<void> _loadFiles() async {
    if (widget.api == null) {
      if (mounted) setState(() { _isLoadingTree = false; _loadError = null; });
      return;
    }
    try {
      final res = await widget.api!.listFiles(widget.workspacePath);
      if (mounted) {
        setState(() {
          _files = List<Map<String, dynamic>>.from(res['files'] ?? []);
          _isLoadingTree = false;
          _loadError = null;
        });
      }
    } catch (e) {
      // Bug #6 : afficher l'erreur explicitement au lieu de silencer.
      if (mounted) {
        setState(() {
          _isLoadingTree = false;
          _loadError = e.toString();
        });
      }
    }
  }

  void _loadFile(String path) async {
    setState(() {
      _selectedFilePath = path;
      _isLoadingCode = true;
      _codeContent = '';
    });
    try {
      final res = await widget.api!.readFile(path, workspacePath: widget.workspacePath);
      if (mounted) {
        setState(() {
          _codeContent = res['content'] as String? ?? '';
          _isLoadingCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeContent = 'Erreur: $e';
          _isLoadingCode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        final fileTree = Container(
          width: isMobile ? double.infinity : 280,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: _workspaceButtonKey,
                onTap: () => _showWorkspaceDropdown(context),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _workspaceLabel,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              // Bug #5 : barre de recherche substring.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            onPressed: () => _searchController.clear(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoadingTree
                  ? _buildSkeletonTree()
                  : _loadError != null
                      ? _buildErrorState(_loadError!)
                      : _buildFileList(),
              ),
            ],
          ),
        );

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text('Explorateur de Fichiers'),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          drawer: isMobile ? Drawer(child: SafeArea(child: fileTree)) : null,
          body: Row(
            children: [
              if (!isMobile) fileTree,
              // ── Right Code View
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              _selectedFilePath,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _selectedFilePath.endsWith('.png') || _selectedFilePath.endsWith('.jpg') || _selectedFilePath.endsWith('.svg')
                              ? Icons.image_search_outlined
                              : Icons.copy_all_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _selectedFilePath.endsWith('.png') || _selectedFilePath.endsWith('.jpg') || _selectedFilePath.endsWith('.svg')
                            ? 'Copier l\'image'
                            : 'Copier le contenu',
                        onPressed: _selectedFilePath.isEmpty || _isLoadingCode
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await Clipboard.setData(ClipboardData(text: _codeContent));
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(_selectedFilePath.endsWith('.png') || _selectedFilePath.endsWith('.jpg') || _selectedFilePath.endsWith('.svg')
                                        ? 'Image copiée dans le presse-papier !'
                                        : 'Contenu copié : ${_selectedFilePath.split('/').last}'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                      ),
                      // Find-in-page toggle
                      IconButton(
                        icon: Icon(
                          Icons.search,
                          size: 16,
                          color: _showFindBar
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: 'Rechercher dans le fichier (Cmd+F)',
                        onPressed: _selectedFilePath.isEmpty
                            ? null
                            : () => setState(() {
                                _showFindBar = !_showFindBar;
                                if (!_showFindBar) _findController.clear();
                              }),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Find-in-page bar (toggle via icône loupe)
                if (_showFindBar)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _findController,
                            autofocus: true,
                            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Trouver dans le fichier...',
                              hintStyle: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              prefixIcon: Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_findQuery.isNotEmpty)
                          Text(
                            '${_countMatches(_codeContent, _findQuery)} rés.',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => setState(() {
                            _showFindBar = false;
                            _findController.clear();
                          }),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: _isLoadingCode
                        ? _buildSkeletonCode()
                        : _buildCodeView(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  void _showWorkspaceDropdown(BuildContext context) {
    CustomDropdownOverlay.show(
      context: context,
      targetKey: _workspaceButtonKey,
      width: 320,
      child: Material(
        color: Colors.transparent,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            _buildWorkspaceItem('antigravity-add-model-main', true),
            _buildWorkspaceItem('www - Copie', false),
            _buildWorkspaceItem('sols-pro-vision', false),
            _buildWorkspaceItem(r'c:\Users\amine\Desktop\ooredoo\posweb', false),
            _buildWorkspaceItem(r'c:\Users\amine\OmniRoute', false),
            _buildWorkspaceItem('mo7i', false),
            Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
            _buildWorkspaceActionItem(Icons.create_new_folder_outlined, 'New Project'),
            _buildWorkspaceActionItem(Icons.bolt_outlined, 'Quick Start'),
            Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
            _buildWorkspaceActionItem(Icons.do_disturb_alt_outlined, 'No Project'),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceItem(String title, bool isSelected) {
    return InkWell(
      onTap: () {
        CustomDropdownOverlay.hide();
        // Here we would actually change the workspace
      },
      child: Container(
        color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceActionItem(IconData icon, String title) {
    return InkWell(
      onTap: () {
        CustomDropdownOverlay.hide();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bug #3 : perf — construit la liste une seule fois, filtrée par _searchQuery.
  Widget _buildFileList() {
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'Espace de travail vide',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Aucun fichier à afficher dans ce répertoire.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final filtered = _searchQuery.isEmpty
        ? _files
        : _files.where((f) {
            final name = (f['name'] as String).toLowerCase();
            return name.contains(_searchQuery);
          }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchQuery.isEmpty
                ? 'Aucun fichier dans ce workspace'
                : 'Aucun résultat pour «\u00a0$_searchQuery\u00a0»',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final file = filtered[index];
        final isDir = file['isDir'] == true;
        final name = file['name'] as String;
        final depth = (file['depth'] as num?)?.toInt() ?? 0;
        final fullPath = file['fullPath'] as String? ?? name;
        final isSelected = fullPath == _selectedFilePath;

        if (isDir) {
          return _TreeFolder(title: name, depth: depth);
        } else {
          return _TreeFile(
            title: name,
            depth: depth,
            isSelected: isSelected,
            onTap: () {
              // Mobile : le drawer reste ouvert après sélection sinon.
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && scaffold.isDrawerOpen) {
                scaffold.closeDrawer();
              }
              _loadFile(fullPath);
            },
          );
        }
      },
    );
  }

  // Bug #6 : état d'erreur explicite avec bouton de rechargement.
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Impossible de charger les fichiers',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() { _isLoadingTree = true; _loadError = null; });
                _loadFiles();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  // Find-in-page : comptage des occurrences (insensible à la casse).\n  // ponytail: allMatches() d'une RegExp — stdlib, zéro allocation custom.
  int _countMatches(String content, String query) {
    if (query.isEmpty) return 0;
    return RegExp(RegExp.escape(query), caseSensitive: false)
        .allMatches(content)
        .length;
  }

  // Bug find-in-page + Bug #4 (diffs > 1000 lignes) :
  // — Quand _findQuery est vide : ListView.builder ligne par ligne (virtualisation)
  //   → corrige le rendu défaillant sur les fichiers volumineux (>1000 lignes).
  // — Quand _findQuery est non-vide : RichText avec spans surlignés ligne par ligne.
  // ponytail: on ne reconstruit que les lignes visibles (itemBuilder à la volée).
  Widget _buildCodeView() {
    // Handling SVG previews safely without crashing on raw binary
    if (_selectedFilePath.endsWith('.svg')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Aperçu Vectoriel SVG', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minWidth: 200, minHeight: 200),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(_codeContent),
              ),
            ),
          ),
        ],
      );
    }

    // Fichiers binaires (images, audio, vidéo) : pas de numéros de ligne
    final isBinary = _selectedFilePath.endsWith('.png') ||
        _selectedFilePath.endsWith('.jpg') ||
        _selectedFilePath.endsWith('.mp3') ||
        _selectedFilePath.endsWith('.mp4');
    if (isBinary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedFilePath.endsWith('.mp3')
                  ? Icons.audio_file_outlined
                  : _selectedFilePath.endsWith('.mp4')
                      ? Icons.video_file_outlined
                      : Icons.image_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Aperçu multimédia (${_selectedFilePath.split('.').last.toUpperCase()})',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text('Fichier binaire — numéros de ligne masqués', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // Tronquage de sécurité pour éviter les plantages sur les sorties > 2000 lignes ou > 50 000 caractères
    final bool isLargeFile = _codeContent.length > 50000;
    final safeContent = isLargeFile ? _codeContent.substring(0, 50000) : _codeContent;
    final rawLines = safeContent.split('\n');
    final lines = rawLines.length > 2000 ? rawLines.sublist(0, 2000) : rawLines;

    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final lineNumberStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    // Lignes du viewer : numéros + contenu (softWrap:false pour permettre le
    // scroll horizontal du conteneur parent au lieu du wrap silencieux).
    final codeList = ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final lineNum = '${index + 1}'.padLeft(4, ' ');
        final line = lines[index];
        if (_findQuery.isEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$lineNum │ ', style: lineNumberStyle),
              Expanded(
                child: SelectableText(
                  line,
                  style: textStyle,
                  // Longues lignes → scroll horizontal, pas de wrap.
                  maxLines: null,
                ),
              ),
            ],
          );
        }
        // Surlignage : découper la ligne en spans autour de chaque match.
        final spans = <TextSpan>[];
        final pattern = RegExp(RegExp.escape(_findQuery), caseSensitive: false);
        int cursor = 0;
        for (final match in pattern.allMatches(line)) {
          if (match.start > cursor) {
            spans.add(TextSpan(text: line.substring(cursor, match.start)));
          }
          spans.add(TextSpan(
            text: line.substring(match.start, match.end),
            style: TextStyle(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30),
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ));
          cursor = match.end;
        }
        if (cursor < line.length) {
          spans.add(TextSpan(text: line.substring(cursor)));
        }
        return RichText(
          text: TextSpan(style: textStyle, children: spans),
        );
      },
    );

    return Column(
      children: [
        if (isLargeFile || rawLines.length > 2000)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
            child: Text(
              isLargeFile && rawLines.length > 2000
                  ? 'Fichier volumineux — ${rawLines.length} lignes, 2000 affichées (contenu tronqué à 50 000 caractères)'
                  : isLargeFile
                      ? 'Fichier volumineux — contenu tronqué à 50 000 caractères'
                      : 'Fichier volumineux — ${rawLines.length} lignes, 2000 affichées',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        Expanded(
          // ponytail: largeur estimée (7.2px/char monospace 12px) pour le
          // scroll horizontal — pas de mesure de layout coûteuse sur les gros
          // fichiers. À remplacer par un TextPainter si les lignes débordent.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                MediaQuery.sizeOf(context).width,
                lines.fold<int>(0, (m, l) => l.length > m ? l.length : m) * 7.2 + 60,
              ),
              child: codeList,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonTree() {

    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 100 + (index % 3) * 40.0,
                height: 14,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(10, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: index % 2 == 0 ? 200 : 300,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

class _TreeFolder extends StatelessWidget {
  final String title;
  final int depth;

  const _TreeFolder({required this.title, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 4, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _TreeFile extends StatelessWidget {
  final String title;
  final int depth;
  final bool isSelected;
  final VoidCallback onTap;

  // Bug #3 : isSelected en param → le widget peut rester const dans les cas
  // non-sélectionnés, évite les rebuilds inutiles sur le reste de la liste.
  const _TreeFile({
    required this.title,
    required this.depth,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? scheme.primary.withValues(alpha: 0.12) : null,
        padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 15,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
