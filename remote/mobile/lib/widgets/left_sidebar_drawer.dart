import 'package:flutter/material.dart';
import '../core/protocol/messages.dart';
import '../theme/app_colors.dart';

class LeftSidebarDrawer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceBase,
      child: SafeArea(
        child: Column(
          children: [
            // Top Header Bar with toggle & navigation icons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.vertical_split_outlined, size: 20, color: AppColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer le menu',
                  ),
                  const IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: AppColors.inkMuted),
                    onPressed: null,
                  ),
                  const IconButton(
                    icon: Icon(Icons.arrow_forward, size: 18, color: AppColors.inkMuted),
                    onPressed: null,
                  ),
                ],
              ),
            ),

            // Main Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  _NavButton(
                    icon: Icons.add,
                    label: 'New Conversation',
                    onTap: () {
                      Navigator.of(context).pop();
                      onNewConversation();
                    },
                    isPrimary: true,
                  ),
                  const SizedBox(height: 6),
                  _NavButton(
                    icon: Icons.history,
                    label: 'Conversation History',
                    onTap: () {},
                  ),
                  const SizedBox(height: 4),
                  _NavButton(
                    icon: Icons.schedule,
                    label: 'Scheduled Tasks',
                    onTap: () {},
                  ),
                  const SizedBox(height: 4),
                  _NavButton(
                    icon: Icons.radar,
                    label: 'Appairer un Daemon',
                    onTap: () {
                      Navigator.of(context).pop();
                      if (onDiscover != null) onDiscover!();
                    },
                  ),
                  const SizedBox(height: 4),
                  _NavButton(
                    icon: Icons.folder_open_outlined,
                    label: 'Explorer le Workspace',
                    onTap: () {
                      Navigator.of(context).pop();
                      if (onOpenWorkspace != null) onOpenWorkspace!();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: AppColors.borderSubtle),

            // Projects Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: const [
                  Text(
                    'Projects',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.filter_list, size: 16, color: AppColors.inkMuted),
                  SizedBox(width: 8),
                  Icon(Icons.create_new_folder_outlined, size: 16, color: AppColors.inkMuted),
                ],
              ),
            ),

            // Workspace Tree / Sessions List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _ProjectFolderGroup(
                    folderName: 'antigravity-add-model-main',
                    sessions: sessions ?? const [
                      _SessionItemData('s1', 'Mobile App Project Plan...', '3m'),
                      _SessionItemData('s2', 'Mobile App Remote Infra...', '10m'),
                      _SessionItemData('s3', 'Poème Sur La Gravité', '50m'),
                      _SessionItemData('s4', 'Configuration Des Niveaux...', '6d'),
                      _SessionItemData('s5', 'Doctor UI Data Issue', '6d'),
                    ],
                    activeSessionId: activeSessionId,
                    onSessionTap: (id) {
                      Navigator.of(context).pop();
                      onSessionSelected(id);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ProjectFolderGroup(
                    folderName: 'www - Copie',
                    sessions: const [
                      _SessionItemData('s6', 'Comprehensive Hardco...', ''),
                      _SessionItemData('s7', 'Identification De L\'Assi...', '30m'),
                      _SessionItemData('s8', 'Audit Et Rapport Complet', ''),
                      _SessionItemData('s9', 'Audit UI/UX Mobile Prof...', ''),
                    ],
                    activeSessionId: activeSessionId,
                    onSessionTap: (id) {
                      Navigator.of(context).pop();
                      onSessionSelected(id);
                    },
                  ),
                ],
              ),
            ),

            const Divider(color: AppColors.borderSubtle),

            // Bottom Settings Action
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings_outlined, size: 18, color: AppColors.inkSecondary),
              title: const Text(
                'Settings',
                style: TextStyle(fontSize: 13, color: AppColors.inkPrimary),
              ),
              onTap: () {
                Navigator.of(context).pop();
                if (onOpenSettings != null) onOpenSettings!();
              },
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
          color: isPrimary ? AppColors.surfaceInput : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? Border.all(color: AppColors.borderSubtle) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.inkPrimary),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.inkPrimary,
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

  const _SessionItemData(this.id, this.title, this.time);
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
              const Icon(Icons.folder_open_outlined, size: 16, color: AppColors.inkSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folderName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSecondary,
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
          final itemTime = s is CascadeSession ? '' : (s as _SessionItemData).time;
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
