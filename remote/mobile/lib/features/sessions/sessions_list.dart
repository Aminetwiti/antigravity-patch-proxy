import 'package:flutter/material.dart';
import '../../core/protocol/messages.dart';
import '../../theme/app_colors.dart';

class LeftSidebarDrawer extends StatefulWidget {
  final String activeSessionId;
  final Function(String sessionId) onSessionSelected;
  final VoidCallback onNewConversation;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDiscover;
  final VoidCallback? onOpenWorkspace;
  final List<CascadeSession>? sessions;

  const LeftSidebarDrawer({
    super.key,
    required this.activeSessionId,
    required this.onSessionSelected,
    required this.onNewConversation,
    this.onOpenSettings,
    this.onDiscover,
    this.onOpenWorkspace,
    this.sessions,
  });

  @override
  State<LeftSidebarDrawer> createState() => _LeftSidebarDrawerState();
}

class _LeftSidebarDrawerState extends State<LeftSidebarDrawer> {
  bool _onlyUnread = false;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> rawSessions = widget.sessions ?? const [
      _SessionItemData('s1', 'Mobile App Project Plan...', '3m', isUnread: true),
      _SessionItemData('s2', 'Mobile App Remote Infra...', '10m', isUnread: false),
      _SessionItemData('s3', 'Poème Sur La Gravité', '50m', isUnread: false),
      _SessionItemData('s4', 'Configuration Des Niveaux...', '6d', isUnread: true),
      _SessionItemData('s5', 'Doctor UI Data Issue', '6d', isUnread: false),
    ];
    final displaySessions = rawSessions.where((s) {
      if (!_onlyUnread) return true;
      if (s is _SessionItemData) return s.isUnread;
      return false;
    }).toList();

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.api_outlined, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Antigravity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  _NavButton(
                    icon: Icons.add,
                    label: 'New Conversation',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onNewConversation();
                    },
                    isPrimary: true,
                  ),
                ],
              ),
            ),
            const Divider(),
            _SidebarAction(
              icon: Icons.search,
              label: 'Discover Daemon',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onDiscover != null) widget.onDiscover!();
              },
            ),
            _SidebarAction(
              icon: Icons.folder_outlined,
              label: 'Explorer le Workspace',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onOpenWorkspace != null) widget.onOpenWorkspace!();
              },
            ),
            _SidebarAction(
              icon: Icons.settings_outlined,
              label: 'Settings & Profile',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onOpenSettings != null) widget.onOpenSettings!();
              },
            ),
            const SizedBox(height: 8),

            // Filtre "Seulement non lu"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Seulement non lu',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _onlyUnread,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) => setState(() => _onlyUnread = val),
                  ),
                ],
              ),
            ),
            const Divider(),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _ProjectFolderGroup(
                    folderName: 'antigravity-add-model-main',
                    sessions: displaySessions,
                    activeSessionId: widget.activeSessionId,
                    onSessionTap: (id) {
                      Navigator.of(context).pop();
                      widget.onSessionSelected(id);
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

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SidebarAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionItemData {
  final String id;
  final String title;
  final String time;
  final bool isUnread;

  const _SessionItemData(this.id, this.title, this.time, {this.isUnread = false});
}

class _ProjectFolderGroup extends StatelessWidget {
  final String folderName;
  final List<dynamic> sessions;
  final String activeSessionId;
  final Function(String id) onSessionTap;

  const _ProjectFolderGroup({
    required this.folderName,
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        ...sessions.map((s) {
          final itemId = s is CascadeSession ? s.id : (s as _SessionItemData).id;
          final itemTitle = s is CascadeSession ? s.title : (s as _SessionItemData).title;
          final itemTime = s is CascadeSession ? s.time : (s as _SessionItemData).time;
          final isSelected = itemId == activeSessionId;
          return Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            child: InkWell(
              onTap: () => onSessionTap(itemId),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.surfaceInput : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        itemTitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? AppColors.inkPrimary : AppColors.inkSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (itemTime.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        itemTime,
                        style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
