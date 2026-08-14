import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/protocol/messages.dart';
import 'package:mobile/theme/app_colors.dart';

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
    this.isConnected = false,
    required this.onToggleConnection,
  });

  @override
  State<LeftSidebarDrawer> createState() => _LeftSidebarDrawerState();
}

class _LeftSidebarDrawerState extends State<LeftSidebarDrawer> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _collapsedFolders = {};

  String _cleanWorkspaceName(String rawPath) {
    if (rawPath.isEmpty || rawPath == '.') return 'antigravity-workspace';
    var clean = rawPath.replaceFirst(RegExp(r'^file:\/\/\/'), '');
    clean = clean.replaceAll('\\', '/');
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    final parts = clean.split('/');
    if (parts.isNotEmpty && parts.last.isNotEmpty) {
      return parts.last;
    }
    return clean;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ne conserver STRICTEMENT que les sessions disponibles (non archivées et non supprimées)
    final allSessions = widget.sessions ?? [];
    final availableSessions = allSessions
        .where((s) => s.isAvailable && s.id.isNotEmpty)
        .toList();

    // Organiser les sessions par workspace
    final Map<String, List<CascadeSession>> groupedSessions = {};
    for (final s in availableSessions) {
      final folderName = _cleanWorkspaceName(s.workspacePath);
      groupedSessions.putIfAbsent(folderName, () => []).add(s);
    }

    final folderNames = groupedSessions.keys.toList()..sort();

    return Drawer(
      backgroundColor: const Color(0xFF131416),
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
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconBtn(
                    icon: Icons.arrow_back,
                    tooltip: 'Retour',
                    onTap: () => Navigator.of(context).pop(),
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
                    Navigator.of(context).pop();
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
              onTap: () {
                Navigator.of(context).pop();
                widget.onConversationHistory?.call();
              },
            ),
            _SidebarActionItem(
              icon: Icons.schedule_outlined,
              label: 'Scheduled Tasks',
              onTap: () {
                Navigator.of(context).pop();
                widget.onScheduledTasks?.call();
              },
            ),

            const SizedBox(height: 14),

            // ── Section Header: Projects [filter] [new folder]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'Projects',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8F909A),
                    ),
                  ),
                  const Spacer(),
                  _HeaderIconBtn(
                    icon: Icons.filter_list_rounded,
                    tooltip: 'Filtrer',
                    onTap: () {},
                    size: 15,
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
                    if (folderNames.isEmpty)
                      _EmptyState(
                        isConnected: widget.isConnected,
                        onConnect: () {
                          Navigator.of(context).pop();
                          widget.onToggleConnection();
                        },
                      )
                    else
                      ...folderNames.map((folder) {
                        final sessions = groupedSessions[folder] ?? [];
                        final isCollapsed = _collapsedFolders.contains(folder);
                        return _WorkspaceFolderSection(
                          folderName: folder,
                          sessions: sessions,
                          isCollapsed: isCollapsed,
                          activeSessionId: widget.activeSessionId,
                          onToggleCollapse: () {
                            setState(() {
                              if (isCollapsed) {
                                _collapsedFolders.remove(folder);
                              } else {
                                _collapsedFolders.add(folder);
                              }
                            });
                          },
                          onSessionTap: (id) {
                            Navigator.of(context).pop();
                            widget.onSessionSelected(id);
                          },
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
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFFD4D4D8),
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
class _WorkspaceFolderSection extends StatelessWidget {
  final String folderName;
  final List<CascadeSession> sessions;
  final bool isCollapsed;
  final String activeSessionId;
  final VoidCallback onToggleCollapse;
  final Function(String id) onSessionTap;

  const _WorkspaceFolderSection({
    required this.folderName,
    required this.sessions,
    required this.isCollapsed,
    required this.activeSessionId,
    required this.onToggleCollapse,
    required this.onSessionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workspace Folder Header
        InkWell(
          onTap: onToggleCollapse,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                    folderName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFA1A1AA),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Session list under this workspace
        if (!isCollapsed) ...[
          if (sessions.isEmpty)
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
          else
            ...sessions.map((s) => _SessionRowItem(
                  session: s,
                  isSelected: s.id == activeSessionId,
                  onTap: () => onSessionTap(s.id),
                )),
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
  final VoidCallback onTap;

  const _SessionRowItem({
    required this.session,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SessionRowItem> createState() => _SessionRowItemState();
}

class _SessionRowItemState extends State<_SessionRowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isRunning = widget.session.isRunning;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
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
                child: Text(
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
              ),
              const SizedBox(width: 8),
              if (isRunning)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.accentBlue,
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
            ],
          ),
        ),
      ),
    );
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
