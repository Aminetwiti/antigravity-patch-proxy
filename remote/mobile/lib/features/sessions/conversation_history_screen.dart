import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/core/protocol/workspace_path.dart';
import 'package:mobile/theme/app_colors.dart';
import 'display_options.dart';

/// Écran Conversation History (Antigravity 2.0)
/// Affiche la liste complète de toutes les conversations avec recherche en temps réel,
/// filtrage par workspace/projet, indicateurs de sessions actives/en cours et sélection rapide.
class ConversationHistoryScreen extends StatefulWidget {
  final List<CascadeSession> sessions;
  final String activeSessionId;
  final Function(String sessionId) onSessionSelected;
  final VoidCallback? onRefresh;
  final Function(String sessionId)? onDeleteSession;

  const ConversationHistoryScreen({
    super.key,
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionSelected,
    this.onRefresh,
    this.onDeleteSession,
  });

  @override
  State<ConversationHistoryScreen> createState() => _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedWorkspaceFilter; // null = all workspaces

  SessionGroupBy _groupBy = SessionGroupBy.project;
  SessionSortBy _sortBy = SessionSortBy.lastUpdated;
  SessionSubtitle _subtitle = SessionSubtitle.worktree;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filtrer STRICTEMENT les sessions disponibles (non archivées et non supprimées)
    final available = widget.sessions.where((s) => s.isAvailable && s.id.isNotEmpty).toList();

    // Extraire tous les workspaces distincts pour le filtre
    final workspaces = available
        .map((s) => WorkspacePath.displayName(s.workspacePath))
        .toSet()
        .toList()
      ..sort();

    // Appliquer le filtre par workspace
    var filtered = available;
    if (_selectedWorkspaceFilter != null) {
      filtered = filtered.where((s) => WorkspacePath.displayName(s.workspacePath) == _selectedWorkspaceFilter).toList();
    }

    // Appliquer la recherche textuelle
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) {
        final title = s.title.toLowerCase();
        final ws = WorkspacePath.displayName(s.workspacePath).toLowerCase();
        return title.contains(_searchQuery) || ws.contains(_searchQuery);
      }).toList();
    }

    // Tri dynamique selon Display Options
    filtered = sortSessions(sessions: filtered, sortBy: _sortBy);

    // Groupement dynamique selon Display Options
    final groupedSessions = groupSessions(
      sessions: filtered,
      groupBy: _groupBy,
    );

    // Flatten for list rendering with headers
    final List<dynamic> displayItems = [];
    if (_groupBy == SessionGroupBy.none) {
      displayItems.addAll(filtered);
    } else {
      for (final entry in groupedSessions.entries) {
        if (entry.value.isNotEmpty) {
          displayItems.add(entry.key);
          displayItems.addAll(entry.value);
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1012),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.inkPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
        ),
        title: const Text(
          'Conversation History',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          if (widget.onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.inkSecondary),
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.onRefresh!();
              },
              tooltip: 'Actualiser',
            ),
          DisplayOptionsMenuButton(
            selectedGroupBy: _groupBy,
            selectedSortBy: _sortBy,
            selectedSubtitle: _subtitle,
            isFilterOpen: true,
            onGroupByChanged: (val) => setState(() => _groupBy = val),
            onSortByChanged: (val) => setState(() => _sortBy = val),
            onSubtitleChanged: (val) => setState(() => _subtitle = val),
            onToggleFilter: () {
              setState(() {
                if (_searchQuery.isNotEmpty || _selectedWorkspaceFilter != null) {
                  _searchController.clear();
                  _selectedWorkspaceFilter = null;
                }
              });
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Search & Filter Bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1D22),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: const Color(0xFF2C2F36), width: 1),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                        cursorColor: AppColors.accentBlue,
                        decoration: InputDecoration(
                          hintText: 'Search conversations...',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF636D83)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF636D83)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF636D83)),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Bouton Filtre par projet
                  PopupMenuButton<String>(
                    tooltip: 'Filtrer par projet',
                    color: AppColors.surfaceRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: const BorderSide(color: AppColors.borderStrong),
                    ),
                    icon: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _selectedWorkspaceFilter != null
                            ? AppColors.accentBlue.withValues(alpha: 0.15)
                            : const Color(0xFF1B1D22),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: _selectedWorkspaceFilter != null
                              ? AppColors.accentBlue
                              : const Color(0xFF2C2F36),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: _selectedWorkspaceFilter != null
                            ? AppColors.accentBlue
                            : AppColors.inkSecondary,
                      ),
                    ),
                    onSelected: (ws) {
                      setState(() {
                        _selectedWorkspaceFilter = ws.isEmpty ? null : ws;
                      });
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: '',
                        child: Text(
                          'Tous les projets',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkPrimary),
                        ),
                      ),
                      const PopupMenuDivider(),
                      ...workspaces.map(
                        (ws) => PopupMenuItem<String>(
                          value: ws,
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 14, color: AppColors.inkMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ws,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _selectedWorkspaceFilter == ws
                                        ? AppColors.accentBlue
                                        : AppColors.inkPrimary,
                                    fontWeight: _selectedWorkspaceFilter == ws
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedWorkspaceFilter == ws)
                                const Icon(Icons.check_rounded, size: 16, color: AppColors.accentBlue),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Badge de filtre actif (si présent)
            if (_selectedWorkspaceFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 13, color: AppColors.accentBlue),
                          const SizedBox(width: 6),
                          Text(
                            _selectedWorkspaceFilter!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.accentBlue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => setState(() => _selectedWorkspaceFilter = null),
                            child: const Icon(Icons.close_rounded, size: 13, color: AppColors.accentBlue),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // ── Session List ────────────────────────────────────────────────
            Expanded(
              child: displayItems.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemCount: displayItems.length,
                      itemBuilder: (context, index) {
                        final item = displayItems[index];

                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_outlined, size: 13, color: AppColors.inkMuted),
                                const SizedBox(width: 6),
                                Text(
                                  item,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkMuted,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final session = item as CascadeSession;
                        final isActive = session.id == widget.activeSessionId;
                        final isRunning = session.isRunning;
                        final wsName = WorkspacePath.displayName(session.workspacePath);

                        return _ConversationHistoryRow(
                          session: session,
                          workspaceName: wsName,
                          isActive: isActive,
                          isRunning: isRunning,
                          showSubtitle: _subtitle == SessionSubtitle.worktree,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onSessionSelected(session.id);
                            Navigator.of(context).pop();
                          },
                          onDelete: widget.onDeleteSession != null
                              ? () => widget.onDeleteSession!(session.id)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 42, color: AppColors.inkMuted),
            const SizedBox(height: 14),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Aucune conversation pour "$_searchQuery"'
                  : 'Aucune conversation disponible',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Les sessions archivées ou supprimées sont automatiquement filtrées.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isNotEmpty || _selectedWorkspaceFilter != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _selectedWorkspaceFilter = null;
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.accentBlue),
                label: const Text('Effacer les filtres', style: TextStyle(fontSize: 12, color: AppColors.accentBlue)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationHistoryRow extends StatelessWidget {
  final CascadeSession session;
  final String workspaceName;
  final bool isActive;
  final bool isRunning;
  final bool showSubtitle;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ConversationHistoryRow({
    required this.session,
    required this.workspaceName,
    required this.isActive,
    required this.isRunning,
    this.showSubtitle = true,
    required this.onTap,
    this.onDelete,
  });

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1D22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B3E47),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2C2F36)),
              ListTile(
                leading: const Icon(Icons.copy_rounded, size: 18, color: AppColors.inkPrimary),
                title: const Text('Copy Title', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: session.title));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Titre copié'), duration: Duration(seconds: 2)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.tag_rounded, size: 18, color: AppColors.inkPrimary),
                title: const Text('Copy Session ID', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: session.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID de session copié'), duration: Duration(seconds: 2)),
                  );
                },
              ),
              if (onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                  title: const Text('Supprimer la conversation', style: TextStyle(fontSize: 13, color: AppColors.danger)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDelete(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1D22),
        title: const Text('Supprimer la conversation ?', style: TextStyle(fontSize: 15, color: AppColors.inkPrimary)),
        content: Text(
          'Voulez-vous supprimer définitivement "${session.title}" ?',
          style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler', style: TextStyle(color: AppColors.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete?.call();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        onSecondaryTap: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: const Color(0xFF1E2127),
        splashColor: AppColors.accentBlue.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Colonne Titre + Workspace
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title.isEmpty ? 'Untitled Conversation' : session.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? AppColors.inkPrimary : const Color(0xFFE4E4E7),
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showSubtitle) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              workspaceName,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF8F909A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Trailing Status: Active blue dot, Spinner, or relative time
              if (isRunning)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isActive ? AppColors.accentBlue : const Color(0xFF9E9FA9),
                    ),
                  ),
                )
              else if (isActive)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.accentBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentBlue,
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                )
              else if (session.time.isNotEmpty)
                Text(
                  session.time,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                  ),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: Color(0xFF3F424E),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
