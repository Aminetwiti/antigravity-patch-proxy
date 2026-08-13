import 'package:flutter/material.dart';
import '../../core/protocol/messages.dart';

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
      backgroundColor: const Color(0xFF141414), // Using a hardcoded near-black to match 100%
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            // 2. Navigation controls (Sidebar toggle, Back, Forward)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.view_sidebar_outlined, size: 18, color: const Color(0xFF9E9E9E)),
                  const SizedBox(width: 16),
                  Icon(Icons.arrow_back, size: 18, color: const Color(0xFF424242)),
                  const SizedBox(width: 16),
                  Icon(Icons.arrow_forward, size: 18, color: const Color(0xFF424242)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Top buttons (New Conv, History, Scheduled)
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
                      color: Color(0xFF757575), // Same grey as 'File'
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.filter_list, size: 14, color: Color(0xFF757575)),
                  const SizedBox(width: 12),
                  const Icon(Icons.create_new_folder_outlined, size: 14, color: Color(0xFF757575)),
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
                thumbColor: const Color(0xFF2C2C2C),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (folderNames.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No projects found. Connect to see sessions.',
                          style: TextStyle(color: Color(0xFF757575), fontSize: 13),
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
                textColor: widget.isConnected ? Colors.green : Colors.redAccent,
                onTap: widget.onToggleConnection,
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
            color: const Color(0xFF1E1E1E), // Slightly lighter than background
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF2C2C2C), // Subtle border
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFFBDBDBD)),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFBDBDBD),
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
              Icon(icon, size: 16, color: textColor ?? const Color(0xFF9E9E9E)),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: textColor ?? const Color(0xFF9E9E9E),
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
  final bool isLoading;
  final bool isPlaceholder;

  const _SessionItemData(
    this.id,
    this.title,
    this.time, {
    this.isLoading = false,
    this.isPlaceholder = false,
  });
}

class _ProjectFolderGroup extends StatelessWidget {
  final String folderName;
  final List<dynamic> sessions;
  final String activeSessionId;
  final bool hasTrailingPlus;
  final Function(String id) onSessionTap;

  const _ProjectFolderGroup({
    required this.folderName,
    required this.sessions,
    required this.activeSessionId,
    this.hasTrailingPlus = false,
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
              const Icon(Icons.folder_outlined, size: 15, color: Color(0xFF757575)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folderName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9E9E9E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasTrailingPlus) ...[
                const Icon(Icons.more_vert, size: 14, color: Color(0xFF757575)),
                const SizedBox(width: 4),
                const Icon(Icons.add, size: 14, color: Color(0xFF757575)),
              ]
            ],
          ),
        ),
        ...sessions.map((s) {
          final itemId = s is CascadeSession ? s.id : (s as _SessionItemData).id;
          final itemTitle = s is CascadeSession ? s.title : (s as _SessionItemData).title;
          final itemTime = s is CascadeSession ? s.time : (s as _SessionItemData).time;
          final isSelected = itemId == activeSessionId;
          final isLoading = s is _SessionItemData ? s.isLoading : false;
          final isPlaceholder = s is _SessionItemData ? s.isPlaceholder : false;
          
          if (isPlaceholder) {
            return Padding(
              padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4, right: 4),
              child: Text(
                itemTitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF424242), // Dark grey for "No conversations yet"
                  fontWeight: FontWeight.w400,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(left: 14, top: 1, bottom: 1, right: 4),
            child: InkWell(
              onTap: () => onSessionTap(itemId),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2C2C2C) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        itemTitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? const Color(0xFFE0E0E0) : const Color(0xFF9E9E9E),
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF757575),
                          ),
                        ),
                      )
                    else if (itemTime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          itemTime,
                          style: TextStyle(
                            fontSize: 11, 
                            color: isSelected ? const Color(0xFF9E9E9E) : const Color(0xFF616161),
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
