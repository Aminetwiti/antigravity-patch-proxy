import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/network/websocket_client.dart';
import 'core/notifications/approval_notifier.dart';
import 'core/protocol/daemon_api.dart';
import 'core/protocol/messages.dart';
import 'core/protocol/session_parser.dart';
import 'core/protocol/stream_parser.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/workspace/workspace_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/left_sidebar_drawer.dart';
import 'widgets/markdown_bubble.dart';
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

  ToolApprovalRequest? _pendingApproval;

  final List<ChatMessage> _messages = [];

  DaemonApi? _api;
  StreamSubscription<Map<String, dynamic>>? _streamSub;
  int _messageCounter = 0;
  
  Map<String, dynamic> _contextStats = {};

  // --- Étape 4 : Reminders contextuels ---
  // « Still working » : bannière après 15 s de stream continu.
  static const _stillWorkingDelay = Duration(seconds: 15);
  final Set<String> _pendingApprovalCallIds = {};
  Timer? _stillWorkingTimer;
  int _activeStreamCount = 0;
  bool _showStillWorking = false;

  @override
  void initState() {
    super.initState();
    _wsClient.statusNotifier.addListener(_onStatusChanged);
    // Notifications locales (APPROVAL_REQUIRED) — aucune dépendance Firebase.
    ApprovalNotifier.instance.init();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_wsClient.statusNotifier.value == ConnectionStatus.connected) {
      _api ??= DaemonApi(
        incoming: _wsClient.stream,
        send: _wsClient.send,
      );
      _watchBroadcastStreams();
      _refreshSessions();
      _refreshContext();
    }
  }

  Future<void> _refreshContext() async {
    final api = _api;
    if (api == null) return;
    try {
      final stats = await api.getContext();
      if (mounted) {
        setState(() {
          _contextStats = stats;
        });
      }
    } catch (_) {}
  }

  // Suit les streams déclenchés par une AUTRE surface (PC ou autre téléphone)
  // et les affiche dans le fil : stream_start → nouveau message assistant
  // streamé, stream_delta → deltas de texte, stream_end → finalisation.
  final Map<String, String> _externalThoughts = {};
  void _watchBroadcastStreams() {
    _streamSub?.cancel();
    _streamSub = _api?.events.listen((msg) {
      final isBroadcast = msg['broadcast'] == true;
      if (!isBroadcast || !mounted) return;
      final type = msg['type'] as String?;
      final requestId = msg['requestId'] as String? ?? '';
      final sessionId = msg['data']?['cascadeId'] as String?;
      if (sessionId != null && sessionId != _activeSessionId) return;

      if (type == 'stream_start') {
        _onStreamStarted();
        setState(() {
          _messages.add(ChatMessage(
            id: 'ext-$requestId',
            sender: 'assistant',
            text: '',
            timestamp: _timestamp(),
            isStreaming: true,
          ));
        });
      } else if (type == 'stream_delta') {
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            final current = _messages[idx];
            _externalThoughts[requestId] =
                (_externalThoughts[requestId] ?? '') + thoughtDelta;
            _messages[idx] = current.copyWith(
              text: current.text + textDelta,
              thought: _externalThoughts[requestId]!.isNotEmpty
                  ? 'Thought · ${_externalThoughts[requestId]!.trim()}'
                  : current.thought,
            );
          }
            _pendingApproval = ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            );
            _pendingApprovalCallIds.add(approval.callId);
            // Étape 3 : notification locale si l'utilisateur n'est PAS actif
            // sur le PC hôte (hostActive=true → l'approbation est déjà à
            // l'écran de l'ordinateur, inutile de sonner le téléphone).
            final hostActive = msg['data']?['hostActive'] == true;
            if (!hostActive) {
              ApprovalNotifier.instance.notifyApprovalRequired(
                callId: approval.callId,
                toolName: approval.tool,
                command: approval.command,
              );
            }
          }
        });
      } else if (type == 'stream_end') {
        _onStreamEnded();
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
          _externalThoughts.remove(requestId);
        });
      }
    });
  }

  Future<void> _refreshSessions() async {
    final api = _api;
    if (api == null) return;
    try {
      final data = await api.listSessions();
      final sessions = SessionParser.parseListSessions(data);
      if (sessions.isNotEmpty) {
        setState(() {
          _sessions = sessions;
          _activeSessionId = sessions.first.id;
          // Titre réel depuis la trajectoire (Étape 2) au lieu du placeholder.
          _activeSessionTitle = sessions.first.title;
        });
      }
    } catch (_) {
      // Offline or daemon not ready — keep local fallback.
    }
  }

  List<CascadeSession> _sessions = const [];

  @override
  void dispose() {
    _streamSub?.cancel();
    _stillWorkingTimer?.cancel();
    _api?.dispose();
    _wsClient.dispose();
    super.dispose();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // --- Étape 4 : suivi de l'activité stream (local + broadcast) ---
  void _onStreamStarted() {
    _activeStreamCount++;
    if (_activeStreamCount == 1) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = Timer(_stillWorkingDelay, () {
        if (mounted && _activeStreamCount > 0) {
          setState(() => _showStillWorking = true);
        }
      });
    }
  }

  void _onStreamEnded() {
    if (_activeStreamCount > 0) _activeStreamCount--;
    if (_activeStreamCount == 0) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = null;
      if (_showStillWorking && mounted) {
        setState(() => _showStillWorking = false);
      }
    }
  }

  void _handleSendMessage(String text) {
    final api = _api;
    setState(() {
      _messages.add(ChatMessage(
        id: 'm${++_messageCounter}',
        sender: 'user',
        text: text,
        timestamp: _timestamp(),
      ));
    });

    if (api == null) return;

    _streamSub?.cancel();
    _onStreamEnded(); // l'ancien stream (si encore actif) ne compte plus
    final assistantId = 'a${++_messageCounter}';
    setState(() {
      _messages.add(ChatMessage(
        id: assistantId,
        sender: 'assistant',
        text: '',
        timestamp: _timestamp(),
        isStreaming: true,
      ));
    });

    var thoughtBuffer = StringBuffer();
    _onStreamStarted(); // Étape 4 : le stream local démarre
    _streamSub = api.sendPrompt(_activeSessionId, text).listen(
      (msg) {
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        if (!mounted) return;
        setState(() {
          if (textDelta.isNotEmpty || thoughtDelta.isNotEmpty) {
            final idx = _messages.indexWhere((m) => m.id == assistantId);
            if (idx >= 0) {
              final current = _messages[idx];
              thoughtBuffer.write(thoughtDelta);
              _messages[idx] = current.copyWith(
                text: current.text + textDelta,
                thought: thoughtBuffer.isNotEmpty
                    ? 'Thought · ${thoughtBuffer.toString().trim()}'
                    : current.thought,
              );
            }
          }
          if (approval != null) {
            _pendingApproval = ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            );
            _pendingApprovalCallIds.add(approval.callId);
            final hostActive = msg['data']?['hostActive'] == true;
            if (!hostActive) {
              ApprovalNotifier.instance.notifyApprovalRequired(
                callId: approval.callId,
                toolName: approval.tool,
                command: approval.command,
              );
            }
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        _onStreamEnded();
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        _onStreamEnded();
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(
              text: _messages[idx].text.isEmpty
                  ? '⚠ Erreur : $e'
                  : _messages[idx].text,
              isStreaming: false,
            );
          }
        });
      },
    );
  }

  void _handleToolDecision(ToolDecision decision) {
    final approval = _pendingApproval;
    setState(() {
      _pendingApproval = null;
    });
    if (approval == null) return;
    // L'utilisateur a répondu : on retire la notification de la barre.
    ApprovalNotifier.instance.cancelApproval(approval.callId);
    _pendingApprovalCallIds.remove(approval.callId);
    _api?.submitApproval(
      cascadeId: approval.cascadeId.isEmpty
          ? _activeSessionId
          : approval.cascadeId,
      callId: approval.callId,
      allow: decision == ToolDecision.allow,
      trajectoryId: approval.trajectoryId,
      stepIndex: approval.stepIndex,
      approvalType: approval.approvalType,
      command: approval.command,
    ).catchError((_) => <String, dynamic>{});
  }

  /// Étape 4 — Reminders contextuels : bannières au-dessus du fil.
  Widget _buildReminderBanners() {
    final children = <Widget>[];
    if (_showStillWorking) {
      children.add(_ReminderBanner(
        icon: Icons.hourglass_top_outlined,
        message: 'La tâche tourne toujours — suivez la depuis le téléphone',
      ));
    }
    final pendingApprovals = _pendingApprovalCallIds.length;
    if (pendingApprovals >= 2) {
      children.add(_ReminderBanner(
        icon: Icons.pan_tool_alt_outlined,
        message: 'Approuvez les appels d\'outils depuis le téléphone',
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final banner in children) ...[banner, const SizedBox(height: 8)],
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _wsClient.statusNotifier.value;
    final isConnected = status == ConnectionStatus.connected;

    return Scaffold(
      key: _scaffoldKey,
      drawer: LeftSidebarDrawer(
        activeSessionId: _activeSessionId,
        sessions: _sessions,
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
            MaterialPageRoute(
              builder: (context) => DiscoveryScreen(
                onConnect: (host, port, token) async {
                  final url = host.startsWith('ws') ? host : 'ws://$host:$port/ws';
                  _wsClient.disconnect();
                  await _wsClient.connect(customUrl: url, authToken: token);
                  return _wsClient.statusNotifier.value == ConnectionStatus.connected;
                },
              ),
            ),
          );
        },
        onOpenWorkspace: () {
          final activeSession = _sessions.firstWhere(
            (s) => s.id == _activeSessionId,
            orElse: () => const CascadeSession(id: '', workspacePath: '.', title: '', status: '', time: ''),
          );
          var path = activeSession.workspacePath;
          if (path.startsWith('file:///')) {
            path = path.substring(8);
          } else if (path.startsWith('file://')) {
            path = path.substring(7);
          }
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WorkspaceScreen(
                api: _api,
                workspacePath: path,
              ),
            ),
          );
        },
      ),
      endDrawer: RightSidebarDrawer(
        subagentsCount: _contextStats['subagentsCount'] as int? ?? 0,
        filesChangedCount: _contextStats['filesChangedCount'] as int? ?? 0,
        artifactsCount: _contextStats['artifactsCount'] as int? ?? 0,
        uploadsCount: _contextStats['uploadsCount'] as int? ?? 0,
        backgroundTasksCount: _contextStats['backgroundTasksCount'] as int? ?? 0,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.dock_outlined, size: 20, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Ouvrir le menu gauche',
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$_activeProjectName / $_activeSessionTitle',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  // Reconnect using the previously saved URL and token if available
                  // Note: Since connect() remembers _targetUrl, we just call connect()
                  _wsClient.connect();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.positive.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? AppColors.positive : Theme.of(context).colorScheme.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isConnected ? AppColors.positive : Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        isConnected ? 'Connected' : 'Offline',
                        key: ValueKey<bool>(isConnected),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isConnected ? AppColors.positive : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
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
            icon: Icon(Icons.change_history, size: 14, color: Theme.of(context).colorScheme.primary),
            label: Text(
              'Open IDE',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
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
            icon: Icon(Icons.vertical_split_outlined, size: 20, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Ouvrir le panneau contexte',
          ),
        ],
      ),
      body: _messages.isEmpty && _pendingApproval == null
          ? Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            _activeProjectName,
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ChatInputBar(
                        onSend: _handleSendMessage,
                      ),
                      const SizedBox(height: 64),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                // Messages Timeline
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      _buildReminderBanners(),
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

class _ReminderBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ReminderBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: scheme.onPrimaryContainer),
            ),
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Text(
            widget.message.text,
            style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isThoughtExpanded ? Icons.chevron_right : Icons.expand_more,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Assistant Response Text (Markdown-rendered)
          MarkdownBubble(
            text: widget.message.text,
            isStreaming: widget.message.isStreaming,
          ),

          const SizedBox(height: 8),

          // Message Action Icons (Copy, Like, Dislike)
          Row(
            children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.message.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copié dans le presse-papiers'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.thumb_up_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Icon(Icons.thumb_down_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}
