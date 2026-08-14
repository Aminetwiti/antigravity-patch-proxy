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
    final scheme = Theme.of(context).colorScheme;
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
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            // 1. Bouton primaire "Nouvelle conversation"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _NavButton(
                icon: Icons.add,
                label: 'Nouvelle conversation',
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
              label: 'Historique des conversations',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onConversationHistory != null) widget.onConversationHistory!();
              },
            ),
            _SidebarAction(
              icon: Icons.schedule,
              label: 'Tâches planifiées',
              onTap: () {
                Navigator.of(context).pop();
                if (widget.onScheduledTasks != null) widget.onScheduledTasks!();
              },
            ),
            const SizedBox(height: 16),
            
            // 2. En-tête Projets
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Projets',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.filter_list, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Icon(Icons.create_new_folder_outlined, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // 3. Liste scrollable des sessions
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 4,
                radius: const Radius.circular(2),
                thumbColor: scheme.outlineVariant,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (folderNames.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              widget.isConnected ? Icons.chat_bubble_outline : Icons.cloud_off_outlined,
                              size: 28,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isConnected ? 'Aucune session active' : 'Aucun projet connecté',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.isConnected
                                  ? 'Démarrez une nouvelle conversation ci-dessus.'
                                  : 'Connectez le Daemon PC pour afficher vos sessions actives.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                            if (!widget.isConnected) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onToggleConnection();
                                },
                                icon: const Icon(Icons.qr_code_scanner, size: 16),
                                label: const Text('Se connecter au Daemon', style: TextStyle(fontSize: 12)),
                              ),
                            ],
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
            
            // 4. Paramètres et statut en bas
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: _SidebarAction(
                icon: Icons.settings_outlined,
                label: 'Paramètres',
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
                label: widget.isConnected ? 'Connecté' : 'Hors ligne',
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurface),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
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
    final scheme = Theme.of(context).colorScheme;
    final color = textColor ?? scheme.onSurfaceVariant;
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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 12),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folderName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 8),
            child: Text(
              'Aucune conversation',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
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
                    color: isSelected ? scheme.surfaceContainerHighest : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ] else if (s.time.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            s.time,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
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
