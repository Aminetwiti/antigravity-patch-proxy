import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/protocol/messages.dart';
import '../../core/protocol/workspace_path.dart';
import 'package:mobile/theme/app_colors.dart';
import 'display_options.dart';

class LeftSidebarDrawer extends StatefulWidget {
  final String activeSessionId;
  final Function(String sessionId) onSessionSelected;
  final VoidCallback onNewConversation;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDiscover;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onConversationHistory;
  final VoidCallback? onScheduledTasks;
  final List<CascadeSession>? sessions;
  final List<ProjectItem>? projects;
  final bool isConnected;
  final VoidCallback onToggleConnection;

  const LeftSidebarDrawer({
    super.key,
    required this.activeSessionId,
    required this.onSessionSelected,
    required this.onNewConversation,
    this.onOpenSettings,
    this.onDiscover,
    this.onOpenWorkspace,
    this.onConversationHistory,
    this.onScheduledTasks,
    this.sessions,
    this.projects,
    this.isConnected = false,
    required this.onToggleConnection,
    this.onDeleteSession,
    this.onRenameSession,
    this.onExportSession,
  });

  final Function(String id)? onDeleteSession;
  final Function(String id, String newTitle)? onRenameSession;
  final Function(CascadeSession session)? onExportSession;

  @override
  State<LeftSidebarDrawer> createState() => _LeftSidebarDrawerState();
}

class _LeftSidebarDrawerState extends State<LeftSidebarDrawer> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _collapsedFolders = {};
  bool _isFilterOpen = false;
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  SessionGroupBy _groupBy = SessionGroupBy.project;
  SessionSortBy _sortBy = SessionSortBy.lastUpdated;
  SessionSubtitle _subtitle = SessionSubtitle.worktree;

  // P4 : sessions épinglées — local-only via SharedPreferences (jamais
  // synchronisées avec le daemon).
  final Set<String> _pinnedIds = {};

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('pinned_session_ids') ?? const [];
    if (!mounted) return;
    setState(() {
      _pinnedIds
        ..clear()
        ..addAll(ids);
    });
  }

  void _togglePin(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_pinnedIds.remove(id)) _pinnedIds.add(id);
    });
    // ponytail: fire-and-forget, SharedPreferences garde le dernier état écrit.
    SharedPreferences.getInstance().then((prefs) =>
        prefs.setStringList('pinned_session_ids', _pinnedIds.toList()));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSessions = widget.sessions ?? [];
    final availableSessions = allSessions
        .where((s) => s.isAvailable && s.id.isNotEmpty)
        .where((s) {
          if (_filterQuery.isEmpty) return true;
          final q = _filterQuery.toLowerCase();
          return s.title.toLowerCase().contains(q) ||
              s.workspacePath.toLowerCase().contains(q);
        })
        .toList();

    final sortedSessions = sortSessions(
      sessions: availableSessions,
      sortBy: _sortBy,
    );

    // P4 : épinglées d'abord (ordre stable — le tri interne est conservé).
    final pinnedFirst = [
      ...sortedSessions.where((s) => _pinnedIds.contains(s.id)),
      ...sortedSessions.where((s) => !_pinnedIds.contains(s.id)),
    ];

    final projectSessions = groupSessions(
      sessions: pinnedFirst,
      groupBy: _groupBy,
      projects: widget.projects,
    );

    final projectNames = projectSessions.keys.toList();

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),

            // ── Top Navigation Bar: Icons [◫ Sidebar toggle] [← Back] [→ Forward]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  _HeaderIconBtn(
                    icon: Icons.dock_outlined,
                    tooltip: 'Masquer la barre',
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconBtn(
                    icon: Icons.arrow_back,
                    tooltip: 'Retour',
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconBtn(
                    icon: Icons.arrow_forward,
                    tooltip: 'Suivant',
                    onTap: () {},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── "+ New Conversation" Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    widget.onNewConversation();
                  },
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1D22),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: const Color(0xFF2C2F36),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add, size: 16, color: AppColors.inkSecondary),
                        SizedBox(width: 10),
                        Text(
                          'New Conversation',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Quick-nav actions (History, Scheduled Tasks)
            _SidebarActionItem(
              icon: Icons.history_rounded,
              label: 'Conversation History',
              isSelected: false,
              onTap: () {
                Navigator.of(context).pop();
                widget.onConversationHistory?.call();
              },
            ),
            _SidebarActionItem(
              icon: Icons.schedule_outlined,
              label: 'Scheduled Tasks',
              isSelected: false,
              onTap: () {
                Navigator.of(context).pop();
                widget.onScheduledTasks?.call();
              },
            ),

            const SizedBox(height: 14),

            // ── Section Header: Projects [display options] [new folder]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _groupBy == SessionGroupBy.project
                        ? 'Projects'
                        : _groupBy == SessionGroupBy.workspace
                            ? 'Workspaces'
                            : _groupBy == SessionGroupBy.status
                                ? 'Status'
                                : 'Conversations',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8F909A),
                    ),
                  ),
                  const Spacer(),
                  DisplayOptionsMenuButton(
                    selectedGroupBy: _groupBy,
                    selectedSortBy: _sortBy,
                    selectedSubtitle: _subtitle,
                    isFilterOpen: _isFilterOpen,
                    onGroupByChanged: (val) => setState(() => _groupBy = val),
                    onSortByChanged: (val) => setState(() => _sortBy = val),
                    onSubtitleChanged: (val) => setState(() => _subtitle = val),
                    onToggleFilter: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _isFilterOpen = !_isFilterOpen;
                        if (!_isFilterOpen) {
                          _filterController.clear();
                          _filterQuery = '';
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  _HeaderIconBtn(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'Ouvrir workspace',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onOpenWorkspace?.call();
                    },
                    size: 15,
                  ),
                ],
              ),
            ),

            if (_isFilterOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _filterController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkPrimary),
                    decoration: InputDecoration(
                      hintText: 'Filtrer les sessions...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      prefixIcon: const Icon(Icons.search, size: 14, color: AppColors.inkMuted),
                      prefixIconConstraints: const BoxConstraints(minWidth: 26),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 12, color: AppColors.inkMuted),
                              tooltip: 'Effacer le filtre',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 20),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filterQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1B1D22),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF2C2F36), width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF2C2F36), width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.accentBlueBright, width: 1),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _filterQuery = val.trim());
                    },
                  ),
                ),
              ),

            const SizedBox(height: 4),

            // ── Workspaces & Sessions Tree
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: false,
                thickness: 3,
                radius: const Radius.circular(2),
                thumbColor: AppColors.borderStrong.withValues(alpha: 0.6),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  children: [
                    if (projectNames.isEmpty)
                      _EmptyState(
                        isConnected: widget.isConnected,
                        onConnect: () {
                          Navigator.of(context).pop();
                          widget.onToggleConnection();
                        },
                      )
                    else
                      ...projectNames.map((proj) {
                        final sessions = projectSessions[proj] ?? [];
                        final isCollapsed = _collapsedFolders.contains(proj);
                        return _WorkspaceFolderSection(
                          folderName: proj,
                          sessions: sessions,
                          isCollapsed: isCollapsed,
                          showSubtitle: _subtitle == SessionSubtitle.worktree,
                          hideHeader: _groupBy == SessionGroupBy.none,
                          activeSessionId: widget.activeSessionId,
                          onToggleCollapse: () {
                            setState(() {
                              if (isCollapsed) {
                                _collapsedFolders.remove(proj);
                              } else {
                                _collapsedFolders.add(proj);
                              }
                            });
                          },
                          onSessionTap: (id) {
                            Navigator.of(context).pop();
                            widget.onSessionSelected(id);
                          },
                          onNewConversation: () {
                            Navigator.of(context).pop();
                            widget.onNewConversation();
                          },
                          onOpenSettings: () {
                            Navigator.of(context).pop();
                            widget.onOpenSettings?.call();
                          },
                          onDeleteSession: widget.onDeleteSession,
                          onRenameSession: widget.onRenameSession,
                          onExportSession: widget.onExportSession,
                          pinnedIds: _pinnedIds,
                          onTogglePin: _togglePin,
                        );
                      }),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            const _Divider(),

            // ── Bottom: Settings + Connection status
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Column(
                children: [
                  _SidebarActionItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onOpenSettings?.call();
                    },
                  ),
                  _ConnectionRow(
                    isConnected: widget.isConnected,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onToggleConnection();
                    },
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

// ── Header Icon Button
class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 17,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(icon, size: size, color: const Color(0xFF8F909A)),
            ),
          ),
        ),
      );
}

// ── Sidebar Action Item (History, Scheduled Tasks, Settings)
class _SidebarActionItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isSelected;

  const _SidebarActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.isSelected = false,
  });

  @override
  State<_SidebarActionItem> createState() => _SidebarActionItemState();
}

class _SidebarActionItemState extends State<_SidebarActionItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF26282E)
                : (_hovered ? const Color(0xFF1E2025) : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFF9E9FA9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFFD4D4D8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Workspace Folder Section (Grouping by folder)
class _WorkspaceFolderSection extends StatefulWidget {
  final String folderName;
  final List<CascadeSession> sessions;
  final bool isCollapsed;
  final bool showSubtitle;
  final bool hideHeader;
  final String activeSessionId;
  final VoidCallback onToggleCollapse;
  final Function(String id) onSessionTap;
  final VoidCallback? onNewConversation;
  final VoidCallback? onOpenSettings;
  final Function(String id)? onDeleteSession;
  final Function(String id, String newTitle)? onRenameSession;
  final Function(CascadeSession session)? onExportSession;

  // P4 : épinglage local
  final Set<String> pinnedIds;
  final ValueChanged<String>? onTogglePin;

  const _WorkspaceFolderSection({
    required this.folderName,
    required this.sessions,
    required this.isCollapsed,
    this.showSubtitle = true,
    this.hideHeader = false,
    required this.activeSessionId,
    required this.onToggleCollapse,
    required this.onSessionTap,
    this.onNewConversation,
    this.onOpenSettings,
    this.onDeleteSession,
    this.onRenameSession,
    this.onExportSession,
    this.pinnedIds = const {},
    this.onTogglePin,
  });

  @override
  State<_WorkspaceFolderSection> createState() => _WorkspaceFolderSectionState();
}

class _WorkspaceFolderSectionState extends State<_WorkspaceFolderSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.sessions.length > 5;
    final visibleSessions = (_showAll || !hasMore)
        ? widget.sessions
        : widget.sessions.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workspace Folder Header (hidden if hideHeader is true)
        if (!widget.hideHeader && widget.folderName.isNotEmpty)
          InkWell(
            onTap: widget.onToggleCollapse,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    size: 15,
                    color: Color(0xFF8F909A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.folderName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFA1A1AA),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // ── Project Options Context Menu (:)
                  PopupMenuButton<String>(
                    tooltip: 'Options du projet',
                    color: const Color(0xFF1B1D22),
                    surfaceTintColor: Colors.transparent,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: const BorderSide(color: Color(0xFF2C2F36), width: 1),
                    ),
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 15,
                      color: Color(0xFF8F909A),
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'copy_name') {
                        Clipboard.setData(ClipboardData(text: widget.folderName));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Nom du projet "${widget.folderName}" copié'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (val == 'settings') {
                        widget.onOpenSettings?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'copy_name',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 14, color: AppColors.inkPrimary),
                            SizedBox(width: 8),
                            Text('Copy Project Name', style: TextStyle(fontSize: 12.5, color: AppColors.inkPrimary)),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'settings',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.settings_outlined, size: 14, color: AppColors.inkPrimary),
                            SizedBox(width: 8),
                            Text('Project Settings', style: TextStyle(fontSize: 12.5, color: AppColors.inkPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  // ── New Session in Project (+)
                  Tooltip(
                    message: 'New Conversation in Project',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onNewConversation?.call();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.add_rounded,
                          size: 16,
                          color: Color(0xFF8F909A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Session list under this workspace
        if (!widget.isCollapsed) ...[
          if (widget.sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 28, top: 4, bottom: 8),
              child: Text(
                'No conversations yet',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5E606A),
                ),
              ),
            )
          else ...[
            ...visibleSessions.map((s) => _SessionRowItem(
                  session: s,
                  isSelected: s.id == widget.activeSessionId,
                  showSubtitle: widget.showSubtitle,
                  onTap: () => widget.onSessionTap(s.id),
                  onDelete: widget.onDeleteSession != null
                      ? () => widget.onDeleteSession!(s.id)
                      : null,
                  onRename: widget.onRenameSession != null
                      ? (newTitle) => widget.onRenameSession!(s.id, newTitle)
                      : null,
                  onExport: widget.onExportSession != null
                      ? () => widget.onExportSession!(s)
                      : null,
                  isPinned: widget.pinnedIds.contains(s.id),
                  onTogglePin: widget.onTogglePin != null
                      ? () => widget.onTogglePin!(s.id)
                      : null,
                )),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
                child: InkWell(
                  onTap: () => setState(() => _showAll = !_showAll),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showAll ? 'See less' : 'See more (${widget.sessions.length - 5})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF8F909A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 14,
                          color: const Color(0xFF8F909A),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Individual Session Row Item
class _SessionRowItem extends StatefulWidget {
  final CascadeSession session;
  final bool isSelected;
  final bool showSubtitle;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final Function(String newTitle)? onRename;
  final VoidCallback? onExport;

  // P4 : épinglage local
  final bool isPinned;
  final VoidCallback? onTogglePin;

  const _SessionRowItem({
    required this.session,
    required this.isSelected,
    this.showSubtitle = true,
    required this.onTap,
    this.onDelete,
    this.onRename,
    this.onExport,
    this.isPinned = false,
    this.onTogglePin,
  });

  @override
  State<_SessionRowItem> createState() => _SessionRowItemState();
}

class _SessionRowItemState extends State<_SessionRowItem> {
  bool _hovered = false;

  void _showSessionContextMenu(BuildContext context) {
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
                        widget.session.title,
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
                leading: const Icon(Icons.edit_outlined, size: 18, color: AppColors.inkPrimary),
                title: const Text('Renommer la conversation', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _promptRename(context);
                },
              ),
              if (widget.onTogglePin != null)
                ListTile(
                  leading: Icon(
                    widget.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 18,
                    color: AppColors.inkPrimary,
                  ),
                  title: Text(
                    widget.isPinned ? 'Désépingler la conversation' : 'Épingler la conversation',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onTogglePin?.call();
                  },
                ),
              if (widget.onExport != null)
                ListTile(
                  leading: const Icon(Icons.download_rounded, size: 18, color: AppColors.inkPrimary),
                  title: const Text('Exporter en Markdown', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onExport?.call();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, size: 18, color: AppColors.inkPrimary),
                title: const Text('Copy Title', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: widget.session.title));
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
                  Clipboard.setData(ClipboardData(text: widget.session.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID de session copié'), duration: Duration(seconds: 2)),
                  );
                },
              ),
              if (widget.onDelete != null)
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

  void _promptRename(BuildContext context) {
    final controller = TextEditingController(text: widget.session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1D22),
        title: const Text('Renommer la conversation', style: TextStyle(fontSize: 15, color: AppColors.inkPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
          decoration: InputDecoration(
            hintText: 'Nouveau titre...',
            hintStyle: const TextStyle(color: AppColors.inkMuted),
            filled: true,
            fillColor: const Color(0xFF22252B),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler', style: TextStyle(color: AppColors.inkMuted)),
          ),
          FilledButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              Navigator.of(ctx).pop();
              if (newTitle.isNotEmpty && newTitle != widget.session.title) {
                widget.onRename?.call(newTitle);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
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
          'Voulez-vous supprimer définitivement "${widget.session.title}" ?',
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
              widget.onDelete?.call();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isRunning = widget.session.isRunning;
    final subtitleText = widget.session.worktree ?? WorkspacePath.displayName(widget.session.workspacePath);

    Widget item = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onLongPress: () => _showSessionContextMenu(context),
        onSecondaryTap: () => _showSessionContextMenu(context),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.only(left: 14, right: 6, top: 1, bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF26282E)
                : _hovered
                    ? const Color(0xFF1E2025)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.session.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isSelected
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFFB0B0BA),
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (widget.showSubtitle && subtitleText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Text(
                          subtitleText,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isSelected
                                ? const Color(0xFF8F909A)
                                : const Color(0xFF6E707A),
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isRunning)
                Tooltip(
                  message: 'En cours d\'exécution',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isSelected ? const Color(0xFFFFFFFF) : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (widget.session.status.toUpperCase().contains('WAIT'))
                Tooltip(
                  message: 'En attente d\'approbation',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else if (widget.session.time.isNotEmpty)
                Text(
                  widget.session.time,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? const Color(0xFF9E9FA9)
                        : const Color(0xFF5E606A),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              if (widget.isPinned)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 11,
                    color: isSelected ? const Color(0xFF9E9FA9) : const Color(0xFF6E707A),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // P4 : swipe gauche = supprimer (endToStart), swipe droite = épingler
    // (startToEnd). Un seul Dismissible horizontal, chaque direction branchée
    // sur son action — confirmDismiss retourne false pour ne jamais supprimer
    // l'item de la liste (les actions passent par les callbacks parents).
    if (widget.onDelete != null || widget.onTogglePin != null) {
      return Dismissible(
        key: ValueKey('dismiss-${widget.session.id}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.endToStart) {
            if (widget.onDelete != null) _confirmDelete(context);
          } else {
            widget.onTogglePin?.call();
          }
          return false;
        },
        background: widget.onTogglePin != null
            ? Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 16),
                margin: const EdgeInsets.only(left: 14, right: 6, top: 1, bottom: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D5AFE).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text('Épingler', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : null,
        secondaryBackground: widget.onDelete != null
            ? Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                margin: const EdgeInsets.only(left: 14, right: 6, top: 1, bottom: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text('Supprimer', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : null,
        child: item,
      );
    }
    return item;
  }
}

// ── Empty State Widget
class _EmptyState extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnect;

  const _EmptyState({required this.isConnected, required this.onConnect});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF181A1F),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: const Color(0xFF272A30), width: 1),
        ),
        child: Column(
          children: [
            Icon(
              isConnected
                  ? Icons.chat_bubble_outline
                  : Icons.cloud_off_outlined,
              size: 26,
              color: AppColors.inkMuted,
            ),
            const SizedBox(height: 10),
            Text(
              isConnected ? 'No active sessions' : 'Disconnected',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isConnected
                  ? 'Start a new conversation in a project.'
                  : 'Connect to Daemon to view workspace sessions.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
            if (!isConnected) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onConnect,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner, size: 13, color: AppColors.onAccent),
                      SizedBox(width: 7),
                      Text(
                        'Connect',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

// ── Divider
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        color: const Color(0xFF1F2127),
      );
}

// ── Connection status row (bottom)
class _ConnectionRow extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onTap;

  const _ConnectionRow({required this.isConnected, required this.onTap});

  @override
  State<_ConnectionRow> createState() => _ConnectionRowState();
}

class _ConnectionRowState extends State<_ConnectionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected ? AppColors.positive : AppColors.inkMuted;
    final label = widget.isConnected ? 'Connected' : 'Offline';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1E2025) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.isConnected
                      ? AppColors.positive
                      : AppColors.inkFaint,
                  shape: BoxShape.circle,
                  boxShadow: widget.isConnected
                      ? [
                          BoxShadow(
                            color: AppColors.positive.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
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
