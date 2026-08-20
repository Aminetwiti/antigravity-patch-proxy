import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';
import '../../../widgets/skeleton_loader.dart';

/// Modèle représentant un fichier modifié dans la session (avec additions/deletions)
class SessionModifiedFile {
  final String path;
  final int additions;
  final int deletions;
  final String? diffContent;

  const SessionModifiedFile({
    required this.path,
    this.additions = 0,
    this.deletions = 0,
    this.diffContent,
  });

  String get fileName {
    final clean = path.replaceAll('\\', '/');
    final idx = clean.lastIndexOf('/');
    return idx >= 0 ? clean.substring(idx + 1) : clean;
  }

  String get directoryPath {
    final clean = path.replaceAll('\\', '/');
    final idx = clean.lastIndexOf('/');
    return idx >= 0 ? clean.substring(0, idx) : '';
  }
}

/// Vue "Review" de session identique au Desktop IDE Antigravity 2.0
class SessionReviewView extends StatefulWidget {
  final List<SessionModifiedFile> files;
  final Function(SessionModifiedFile file) onOpenFileDiff;
  final VoidCallback? onExpandAll;
  final VoidCallback? onSplitDiffView;
  final bool isLoading;

  /// P5 : actions groupées — accepter / rejeter l'ensemble des modifications.
  /// Les callbacks restent optionnels : si absents, la barre d'actions est
  /// masquée (l'écran parent décide si le daemon peut les appliquer).
  final VoidCallback? onAcceptAll;
  final VoidCallback? onDiscardAll;

  const SessionReviewView({
    super.key,
    required this.files,
    required this.onOpenFileDiff,
    this.onExpandAll,
    this.onSplitDiffView,
    this.isLoading = false,
    this.onAcceptAll,
    this.onDiscardAll,
  });

  @override
  State<SessionReviewView> createState() => _SessionReviewViewState();
}

class _SessionReviewViewState extends State<SessionReviewView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchOpen = false;
  bool _groupByFolder = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    if (lower.endsWith('.sh') || lower.endsWith('.bat') || lower.endsWith('.ps1')) {
      return Icons.terminal_rounded;
    }
    if (lower.endsWith('.gitignore') || lower.startsWith('.git')) {
      return Icons.alt_route_rounded;
    }
    if (lower.endsWith('.js') || lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.jsx')) {
      return Icons.javascript_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _colorForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return const Color(0xFF29B6F6);
    if (lower.endsWith('.go')) return const Color(0xFF00ADD8);
    if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml') || lower.endsWith('.toml')) {
      return const Color(0xFFEAB308);
    }
    if (lower.endsWith('.md')) return const Color(0xFFA855F7);
    if (lower.endsWith('.sh') || lower.endsWith('.bat')) return const Color(0xFF22C55E);
    if (lower.endsWith('.gitignore')) return const Color(0xFFF43F5E);
    if (lower.endsWith('.ts') || lower.endsWith('.tsx')) return const Color(0xFF3178C6);
    if (lower.endsWith('.js') || lower.endsWith('.jsx')) return const Color(0xFFF7DF1E);
    return const Color(0xFF9E9FA9);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = widget.files.where((f) {
      if (_searchQuery.isEmpty) return true;
      return f.path.toLowerCase().contains(_searchQuery);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── En-tête : Titre "Review (N)" + Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              Text(
                'Review',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF23262D) : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.files.length}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.inkSecondary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),

              // ⋮ Options menu
              PopupMenuButton<String>(
                tooltip: 'Options de revue',
                color: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainer,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant, width: 1),
                ),
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                onSelected: (val) {
                  if (val == 'split') {
                    widget.onSplitDiffView?.call();
                  } else if (val == 'expand') {
                    widget.onExpandAll?.call();
                  } else if (val == 'copy_paths') {
                    final paths = widget.files.map((f) => f.path).join('\n');
                    Clipboard.setData(ClipboardData(text: paths));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Liste des chemins copiée'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'split',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.splitscreen_rounded, size: 15, color: scheme.onSurface),
                        const SizedBox(width: 8),
                        Text('View Split Diff', style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'expand',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.unfold_more_rounded, size: 15, color: scheme.onSurface),
                        const SizedBox(width: 8),
                        Text('Expand All', style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'copy_paths',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 15, color: scheme.onSurface),
                        const SizedBox(width: 8),
                        Text('Copy File Paths', style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                      ],
                    ),
                  ),
                ],
              ),

              // 🔍 Search toggle
              IconButton(
                icon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: _isSearchOpen ? scheme.primary : scheme.onSurfaceVariant,
                ),
                tooltip: 'Rechercher un fichier modifié',
                onPressed: () {
                  setState(() {
                    _isSearchOpen = !_isSearchOpen;
                    if (!_isSearchOpen) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),

              // ☰ Group/View toggle
              IconButton(
                icon: Icon(
                  _groupByFolder ? Icons.view_list_rounded : Icons.folder_outlined,
                  size: 18,
                  color: _groupByFolder ? scheme.primary : scheme.onSurfaceVariant,
                ),
                tooltip: _groupByFolder ? 'Vue liste plate' : 'Grouper par dossier',
                onPressed: () => setState(() => _groupByFolder = !_groupByFolder),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // ── Barre de recherche conditionnelle
        if (_isSearchOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant, width: 1),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                cursorColor: scheme.primary,
                decoration: InputDecoration(
                  hintText: 'Filtrer les modifications...',
                  hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: scheme.onSurfaceVariant),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 14, color: scheme.onSurfaceVariant),
                          tooltip: 'Effacer la recherche',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),
        // P5 : actions groupées (Accepter tout / Tout rejeter) — uniquement
        // quand des fichiers sont listés et que l'écran parent fournit les
        // callbacks d'application.
        if (widget.files.isNotEmpty &&
            (widget.onAcceptAll != null || widget.onDiscardAll != null)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(
              children: [
                if (widget.onAcceptAll != null)
                  Expanded(
                    child: _BulkActionChip(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Tout accepter',
                      color: const Color(0xFF22C55E),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onAcceptAll?.call();
                      },
                    ),
                  ),
                if (widget.onAcceptAll != null && widget.onDiscardAll != null)
                  const SizedBox(width: 8),
                if (widget.onDiscardAll != null)
                  Expanded(
                    child: _BulkActionChip(
                      icon: Icons.undo_rounded,
                      label: 'Tout rejeter',
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onDiscardAll?.call();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],

        const Divider(color: Color(0xFF212328), height: 1),

        // ── Liste des fichiers modifiés
        Expanded(
          child: widget.isLoading && widget.files.isEmpty
              ? SkeletonLoader(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    physics: const NeverScrollableScrollPhysics(),
                    children: const [
                      SkeletonDiffFileItem(),
                      Divider(color: Color(0xFF1B1D22), height: 1, indent: 14, endIndent: 14),
                      SkeletonDiffFileItem(),
                      Divider(color: Color(0xFF1B1D22), height: 1, indent: 14, endIndent: 14),
                      SkeletonDiffFileItem(),
                      Divider(color: Color(0xFF1B1D22), height: 1, indent: 14, endIndent: 14),
                      SkeletonDiffFileItem(),
                    ],
                  ),
                )
              : filtered.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.check_circle_outline_rounded,
                                size: 32,
                                color: const Color(0xFF5E606A),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Aucun fichier pour "$_searchQuery"'
                                    : 'Aucun fichier modifié dans cette session',
                                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(
                    color: Color(0xFF1B1D22),
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                  ),
                  itemBuilder: (context, index) {
                    final file = filtered[index];
                    return _ChangedFileRow(
                      file: file,
                      icon: _iconForName(file.fileName),
                      iconColor: _colorForName(file.fileName),
                      onTap: () => widget.onOpenFileDiff(file),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChangedFileRow extends StatelessWidget {
  final SessionModifiedFile file;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _ChangedFileRow({
    required this.file,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      hoverColor: isDark ? const Color(0xFF1E2127) : scheme.surfaceContainerHighest,
      splashColor: scheme.primary.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
              // Icône du langage / fichier
              Icon(
                icon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 9),

              // Nom du fichier + chemin relatif
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        file.fileName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFE4E4E7) : scheme.onSurface,
                          letterSpacing: -0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (file.directoryPath.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          file.directoryPath,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF8F909A) : scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Badges Additions / Deletions: +X -Y
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (file.additions > 0 || file.deletions == 0)
                    Text(
                      '+${file.additions}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                  if (file.deletions > 0) ...[
                    const SizedBox(width: 5),
                    Text(
                      '-${file.deletions}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: Color(0xFF5E606A),
              ),
            ],
          ),
        ),
      );
  }
}

/// P5 : chip d'action groupée (Accepter / Rejeter) — bouton large, tactile.
class _BulkActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
