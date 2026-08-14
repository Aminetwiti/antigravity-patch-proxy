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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionsList = widget.sessions ?? [];
    final Map<String, List<CascadeSession>> groupedSessions = {};
    for (final s in sessionsList) {
      final folderName = s.workspacePath.isEmpty
          ? 'Autres'
          : s.workspacePath.split(RegExp(r'[\\/]')).last;
      groupedSessions.putIfAbsent(folderName, () => []).add(s);
    }
    final folderNames = groupedSessions.keys.toList()..sort();

    return Drawer(
      backgroundColor: AppColors.sidebarBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            // ── Header: logo + title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(Icons.bolt, size: 13, color: AppColors.onAccent),
                  ),
                  const SizedBox(width: 9),
                  const Text(
                    'Antigravity',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  _IconBtn(
                    icon: Icons.edit_outlined,
                    tooltip: 'Nouvelle conversation',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onNewConversation();
                    },
                  ),
                ],
              ),
            ),

            const _Divider(),

            // ── Quick-nav actions
            _SidebarAction(
              icon: Icons.access_time_outlined,
              label: 'Historique',
              onTap: () {
                Navigator.of(context).pop();
                widget.onConversationHistory?.call();
              },
            ),
            _SidebarAction(
              icon: Icons.schedule_outlined,
              label: 'Tâches planifiées',
              onTap: () {
                Navigator.of(context).pop();
                widget.onScheduledTasks?.call();
              },
            ),
            _SidebarAction(
              icon: Icons.folder_open_outlined,
              label: 'Espace de travail',
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenWorkspace?.call();
              },
            ),

            const SizedBox(height: 4),
            const _Divider(),
            const SizedBox(height: 4),

            // ── Section label
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: Row(
                children: [
                  const Text(
                    'SESSIONS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkFaint,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  _IconBtn(
                    icon: Icons.add,
                    tooltip: 'Nouvelle session',
                    size: 13,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onNewConversation();
                    },
                  ),
                ],
              ),
            ),

            // ── Session list
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 3,
                radius: const Radius.circular(2),
                thumbColor: AppColors.borderStrong.withValues(alpha: 0.6),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    if (folderNames.isEmpty)
                      _EmptyState(isConnected: widget.isConnected, onConnect: () {
                        Navigator.of(context).pop();
                        widget.onToggleConnection();
                      })
                    else
                      ...folderNames.map((folder) => _ProjectFolderGroup(
                            folderName: folder,
                            sessions: groupedSessions[folder]!,
                            activeSessionId: widget.activeSessionId,
                            onSessionTap: (id) {
                              Navigator.of(context).pop();
                              widget.onSessionSelected(id);
                            },
                          )),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            const _Divider(),

            // ── Bottom: settings + connection status
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(
                children: [
                  _SidebarAction(
                    icon: Icons.settings_outlined,
                    label: 'Paramètres',
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
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ── Divider
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 0),
        color: AppColors.borderSubtle,
      );
}

// ── Small icon button (header actions)
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 14,
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
              child: Icon(icon, size: size, color: AppColors.inkMuted),
            ),
          ),
        ),
      );
}

// ── Sidebar action row (history, scheduled, settings…)
class _SidebarAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SidebarAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.inkSecondary;
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
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.listSelectionBg.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: color),
              const SizedBox(width: 10),
              Text(
                widget.label,
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

// ── Project folder group
class _ProjectFolderGroup extends StatelessWidget {
  final String folderName;
  final List<CascadeSession> sessions;
  final String activeSessionId;
  final Function(String id) onSessionTap;

  const _ProjectFolderGroup({
    required this.folderName,
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Folder header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined,
                    size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    folderName,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkMuted,
                      letterSpacing: 0.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 3, bottom: 8),
              child: Text(
                'Aucune conversation',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint.withValues(alpha: 0.7)),
              ),
            )
          else
            ...sessions.map((s) => _SessionRow(
                  session: s,
                  isSelected: s.id == activeSessionId,
                  onTap: () => onSessionTap(s.id),
                )),
        ],
      );
}

// ── Individual session row
class _SessionRow extends StatefulWidget {
  final CascadeSession session;
  final bool isSelected;
  final VoidCallback onTap;

  const _SessionRow({
    required this.session,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
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
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.fromLTRB(6, 1, 6, 1),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.listSelectionBg
                : _hovered
                    ? AppColors.listSelectionBg.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              // Left accent bar for active session
              AnimatedContainer(
                duration: AppMotion.fast,
                width: 2,
                height: 30,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accentBlue : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.md),
                    bottomLeft: Radius.circular(AppRadius.md),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.session.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isSelected
                                ? AppColors.inkPrimary
                                : AppColors.inkSecondary,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (!isSelected && widget.session.time.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            widget.session.time,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state
class _EmptyState extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnect;

  const _EmptyState({required this.isConnected, required this.onConnect});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderSubtle, width: 1),
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
              isConnected ? 'Aucune session active' : 'Non connecté',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isConnected
                  ? 'Démarrez une nouvelle conversation.'
                  : 'Connectez le Daemon pour voir vos sessions.',
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
                        'Se connecter',
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
    final label = widget.isConnected ? 'Connecté' : 'Hors ligne';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.listSelectionBg.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              // Status dot
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
