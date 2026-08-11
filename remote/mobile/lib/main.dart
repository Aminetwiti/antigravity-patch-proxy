import 'package:flutter/material.dart';
import 'core/network/websocket_client.dart';
import 'core/protocol/messages.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/workspace/workspace_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/left_sidebar_drawer.dart';
import 'widgets/right_sidebar_drawer.dart';
import 'widgets/tool_approval_card.dart';

void main() {
  runApp(const AntigravityRemoteApp());
}

class AntigravityRemoteApp extends StatelessWidget {
  const AntigravityRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Antigravity Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AntigravityMainScreen(),
    );
  }
}

class AntigravityMainScreen extends StatefulWidget {
  const AntigravityMainScreen({super.key});

  @override
  State<AntigravityMainScreen> createState() => _AntigravityMainScreenState();
}

class _AntigravityMainScreenState extends State<AntigravityMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final DaemonWebSocketClient _wsClient = DaemonWebSocketClient();

  String _activeSessionId = 's3';
  final String _activeProjectName = 'antigravity-add-model-main';
  String _activeSessionTitle = 'Poème Sur La Gravité';

  ToolApprovalRequest? _pendingApproval = ToolApprovalRequest(
    callId: 'call_99182',
    toolName: 'run_command',
    command: 'git status && npm run test',
    description: 'Execution of shell verification command on host PC',
  );

  final List<ChatMessage> _messages = [
    const ChatMessage(
      id: 'm1',
      sender: 'user',
      text: 'Écris un poème de 2 lignes sur la gravité',
      timestamp: '15:10',
    ),
    const ChatMessage(
      id: 'm2',
      sender: 'assistant',
      thought: 'Thought for 1s',
      text: 'Silencieuse force ramenant tout vers le sol,\nElle dicte aux astres la courbe de leur vol.',
      timestamp: '15:10',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _wsClient.statusNotifier.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _wsClient.dispose();
    super.dispose();
  }

  void _handleSendMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sender: 'user',
        text: text,
        timestamp: '${DateTime.now().hour}:${DateTime.now().minute}',
      ));
    });

    _wsClient.send({
      'action': 'SendUserCascadeMessage',
      'cascadeId': _activeSessionId,
      'text': text,
    });
  }

  void _handleToolDecision(ToolDecision decision) {
    setState(() {
      _pendingApproval = null;
    });

    _wsClient.send({
      'action': 'SubmitToolApproval',
      'decision': decision == ToolDecision.allow ? 'ALLOW' : 'DENY',
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _wsClient.statusNotifier.value;
    final isConnected = status == ConnectionStatus.connected;

    return Scaffold(
      key: _scaffoldKey,
      drawer: LeftSidebarDrawer(
        activeSessionId: _activeSessionId,
        onSessionSelected: (id) {
          setState(() {
            _activeSessionId = id;
            _activeSessionTitle = 'Session $id';
          });
        },
        onNewConversation: () {
          setState(() {
            _messages.clear();
            _activeSessionTitle = 'New Conversation';
          });
        },
        onOpenSettings: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          );
        },
        onDiscover: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const DiscoveryScreen()),
          );
        },
        onOpenWorkspace: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const WorkspaceScreen()),
          );
        },
      ),
      endDrawer: const RightSidebarDrawer(
        subagentsCount: 0,
        filesChangedCount: 10,
        artifactsCount: 1,
        uploadsCount: 0,
        backgroundTasksCount: 0,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.dock_outlined, size: 20, color: AppColors.inkPrimary),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Ouvrir le menu gauche',
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$_activeProjectName / $_activeSessionTitle',
                style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Connection Pill Indicator
            InkWell(
              onTap: () {
                if (isConnected) {
                  _wsClient.disconnect();
                } else {
                  _wsClient.connect();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.positive.withValues(alpha: 0.15)
                      : AppColors.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? AppColors.positive : AppColors.danger,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isConnected ? AppColors.positive : AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isConnected ? 'Connected' : 'Offline',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isConnected ? AppColors.positive : AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Open IDE Button Pill
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.change_history, size: 14, color: AppColors.accentBlue),
            label: const Text(
              'Open IDE',
              style: TextStyle(fontSize: 11, color: AppColors.inkPrimary),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          // Right Sidebar Toggle Button
          IconButton(
            icon: const Icon(Icons.vertical_split_outlined, size: 20, color: AppColors.inkPrimary),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Ouvrir le panneau contexte',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages Timeline
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                ..._messages.map((msg) => _MessageBubble(message: msg)),
                if (_pendingApproval != null)
                  ToolApprovalCard(
                    request: _pendingApproval!,
                    onDecision: _handleToolDecision,
                  ),
              ],
            ),
          ),

          // Bottom Prompt Input Bar
          ChatInputBar(
            onSend: _handleSendMessage,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _isThoughtExpanded = true;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.sender == 'user';

    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16, left: 40),
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Text(
            widget.message.text,
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkPrimary),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thought Accordion Pill
          if (widget.message.thought != null) ...[
            InkWell(
              onTap: () {
                setState(() {
                  _isThoughtExpanded = !_isThoughtExpanded;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.message.thought!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isThoughtExpanded ? Icons.chevron_right : Icons.expand_more,
                      size: 14,
                      color: AppColors.inkMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Assistant Response Text
          Text(
            widget.message.text,
            style: const TextStyle(fontSize: 14, color: AppColors.inkPrimary, height: 1.4),
          ),

          const SizedBox(height: 8),

          // Message Action Icons (Copy, Like, Dislike)
          Row(
            children: const [
              Icon(Icons.copy_outlined, size: 14, color: AppColors.inkMuted),
              SizedBox(width: 12),
              Icon(Icons.thumb_up_outlined, size: 14, color: AppColors.inkMuted),
              SizedBox(width: 12),
              Icon(Icons.thumb_down_outlined, size: 14, color: AppColors.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
}
