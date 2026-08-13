import 'dart:async';
import 'dart:ui' as ui;

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
import 'services/settings_store.dart';
import 'widgets/right_sidebar_drawer.dart';

void main() {
  runApp(const AntigravityRemoteApp());
}

class AntigravityRemoteApp extends StatefulWidget {
  const AntigravityRemoteApp({super.key});

  @override
  State<AntigravityRemoteApp> createState() => _AntigravityRemoteAppState();
}

class _AntigravityRemoteAppState extends State<AntigravityRemoteApp> {
  int _themeModeIndex = 0; // 0: system, 1: light, 2: dark

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final s = await SettingsStore.load();
      if (!mounted) return;
      setState(() => _themeModeIndex = (s['themeMode'] as int?) ?? 0);
    } catch (_) {
      // Tests sans mock SharedPreferences : thème système par défaut.
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = (_themeModeIndex >= 0 && _themeModeIndex < 3) ? _themeModeIndex : 0;
    return MaterialApp(
      title: 'Antigravity Mobile',
      debugShowCheckedModeBanner: false,
      // Feature #6 : respecter les préférences système (clair/sombre) au lieu
      // de forcer le dark mode. ThemeMode.system délègue à MediaQuery.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.values[idx],
      home: AntigravityMainScreen(
        themeModeIndex: idx,
        onThemeModeChanged: (i) => setState(() => _themeModeIndex = i),
      ),
    );
  }
}

class AntigravityMainScreen extends StatefulWidget {
  const AntigravityMainScreen({
    super.key,
    this.themeModeIndex = 0,
    required this.onThemeModeChanged,
  });

  final int themeModeIndex;
  final ValueChanged<int> onThemeModeChanged;

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

  Map<String, dynamic> _savedSettings = const {};

  @override
  void initState() {
    super.initState();
    _prevStatus = _wsClient.statusNotifier.value;
    _wsClient.statusNotifier.addListener(_onStatusChanged);
    ApprovalNotifier.instance.init();
    // Auto-connexion : réglages persistés (host/port/ssl/token) si présents,
    // sinon repli sur la config d'environnement. `adb reverse tcp:8090` + jeton
    // par défaut restent le chemin dev.
    // ponytail: plafond connu — pas de persistance de l'appairage; le QR /
    // discovery reste le chemin production.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectWithSavedSettings();
    });
  }

  Future<void> _connectWithSavedSettings() async {
    try {
      final s = await SettingsStore.load();
      if (!mounted) return;
      _savedSettings = s;
      final host = (s['host'] as String?)?.trim() ?? '';
      final port = (s['port'] as int?) ?? 8090;
      final ssl = (s['ssl'] as bool?) ?? false;
      final csrf = (s['csrf'] as String?)?.trim() ?? '';
      if (host.isEmpty) {
        _wsClient.connect(authToken: EnvConfig.authToken);
        return;
      }
      final url = '${ssl ? 'wss' : 'ws'}://$host:$port/ws';
      _wsClient.connect(
        customUrl: url,
        authToken: csrf.isNotEmpty ? csrf : EnvConfig.authToken,
      );
    } catch (_) {
      // Tests sans mock SharedPreferences : repli sur la config par défaut.
      if (mounted) _wsClient.connect(authToken: EnvConfig.authToken);
    }
  }

  /// Applique les réglages daemon sauvegardés depuis Settings : reconnexion
  /// immédiate sur la nouvelle cible.
  void _applyDaemonSettings(Map<String, dynamic> v) {
    setState(() => _savedSettings = v);
    final host = (v['host'] as String?)?.trim() ?? '';
    final port = (v['port'] as int?) ?? 8090;
    final ssl = (v['ssl'] as bool?) ?? false;
    final csrf = (v['csrf'] as String?)?.trim() ?? '';
    final url = '${ssl ? 'wss' : 'ws'}://$host:$port/ws';
    _wsClient.disconnect();
    _wsClient.connect(
      customUrl: url,
      authToken: csrf.isNotEmpty ? csrf : EnvConfig.authToken,
    );
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
      extendBodyBehindAppBar: true,
      drawer: LeftSidebarDrawer(
        activeSessionId: _activeSessionId,
        sessions: _sessions,
        isConnected: isConnected,
        onToggleConnection: () {
          if (isConnected) {
            _wsClient.disconnect();
          } else {
            _wsClient.connect();
          }
        },
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
        onConversationHistory: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conversation History - Coming soon!')),
          );
        },
        onScheduledTasks: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled Tasks - Coming soon!')),
          );
        },
        onOpenSettings: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SettingsScreen(
                initialSettings: _savedSettings,
                onThemeModeChanged: widget.onThemeModeChanged,
                onDaemonSaved: _applyDaemonSettings,
                api: _api,
                notifier: ApprovalNotifier.instance,
              ),
            ),
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
        api: _api,
        activeSessionId: _activeSessionId,
        subagentsCount: _contextStats['subagentsCount'] as int? ?? 0,
        filesChangedCount: _contextStats['filesChangedCount'] as int? ?? 0,
        artifactsCount: _contextStats['artifactsCount'] as int? ?? 0,
        uploadsCount: _contextStats['uploadsCount'] as int? ?? 0,
        backgroundTasksCount: _contextStats['backgroundTasksCount'] as int? ?? 0,
      ),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(color: Colors.transparent),
          ),
        ),
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
