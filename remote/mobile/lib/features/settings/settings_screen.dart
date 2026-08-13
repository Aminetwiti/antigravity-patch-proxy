import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/notifications/approval_notifier.dart';
import '../../core/protocol/daemon_api.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.initialSettings = const {},
    this.onThemeModeChanged,
    this.onDaemonSaved,
    this.api,
    this.notifier,
    this.httpClient,
  });

  final Map<String, dynamic> initialSettings;
  final ValueChanged<int>? onThemeModeChanged;
  final ValueChanged<Map<String, dynamic>>? onDaemonSaved;
  final DaemonApi? api;
  final ApprovalNotifier? notifier;
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414), // Exact dark background
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Sidebar Menu (Desktop style)
            Container(
              width: 220,
              color: const Color(0xFF141414),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _SidebarItem(label: 'Account', isActive: false),
                  _SidebarItem(label: 'General', isActive: true),
                  _SidebarItem(label: 'Appearance', isActive: false),
                  _SidebarItem(label: 'Models', isActive: false),
                  _SidebarItem(label: 'Customizations', isActive: false),
                  _SidebarItem(label: 'Browser', isActive: false),
                  _SidebarItem(label: 'App', isActive: false),
                  
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Projects',
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _SidebarItem(label: 'antigravity-add-model-m...', isActive: false),
                  _SidebarItem(label: 'www - Copie', isActive: false),
                  _SidebarItem(label: 'sols-pro-vision', isActive: false),
                  _SidebarItem(label: 'Show all', isActive: false, isMuted: true),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Not in Project',
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _SidebarItem(label: 'Conversations', isActive: false),
                  
                  const Spacer(),
                  _SidebarItem(label: 'Shortcuts', isActive: false),
                  _SidebarItem(label: 'Provide Feedback', isActive: false),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            
            // Right Content Area (General Tab)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  border: Border(left: BorderSide(color: Color(0xFF1E1E1E), width: 1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 24, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'General',
                                  style: TextStyle(
                                    color: Color(0xFFE0E0E0),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Configure agent execution, queued message delivery, and permissions.',
                                  style: TextStyle(
                                    color: Color(0xFF757575),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF9E9E9E), size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Scrollable Settings Cards
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        children: [
                          _SectionHeader(title: 'Execution'),
                          _SettingsCard(
                            title: 'Queued Messages',
                            subtitle: 'Configure when follow-up messages are sent.',
                            linkText: 'Keyboard shortcuts',
                            control: Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF2C2C2C)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2C2C2C),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text('Queue', style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12, fontWeight: FontWeight.w500)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    alignment: Alignment.center,
                                    child: const Text('Send Immediately', style: TextStyle(color: Color(0xFF757575), fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          _SectionHeader(title: 'Agent Settings'),
                          _SettingsCard(
                            title: 'Security Preset',
                            subtitle: 'Choose a predefined security preset for the agent. This controls terminal auto-\nexecution policy, and file access policy.',
                            linkText: 'Learn more about Turbo mode',
                            control: _DropdownControl(text: 'T...'), // Obscured in screenshot
                          ),
                          
                          const SizedBox(height: 24),
                          _SectionHeader(title: 'Agent Behavior'),
                          _SettingsCard(
                            title: 'Artifact Review Policy',
                            subtitle: 'Specifies Agent\'s behavior when asking for review on artifacts, which are\ndocuments it creates to enable a richer conversation experience.',
                            control: _DropdownControl(text: 'Always Proceed'),
                          ),
                          
                          const SizedBox(height: 24),
                          _SectionHeader(title: 'File Permissions'),
                          _SettingsCard(
                            title: 'File Access Rules',
                            subtitle: 'Configure allowed and denied paths for file reads and writes.',
                            control: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2C),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Open', style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          _SectionHeader(title: 'Network Permissions'),
                          // Cutoff in screenshot, leaving empty space to match
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isMuted;

  const _SidebarItem({required this.label, required this.isActive, this.isMuted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2C2C2C) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive 
                ? const Color(0xFFE0E0E0) 
                : (isMuted ? const Color(0xFF757575) : const Color(0xFF9E9E9E)),
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? linkText;
  final Widget control;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    this.linkText,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF191919), // Slightly lighter than background, very subtle
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C2C2C), width: 1), // Exact subtle border
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF757575),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (linkText != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        linkText!,
                        style: const TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline, size: 12, color: Color(0xFF757575)),
                    ],
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

class _DropdownControl extends StatelessWidget {
  final String text;

  const _DropdownControl({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13)),
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF9E9E9E)),
        ],
      ),
    );
  }
}
