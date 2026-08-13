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
  bool _showScheduledOnly = false;
  final TextEditingController _projectSearchCtrl = TextEditingController();
  String _projectSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _projectSearchCtrl.addListener(() {
      setState(() => _projectSearchQuery = _projectSearchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _projectSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> rawSessions = widget.sessions ?? const [
      _SessionItemData('s1', 'Mobile App Project Plan...', '3m', isUnread: true, isPinned: true, workspaceName: 'remote/mobile'),
      _SessionItemData('s2', 'Mobile App Remote Infra...', '10m', isUnread: false),
      _SessionItemData('s3', 'Poème Sur La Gravité', '50m', isUnread: false, isPinned: true, workspaceName: 'antigravity-main'),
      _SessionItemData('s4', 'Configuration Des Niveaux...', '6d', isUnread: true, isScheduled: true),
      _SessionItemData('s5', 'Doctor UI Data Issue', '6d', isUnread: false),
    ];
    final displaySessions = rawSessions.where((s) {
      if (_onlyUnread) {
        if (s is _SessionItemData && !s.isUnread) return false;
      }
      if (_showScheduledOnly) {
        if (s is _SessionItemData && !s.isScheduled) return false;
      }
      if (_projectSearchQuery.isNotEmpty) {
        final title = s is CascadeSession ? s.title : (s as _SessionItemData).title;
        if (!title.toLowerCase().contains(_projectSearchQuery)) return false;
      }
      return true;
    }).toList();

    return Drawer(
      // Rail PC : canvas Zinc-950 + bordure droite (--glass-bg-tier-1 sur --bg-0)
      backgroundColor: AppColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.borderSubtle, width: 1),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                controller: _projectSearchCtrl,
                autofocus: false,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Rechercher un projet / session…',
                  prefixIcon: Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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

            // Filtres : non lu + tâches planifiées (inline, pas de modal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Tâches planifiées',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _showScheduledOnly,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) => setState(() => _showScheduledOnly = val),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            // PC .btn-primary vs .btn-ghost
            color: isPrimary ? AppColors.accentBlueDeep : AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isPrimary
                  ? AppColors.accentBlueDeep
                  : AppColors.borderSubtle,
            ),
            boxShadow: isPrimary
                ? [BoxShadow(color: AppColors.accentBlue.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isPrimary ? Colors.white : AppColors.inkSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                  color: isPrimary ? Colors.white : AppColors.inkPrimary,
                ),
              ),
            ],
          ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          // PC .nav-item : hauteur 40px, hover surfaceHover
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.inkSecondary),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
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
  final bool isPinned;
  final bool isScheduled;
  final String? workspaceName;

  const _SessionItemData(
    this.id,
    this.title,
    this.time, {
    this.isUnread = false,
    this.isPinned = false,
    this.isScheduled = false,
    this.workspaceName,
  });
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
              Icon(Icons.folder_open_outlined, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folderName,
                  style: const TextStyle(
                    // PC .nav-group-label : 10px uppercase espacé
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: AppColors.inkFaint,
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
          final isPinned = s is _SessionItemData ? s.isPinned : false;
          final workspaceName = s is _SessionItemData ? s.workspaceName : null;
          return Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            child: InkWell(
              onTap: () => onSessionTap(itemId),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  // PC .nav-item.active : fond raised + glow bleu
                  color: isSelected ? AppColors.surfaceInput : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.accentBlue.withValues(alpha: 0.20),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                  border: isSelected
                      ? Border.all(color: AppColors.accentBlue.withValues(alpha: 0.35))
                      : null,
                ),
                child: Row(
                  children: [
                    if (isPinned) ...[
                      const Icon(Icons.push_pin, size: 13, color: AppColors.accentBlue),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemTitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isSelected ? AppColors.inkPrimary : AppColors.inkSecondary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (workspaceName != null)
                            Row(
                              children: [
                                const Icon(Icons.folder_outlined, size: 11, color: AppColors.accentBlue),
                                const SizedBox(width: 4),
                                Text(
                                  workspaceName,
                                  style: const TextStyle(fontSize: 10, color: AppColors.accentBlue),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.call_split, size: 10, color: AppColors.inkMuted),
                                const SizedBox(width: 2),
                                const Text(
                                  'main',
                                  style: TextStyle(fontSize: 9.5, color: AppColors.inkMuted),
                                ),
                              ],
                            ),
                        ],
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
