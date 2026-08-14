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
          ? 'Other' 
          : s.workspacePath.split(RegExp(r'[\\/]')).last;
      groupedSessions.putIfAbsent(folderName, () => []).add(s);
    }
    
    // Sort keys if needed, or leave as is
    final folderNames = groupedSessions.keys.toList()..sort();

    return Drawer(
      backgroundColor: AppColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            // 2. Top buttons (New Conv, History, Scheduled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _NavButton(
                icon: Icons.add,
                label: 'New Conversation',
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onNewConversation();
                },
                isPrimary: true,
              ),
            ),
            const SizedBox(height: 8),
            _SidebarAction(
              icon: Icons.history,
              label: 'Conversation History',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onConversationHistory != null) widget.onConversationHistory!();
              },
            ),
            _SidebarAction(
              icon: Icons.schedule,
              label: 'Scheduled Tasks',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onScheduledTasks != null) widget.onScheduledTasks!();
              },
            ),
            const SizedBox(height: 16),
            
            // 4. Projects Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Projects',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.filter_list, size: 14, color: AppColors.inkMuted),
                  const SizedBox(width: 12),
                  const Icon(Icons.create_new_folder_outlined, size: 14, color: AppColors.inkMuted),
                  const SizedBox(width: 8), // For scrollbar alignment
                ],
              ),
            ),

            // 5. Scrollable session list
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 6,
                radius: const Radius.circular(3),
                thumbColor: AppColors.borderStrong,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (folderNames.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              widget.isConnected ? Icons.chat_bubble_outline : Icons.cloud_off_outlined,
                              size: 28,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isConnected ? 'Aucune session active' : 'Aucun projet connecté',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.isConnected
                                  ? 'Créez une nouvelle conversation ou choisissez une session ci-dessus.'
                                  : 'Connectez le Daemon PC pour afficher vos sessions actives.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                            ),
                            const SizedBox(height: 12),
                            if (widget.isConnected)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onNewConversation();
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Nouvelle Conversation', style: TextStyle(fontSize: 12)),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onToggleConnection();
                                },
                                icon: const Icon(Icons.qr_code_scanner, size: 16),
                                label: const Text('Se connecter au Daemon', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      )
                    else
                      ...folderNames.map((folder) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _ProjectFolderGroup(
                            folderName: folder,
                            sessions: groupedSessions[folder]!,
                            activeSessionId: widget.activeSessionId,
                            onSessionTap: (id) {
                              Navigator.of(context).pop();
                              widget.onSessionSelected(id);
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            
            // 6. Settings and Connection at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: _SidebarAction(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.of(context).pop();
                  if (widget.onOpenSettings != null) widget.onOpenSettings!();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: _SidebarAction(
                icon: widget.isConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                label: widget.isConnected ? 'Connected' : 'Offline',
                textColor: widget.isConnected ? AppColors.positive : AppColors.danger,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onToggleConnection();
                },
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderStrong,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.inkSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
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

class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? textColor;

  const _SidebarAction({required this.icon, required this.label, this.onTap, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: textColor ?? AppColors.inkMuted),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: textColor ?? AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 15, color: AppColors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folderName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 28, top: 4, bottom: 8),
            child: Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.inkFaint,
              ),
            ),
          )
        else
          ...sessions.map((s) {
            final isSelected = s.id == activeSessionId;

            return Padding(
              padding: const EdgeInsets.only(left: 14, top: 1, bottom: 1, right: 4),
              child: InkWell(
                onTap: () => onSessionTap(s.id),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.surfaceInput : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isSelected ? AppColors.inkPrimary : AppColors.inkMuted,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.accentBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ] else if (s.time.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            s.time,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
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
