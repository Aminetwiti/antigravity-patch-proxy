import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/protocol/daemon_api.dart';
import '../../widgets/custom_dropdown_overlay.dart';
import 'git_commit_dialog.dart';
import 'package:mobile/theme/app_colors.dart';

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
  // Workspace résolu en chemin absolu pour le daemon (resolvePath).
  String _workspaceResolved = '.';
  // Grep workspace (P5) : recherche contenu+noms côté daemon.
  final TextEditingController _grepController = TextEditingController();
  final FocusNode _grepFocusNode = FocusNode();
  bool _showGrep = false;
  bool _isGrepLoading = false;
  List<Map<String, dynamic>> _grepResults = [];
  // Filtre d'extension rapide (Axe 2)
  String? _selectedExtensionFilter;
  // Branches Git du workspace (Axe 2)
  List<String> _gitBranches = [];
  String? _currentGitBranch;
  // État Git & conflits (P3)
  bool _inConflict = false;
  List<String> _conflicts = [];

  /// Normalise le workspace en chemin absolu exploitable par le daemon.
  static String resolveWorkspace(String raw) {
    final w = raw.trim();
    if (w.startsWith('file:///')) return w.substring(8);
    if (w.startsWith('file://')) return w.substring(7);
    return w;
  }

  @override
  void initState() {
    super.initState();
    // Le daemon confine list_files/read_file sous une racine ABSOLUE (resolvePath
    // fait filepath.Abs). On envoie donc le workspace en chemin absolu dès le
    // départ : '.', 'workspace/', 'file:///...' → path réel côté PC.
    _workspaceResolved = resolveWorkspace(widget.workspacePath);
    _loadFiles();
    _loadGitBranches();
    _loadGitState();
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
    _grepController.dispose();
    super.dispose();
  }

  // Basename réel du workspace (nom du dossier, pas le path complet).
  String get _workspaceLabel {
    final p = widget.workspacePath.trim();
    if (p.isEmpty || p == '.') return 'Workspace';
    final cleaned = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final i = cleaned.lastIndexOf(RegExp(r'[/\\]'));
    return i >= 0 ? cleaned.substring(i + 1) : cleaned;
  }

  Future<void> _loadFiles() async {
    if (widget.api == null) {
      if (mounted) {
        setState(() {
          _isLoadingTree = false;
          _loadError = null;
        });
      }
      return;
    }
    try {
      final res = await widget.api!.listFiles(_workspaceResolved);
      if (mounted) {
        setState(() {
          final rawFiles = res['files'] ?? (res['data'] is Map ? res['data']['files'] : null);
          _files = (rawFiles is List)
              ? rawFiles.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
              : <Map<String, dynamic>>[];
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

  /// Charge les branches Git du workspace (Axe 2). La branche courante est
  /// déduite de la présence d'un '*' en tête (git branch -a).
  Future<void> _loadGitBranches() async {
    if (widget.api == null) return;
    try {
      final branches = await widget.api!.listGitBranches(
        workspacePath: _workspaceResolved,
      );
      String? current;
      for (final b in branches) {
        if (b.startsWith('*')) {
          current = b.substring(1).trim();
          break;
        }
      }
      if (mounted) {
        setState(() {
          _gitBranches = branches
              .map((b) => b.replaceFirst(RegExp(r'^\*\s*'), '').trim())
              .where((b) => b.isNotEmpty)
              .toList();
          _currentGitBranch = current ?? (_gitBranches.isNotEmpty ? _gitBranches.first : null);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gitBranches = [];
          _currentGitBranch = null;
        });
      }
    }
  }

  /// Charge l'état VCS / Git complet (conflits, modifications indexées).
  Future<void> _loadGitState() async {
    if (widget.api == null) return;
    try {
      final state = await widget.api!.getGitState(
        workspacePath: _workspaceResolved,
      );
      if (mounted) {
        // VCS wire: {conflictState: {inConflict: bool, conflicts: [{path:...}]}}
        // Some paths flatten this to {inConflict: bool, conflicts: [...]}
        final conflictState = state['conflictState'] is Map
            ? Map<String, dynamic>.from(state['conflictState'] as Map)
            : state;
        final conflictList = <String>[];
        final rawConflicts = conflictState['conflicts'];
        if (rawConflicts is List) {
          for (final c in rawConflicts) {
            if (c is Map && c['path'] != null) {
              conflictList.add(c['path'].toString());
            } else if (c is String) {
              conflictList.add(c);
            }
          }
        }
        final bool isConflict =
            conflictState['inConflict'] == true ||
            state['inConflict'] == true ||
            conflictList.isNotEmpty;

        setState(() {
          _inConflict = isConflict;
          _conflicts = conflictList;
          if (state['currentRef'] is String &&
              (state['currentRef'] as String).isNotEmpty) {
            _currentGitBranch = state['currentRef'] as String;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFile(String path) async {
    setState(() {
      _selectedFilePath = path;
      _isLoadingCode = true;
      _codeContent = '';
    });
    try {
      final res = await widget.api!.readFile(
        path,
        workspacePath: _workspaceResolved,
      );
      if (mounted) {
        setState(() {
          final rawContent = res['content'] ?? res['text'] ?? (res['data'] is Map ? (res['data']['content'] ?? res['data']['text']) : null);
          _codeContent = rawContent?.toString() ?? '';
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

  /// Partage / exportation du fichier ouvert via Share.shareXFiles (P7).
  Future<void> _shareFile() async {
    if (_selectedFilePath.isEmpty || _isLoadingCode) return;
    try {
      final fileName = _selectedFilePath.split('/').last.split('\\').last;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(_codeContent);
      await Share.shareXFiles([XFile(tempFile.path)], text: 'Fichier $fileName depuis Antigravity Workspace');
    } catch (_) {
      await Share.share(_codeContent, subject: _selectedFilePath.split('/').last);
    }
  }

  /// Grep workspace : délègue au daemon (search_files), résultats tapables.
  /// On ferme le drawer si ouvert (mobile) puis on charge le fichier.
  Future<void> _searchInWorkspace() async {
    final query = _grepController.text.trim();
    if (query.isEmpty || widget.api == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isGrepLoading = true;
      _grepResults = [];
    });
    try {
      final res = await widget.api!.searchFiles(_workspaceResolved, query);
      if (mounted) {
        setState(() {
          final rawResults = res['results'] ?? res['matches'] ?? (res['data'] is Map ? (res['data']['results'] ?? res['data']['matches']) : null);
          _grepResults = (rawResults is List)
              ? rawResults.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
              : <Map<String, dynamic>>[];
          _isGrepLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _grepResults = [];
          _isGrepLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recherche impossible : $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openGrepResult(String path, int? line) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
    _loadFile(path);
    // Retour au fichier si l'utilisateur est dans l'onglet Grep :
    // l'aperçu code est prioritaire (le panneau reste accessible via l'icône).
    if (_showGrep && _selectedFilePath == path) {
      setState(() => _showGrep = false);
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
            border: Border(
              right: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
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
                      Icon(
                        Icons.folder_open,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _workspaceLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_inConflict) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'CONFLIT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                      if (_currentGitBranch != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.alt_route,
                                size: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _currentGitBranch!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_inConflict)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Conflits Git (${_conflicts.length})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_conflicts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ..._conflicts.take(3).map((c) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: InkWell(
                            onTap: () {
                              final scaffold = Scaffold.maybeOf(context);
                              if (scaffold != null && scaffold.isDrawerOpen) {
                                scaffold.closeDrawer();
                              }
                              _loadFile(c);
                            },
                            child: Text(
                              '• $c',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.onErrorContainer,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              // Bug #5 : barre de recherche substring.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    suffixIcon:
                        _searchQuery.isNotEmpty
                            ? IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 14,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                              tooltip: 'Effacer la recherche',
                              onPressed: () => _searchController.clear(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            )
                            : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              // Filtres rapides par extension (Axe 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildFilterChip(null, 'Tout', Icons.all_inclusive_outlined),
                    _buildFilterChip('.dart', 'Dart'),
                    _buildFilterChip('.go', 'Go'),
                    _buildFilterChip('.ts', 'TS'),
                    _buildFilterChip('.json', 'JSON'),
                    _buildFilterChip('.md', 'MD'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _buildFileStats(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              Expanded(
                child:
                    _isLoadingTree
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
            actions: [
              IconButton(
                icon: const Icon(Icons.commit_outlined, size: 20),
                tooltip: 'Créer un commit Git (IA)',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final msg = await GitCommitDialog.show(
                    context,
                    api: widget.api,
                    workspacePath: _workspaceResolved,
                  );
                  if (msg != null && mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Message de commit prêt :\n$msg'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.manage_search_rounded,
                  size: 20,
                  color:
                      _showGrep
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Rechercher dans le workspace (grep)',
                onPressed: () {
                  setState(() {
                    _showGrep = !_showGrep;
                    if (!_showGrep) _grepResults = [];
                  });
                  if (_showGrep) {
                    // Autofocus après le build du panneau.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _grepController.text.isEmpty) {
                        FocusScope.of(context).requestFocus(_grepFocusNode);
                      }
                    });
                  }
                },
              ),
            ],
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Row(
                        children: [
                          Icon(
                            _selectedFilePath.isEmpty
                                ? Icons.folder_open_outlined
                                : Icons.description_outlined,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message:
                                  _selectedFilePath.isEmpty
                                      ? 'Sélectionnez un fichier'
                                      : _selectedFilePath,
                              child: Text(
                                _selectedFilePath.isEmpty
                                    ? 'Sélectionnez un fichier'
                                    : _selectedFilePath,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      _selectedFilePath.isEmpty
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant
                                          : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _selectedFilePath.endsWith('.png') ||
                                      _selectedFilePath.endsWith('.jpg') ||
                                      _selectedFilePath.endsWith('.svg')
                                  ? Icons.image_search_outlined
                                  : Icons.copy_all_outlined,
                              size: 16,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            tooltip:
                                _selectedFilePath.endsWith('.png') ||
                                        _selectedFilePath.endsWith('.jpg') ||
                                        _selectedFilePath.endsWith('.svg')
                                    ? 'Copier l\'image'
                                    : 'Copier le contenu',
                            onPressed:
                                _selectedFilePath.isEmpty || _isLoadingCode
                                    ? null
                                    : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      await Clipboard.setData(
                                        ClipboardData(text: _codeContent),
                                      );
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _selectedFilePath.endsWith(
                                                      '.png',
                                                    ) ||
                                                    _selectedFilePath.endsWith(
                                                      '.jpg',
                                                    ) ||
                                                    _selectedFilePath.endsWith(
                                                      '.svg',
                                                    )
                                                ? 'Image copiée dans le presse-papier !'
                                                : 'Contenu copié : ${_selectedFilePath.split('/').last}',
                                          ),
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
                              color:
                                  _showFindBar
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Rechercher dans le fichier (Cmd+F)',
                            onPressed:
                                _selectedFilePath.isEmpty
                                    ? null
                                    : () => setState(() {
                                      _showFindBar = !_showFindBar;
                                      if (!_showFindBar) {
                                        _findController.clear();
                                      }
                                    }),
                          ),
                          // Share file (P7)
                          IconButton(
                            icon: Icon(
                              Icons.share_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Partager le fichier',
                            onPressed:
                                _selectedFilePath.isEmpty || _isLoadingCode
                                    ? null
                                    : _shareFile,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Find-in-page bar (toggle via icône loupe)
                    if (_showFindBar)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _findController,
                                autofocus: true,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Trouver dans le fichier...',
                                  hintStyle: TextStyle(
                                    fontSize: 12.5,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    size: 16,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  filled: true,
                                  fillColor:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_findQuery.isNotEmpty)
                              Text(
                                '${_countMatches(_codeContent, _findQuery)} rés.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Fermer la recherche',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed:
                                  () => setState(() {
                                    _showFindBar = false;
                                    _findController.clear();
                                  }),
                            ),
                          ],
                        ),
                      ),
                    // Grep workspace : panneau de résultats en remplacement du
                    // viewer de code quand _showGrep est actif.
                    if (_showGrep)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          child: _buildGrepPanel(),
                        ),
                      )
                    else
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          child:
                              _isLoadingCode
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
    final scheme = Theme.of(context).colorScheme;
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
            _buildWorkspaceItem(_workspaceLabel, true, scheme),
            Divider(color: scheme.outlineVariant, height: 1),
            _buildWorkspaceActionItem(
              Icons.create_new_folder_outlined,
              'New Project',
              scheme,
            ),
            _buildWorkspaceActionItem(
              Icons.bolt_outlined,
              'Quick Start',
              scheme,
            ),
            Divider(color: scheme.outlineVariant, height: 1),
            _buildWorkspaceActionItem(
              Icons.do_disturb_alt_outlined,
              'No Project',
              scheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceItem(
    String title,
    bool isSelected,
    ColorScheme scheme,
  ) {
    return InkWell(
      onTap: () {
        CustomDropdownOverlay.hide();
        // Here we would actually change the workspace
      },
      child: Container(
        color: isSelected ? scheme.surfaceContainerHighest : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: scheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceActionItem(
    IconData icon,
    String title,
    ColorScheme scheme,
  ) {
    return InkWell(
      onTap: () {
        CustomDropdownOverlay.hide();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bug #3 : perf — construit la liste une seule fois, filtrée par _searchQuery.
  /// Puce de filtre d'extension rapide (Axe 2).
  Widget _buildFilterChip(String? ext, String label, [IconData? icon]) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedExtensionFilter == ext;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 10.5)),
        ],
      ),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        fontSize: 10.5,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
      side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => setState(() {
        _selectedExtensionFilter = selected ? null : ext;
      }),
    );
  }

  /// Compteur fichiers/dossiers affichés (Axe 2).
  String _buildFileStats() {
    final files = _files.where((f) => f['isDir'] != true).length;
    final dirs = _files.length - files;
    final active = _selectedExtensionFilter;
    final base = '$files fichiers · $dirs dossiers';
    if (active == null) return base;
    final count = _files.where((f) {
      if (f['isDir'] == true) return false;
      return (f['name'] as String).toLowerCase().endsWith(active);
    }).length;
    return '$count · $active · $base';
  }

  Widget _buildFileList() {
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Espace de travail vide',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aucun fichier à afficher dans ce répertoire.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    var filtered =
        _searchQuery.isEmpty
            ? _files
            : _files.where((f) {
              final name = (f['name'] as String).toLowerCase();
              return name.contains(_searchQuery);
            }).toList();
    if (_selectedExtensionFilter != null) {
      filtered = filtered.where((f) {
        if (f['isDir'] == true) return false;
        final name = (f['name'] as String).toLowerCase();
        return name.endsWith(_selectedExtensionFilter!);
      }).toList();
    }

    if (filtered.isEmpty) {
      final hasFilters = _searchQuery.isNotEmpty || _selectedExtensionFilter != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _searchQuery.isEmpty
                    ? (_selectedExtensionFilter != null
                        ? 'Aucun fichier «\u00a0$_selectedExtensionFilter\u00a0»'
                        : 'Aucun fichier dans ce workspace')
                    : 'Aucun résultat pour «\u00a0$_searchQuery\u00a0»',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasFilters) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _selectedExtensionFilter = null;
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Réinitialiser les filtres', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
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
            Icon(
              Icons.error_outline,
              size: 32,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Impossible de charger les fichiers',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoadingTree = true;
                  _loadError = null;
                });
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

  // Find-in-page : comptage des occurrences (insensible à la casse).
  // ponytail: allMatches() d'une RegExp — stdlib, zéro allocation custom.
  int _countMatches(String content, String query) {
    if (query.isEmpty) return 0;
    return RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(content).length;
  }

  /// Panneau grep : barre de recherche + résultats (fichier:ligne + snippet).
  Widget _buildGrepPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _grepController,
                  focusNode: _grepFocusNode,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchInWorkspace(),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans le workspace…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    suffixIcon:
                        _grepController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Effacer',
                              onPressed: () {
                                _grepController.clear();
                                setState(() => _grepResults = []);
                              },
                            )
                            : null,
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isGrepLoading ? null : _searchInWorkspace,
                icon:
                    _isGrepLoading
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.search, size: 16),
                label: const Text('Chercher'),
              ),
            ],
          ),
        ),
        if (_isGrepLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_grepResults.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _grepController.text.trim().isEmpty
                    ? 'Saisis un terme puis touche Chercher.'
                    : 'Aucun résultat pour «\u00a0${_grepController.text.trim()}\u00a0»',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _grepResults.length,
              itemBuilder: (context, index) {
                final r = _grepResults[index];
                final path = (r['path'] as String?) ?? '';
                final line = (r['line'] as num?)?.toInt();
                final snippet = (r['snippet'] as String?) ?? '';
                final isNameMatch = r['match'] == 'name';
                return _SearchResultTile(
                  path: path,
                  line: line,
                  snippet: snippet,
                  isNameMatch: isNameMatch,
                  onTap: () => _openGrepResult(path, line),
                );
              },
            ),
          ),
      ],
    );
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
                Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Aperçu Vectoriel SVG',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minWidth: 200, minHeight: 200),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(child: SelectableText(_codeContent)),
            ),
          ),
        ],
      );
    }

    // Fichiers binaires (images, audio, vidéo) : pas de numéros de ligne
    final isBinary =
        _selectedFilePath.endsWith('.png') ||
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Fichier binaire — numéros de ligne masqués',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Tronquage de sécurité pour éviter les plantages sur les sorties > 2000 lignes ou > 50 000 caractères
    final bool isLargeFile = _codeContent.length > 50000;
    final safeContent =
        isLargeFile ? _codeContent.substring(0, 50000) : _codeContent;
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
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
          spans.add(
            TextSpan(
              text: line.substring(match.start, match.end),
              style: TextStyle(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.30),
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
          cursor = match.end;
        }
        if (cursor < line.length) {
          spans.add(TextSpan(text: line.substring(cursor)));
        }
        return RichText(text: TextSpan(style: textStyle, children: spans));
      },
    );

    return Column(
      children: [
        if (isLargeFile || rawLines.length > 2000)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.10),
            child: Text(
              isLargeFile && rawLines.length > 2000
                  ? 'Fichier volumineux — ${rawLines.length} lignes, 2000 affichées (contenu tronqué à 50 000 caractères)'
                  : isLargeFile
                  ? 'Fichier volumineux — contenu tronqué à 50 000 caractères'
                  : 'Fichier volumineux — ${rawLines.length} lignes, 2000 affichées',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
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
                lines.fold<int>(0, (m, l) => l.length > m ? l.length : m) *
                        7.2 +
                    60,
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 8.0 + depth * 14,
        top: 4,
        bottom: 4,
        right: 8,
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
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

  const _TreeFile({
    required this.title,
    required this.depth,
    required this.onTap,
    this.isSelected = false,
  });

  IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.flutter_dash_outlined;
    if (lower.endsWith('.go')) return Icons.code_rounded;
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.toml')) {
      return Icons.settings_suggest_outlined;
    }
    if (lower.endsWith('.md') || lower.endsWith('.txt')) {
      return Icons.article_outlined;
    }
    if (lower.endsWith('.sh') ||
        lower.endsWith('.bat') ||
        lower.endsWith('.ps1')) {
      return Icons.terminal_rounded;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _colorForName(String name, ColorScheme scheme) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return const Color(0xFF29B6F6);
    if (lower.endsWith('.go')) return const Color(0xFF00ADD8);
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return const Color(0xFFEAB308);
    }
    if (lower.endsWith('.md')) return const Color(0xFFA855F7);
    if (lower.endsWith('.sh') || lower.endsWith('.bat')) {
      return const Color(0xFF22C55E);
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.svg')) {
      return const Color(0xFFEC4899);
    }
    return isSelected ? scheme.primary : scheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: EdgeInsets.only(
          left: 8.0 + depth * 14,
          top: 4,
          bottom: 4,
          right: 8,
        ),
        decoration: BoxDecoration(
          color:
              isSelected ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border:
              isSelected
                  ? Border.all(color: scheme.outlineVariant, width: 1)
                  : null,
        ),
        child: Row(
          children: [
            Icon(
              _iconForName(title),
              size: 14,
              color: _colorForName(title, scheme),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  color:
                      isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Résultat de recherche grep : chemin (avec ligne) + snippet du match.
class _SearchResultTile extends StatelessWidget {
  final String path;
  final int? line;
  final String snippet;
  final bool isNameMatch;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.path,
    required this.line,
    required this.snippet,
    required this.isNameMatch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNameMatch
                      ? Icons.folder_copy_outlined
                      : Icons.description_outlined,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line != null ? '$path:$line' : path,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                snippet,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
