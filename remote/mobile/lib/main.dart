import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/env_config.dart';
import 'core/network/outbox.dart';
import 'core/network/websocket_client.dart';
import 'core/notifications/approval_notifier.dart';
import 'core/protocol/daemon_api.dart';
import 'core/protocol/messages.dart';
import 'core/protocol/session_parser.dart';
import 'features/chat_stream/chat_stream_screen.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/workspace/workspace_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'features/sessions/sessions_list.dart';
import 'widgets/right_sidebar_drawer.dart';

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
      // Feature #6 : respecter les préférences système (clair/sombre) au lieu
      // de forcer le dark mode. ThemeMode.system délègue à MediaQuery.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
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

  DaemonApi? _api;
  Map<String, dynamic> _contextStats = {};

  final OutboxQueue _outbox = OutboxQueue();

  List<CascadeSession> _sessions = const [];
  // Bug #15 : guard pour éviter le double fetch concurrent de sessions.
  bool _sessionsFetching = false;

  ConnectionStatus _prevStatus = ConnectionStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _prevStatus = _wsClient.statusNotifier.value;
    _wsClient.statusNotifier.addListener(_onStatusChanged);
    ApprovalNotifier.instance.init();
    // Auto-connexion dev : `adb reverse tcp:8090` + jeton par défaut.
    // ponytail: plafond connu — pas de persistance de l'appairage; le QR /
    // discovery reste le chemin production.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsClient.connect(authToken: EnvConfig.authToken);
    });
  }

  void _onStatusChanged() {
    if (!mounted) return;
    
    final currentStatus = _wsClient.statusNotifier.value;
    if (_prevStatus != currentStatus) {
      if (currentStatus == ConnectionStatus.disconnected || currentStatus == ConnectionStatus.error) {
        HapticFeedback.heavyImpact();
      } else if (currentStatus == ConnectionStatus.connected) {
        HapticFeedback.lightImpact();
      }
      _prevStatus = currentStatus;
    }

    setState(() {});
    if (currentStatus == ConnectionStatus.connected) {
      _api ??= DaemonApi(
        incoming: _wsClient.stream,
        send: _wsClient.send,
        outbox: _outbox,
      );
      _api!.attachReconnect(
        _wsClient.reconnectVersion,
        _resyncSessions,
      );
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

  Future<void> _refreshSessions() async {
    // Bug #15 : évite le double appel concurrent (connexion + reconnectVersion).
    if (_sessionsFetching) return;
    _sessionsFetching = true;
    final api = _api;
    if (api == null) { _sessionsFetching = false; return; }
    try {
      final data = await api.listSessions();
      final sessions = SessionParser.parseListSessions(data);
      if (sessions.isNotEmpty) {
        setState(() {
          _sessions = sessions;
          _activeSessionId = sessions.first.id;
          _activeSessionTitle = sessions.first.title;
        });
      }
    } catch (_) {
    } finally {
      _sessionsFetching = false;
    }
  }

  Future<Map<String, dynamic>> _resyncSessions() async {
    final api = _api;
    if (api == null) return const {};
    try {
      await _refreshSessions();
      return const {'ok': true};
    } catch (_) {
      return const {};
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    _wsClient.dispose();
    super.dispose();
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
            final s = _sessions.firstWhere((s) => s.id == id, orElse: () => const CascadeSession(id: '', workspacePath: '', title: 'Session', status: '', time: ''));
            _activeSessionTitle = s.title;
          });
          // Bug #2 : rafraîchir le contexte pour la nouvelle session.
          _refreshContext();
        },
        onNewConversation: () {
          setState(() {
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
            InkWell(
              onTap: () {
                if (isConnected) {
                  _wsClient.disconnect();
                } else {
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
          IconButton(
            icon: Icon(Icons.vertical_split_outlined, size: 20, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Ouvrir le panneau contexte',
          ),
        ],
      ),
      body: ChatStreamScreen(
        api: _api,
        activeSessionId: _activeSessionId,
        activeProjectName: _activeProjectName,
        isConnected: isConnected,
        wsClient: _wsClient,
      ),
    );
  }
}
