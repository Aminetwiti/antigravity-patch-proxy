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
import 'theme/app_theme.dart';
import 'features/sessions/sessions_list.dart';
import 'features/sessions/conversation_history_screen.dart';
import 'features/scheduled_tasks/scheduled_tasks_screen.dart';
import 'services/settings_store.dart';
import 'widgets/remote_terminal_sheet.dart';
import 'widgets/right_sidebar_drawer.dart';

void main() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xFF1E1E24), // Fallback dark surface
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Erreur de rendu UI',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              details.exceptionAsString(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  };
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
  List<ProjectItem> _projects = const [];
  // Bug #15 : guard pour éviter le double fetch concurrent de sessions.
  bool _sessionsFetching = false;

  ConnectionStatus _prevStatus = ConnectionStatus.disconnected;

  Map<String, dynamic> _savedSettings = const {};

  @override
  void initState() {
    super.initState();
    _prevStatus = _wsClient.statusNotifier.value;
    _wsClient.statusNotifier.addListener(_onStatusChanged);
    // Sauvegarde la session à chaque connexion réussie : URL ws complète + token
    // (le tunnel Cloudflare change d'URL à chaque redémarrage du daemon).
    _wsClient.onSessionEstablished = (url, token) {
      SettingsStore.saveSession(wsUrl: url, token: token, sessionId: _activeSessionId);
    };
    // Token obsolète (daemon redémarré avec un nouveau --auth-token) :
    // on efface la session persistée ET le csrf des réglages (le serveur
    // vient de rejeter ce token : il est définitivement invalide), puis on
    // retente immédiatement — sinon ~30 s de 401 en boucle.
    _wsClient.onAuthRejected = () async {
      final hadSession = (await SettingsStore.loadSession()).isNotEmpty;
      SettingsStore.clearSession();
      SettingsStore.save({'csrf': ''});
      // Garde anti-boucle : si aucune session n'existait, on ne relance pas
      // (le backoff de _handleDisconnect s'en charge) pour ne pas créer une
      // boucle infinie de reconnexions 401.
      if (hadSession) {
        _connectWithSavedSettings();
      }
    };
    // URL de tunnel morte (530/502 Cloudflare, daemon redémarré avec un
    // nouveau tunnel) : on efface la session obsolète et on retente sur le
    // fallback LAN (réglages host/port) — le daemon répond toujours en local.
    _wsClient.onEndpointDead = () async {
      final hadSession = (await SettingsStore.loadSession()).isNotEmpty;
      SettingsStore.clearSession();
      if (hadSession) {
        _connectWithSavedSettings();
      }
    };
    ApprovalNotifier.instance.init();
    // Restaure la dernière session active (si encore valide) sans attendre
    // la liste distante — l'UI affiche immédiatement le bon contexte.
    SettingsStore.loadSession().then((s) {
      if (!mounted || s.isEmpty) return;
      final sid = s['sessionId'] as String? ?? '';
      if (sid.isNotEmpty) {
        setState(() => _activeSessionId = sid);
      }
    });
    // Auto-connexion : session persistée < 24 h en priorité (reconnexion
    // directe au tunnel), sinon réglages host/port/ssl/token, sinon repli sur
    // la config d'environnement. `adb reverse tcp:8090` + jeton par défaut
    // restent le chemin dev.
    // ponytail: plafond connu — la session expire après 24 h; le QR /
    // discovery reste le chemin de re-appairage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectWithSavedSettings();
    });
  }

  Future<void> _connectWithSavedSettings() async {
    try {
      // Priorité 1 : session < 24 h → reconnexion directe au tunnel
      // sauvegardé (URL Cloudflare complète + token), sans re-scan QR.
      final session = await SettingsStore.loadSession();
      if (mounted && session.isNotEmpty) {
        final url = session['wsUrl'] as String? ?? '';
        final token = session['token'] as String? ?? '';
        if (url.isNotEmpty) {
          _wsClient.connect(
            customUrl: url,
            authToken: token.isNotEmpty ? token : EnvConfig.authToken,
          );
          return;
        }
      }
      // Priorité 2 : réglages persistés (host/port/ssl/token).
      final s = await SettingsStore.load();
      if (!mounted) return;
      _savedSettings = s;
      final host = (s['host'] as String?)?.trim() ?? '';
      final port = (s['port'] as int?) ?? EnvConfig.daemonPort;
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

  static String _formatWsUrl(String host, int port) {
    final cleanHost = host.trim();
    if (cleanHost.startsWith('ws://') || cleanHost.startsWith('wss://')) {
      return cleanHost.endsWith('/ws') ? cleanHost : '$cleanHost/ws';
    }
    if (cleanHost.startsWith('https://')) {
      final bare = cleanHost.substring('https://'.length);
      return 'wss://$bare/ws';
    }
    if (cleanHost.startsWith('http://')) {
      final bare = cleanHost.substring('http://'.length);
      return 'ws://$bare/ws';
    }
    if (port == 443 || cleanHost.contains('trycloudflare.com') || cleanHost.contains('pinggy')) {
      return 'wss://$cleanHost/ws';
    }
    return 'ws://$cleanHost:$port/ws';
  }

  /// Applique les réglages daemon sauvegardés depuis Settings : reconnexion
  /// immédiate sur la nouvelle cible.
  void _applyDaemonSettings(Map<String, dynamic> v) {
    setState(() => _savedSettings = v);
    final host = (v['host'] as String?)?.trim() ?? '';
    final port = (v['port'] as int?) ?? EnvConfig.daemonPort;
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
      // Persiste la session (URL tunnel + token + sessionId) : le tunnel
      // Cloudflare change d'URL à chaque redémarrage du daemon, on re-sauvegarde
      // donc à chaque connexion réussie, y compris les reconnexions.
      SettingsStore.saveSession(
        wsUrl: _wsClient.targetUrl,
        token: _wsClient.authToken ?? '',
        sessionId: _activeSessionId,
      );
      _api?.dispose();
      _api = DaemonApi(
        incoming: _wsClient.stream,
        send: _wsClient.send,
        outbox: _outbox,
      );
      _api!.attachReconnect(
        _wsClient.reconnectVersion,
        _resyncSessions,
      );
      _watchSessionEvents();
      _refreshSessions();
      _refreshContext();
      _applySavedApprovalSettings();
    }
  }

  /// Re-synchronise les réglages d'approbation persistés vers le daemon à
  /// chaque (re)connexion : le daemon ne persiste rien, il faut donc lui
  /// ré-appliquer le délai d'auto-refus et l'auto-accept read-only après un
  /// redémarrage (du daemon ou de l'app).
  Future<void> _applySavedApprovalSettings() async {
    final api = _api;
    if (api == null) return;
    try {
      final s = await SettingsStore.load();
      final timeout = (s['approvalTimeoutMinutes'] as int?) ?? 5;
      await api.sendWithResult('set_approval_timeout', {
        'data': {'minutes': timeout},
      });
      final autoAccept = (s['autoAcceptEnabled'] as bool?) ?? false;
      await api.setAutoAccept(enabled: autoAccept);
    } catch (_) {
      // Réglages décoratifs : sans daemon, on ignore silencieusement.
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
    } catch (e) {
      // C3 (audit clean-code-guard) : silencieux auparavant — le contexte
      // (compteurs sidebar droite) est décoratif, on logge sans alerter.
      debugPrint('refreshContext failed: $e');
    }
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

      List<ProjectItem> projects = [];
      if (data['projects'] is List) {
        projects = (data['projects'] as List)
            .map((p) => ProjectItem.fromJson(p as Map<String, dynamic>))
            .toList();
      }

      if (mounted) {
        setState(() {
          if (projects.isNotEmpty) {
            _projects = projects;
          }
          if (sessions.isNotEmpty) {
            final stillActive = sessions.any((s) => s.id == _activeSessionId);
            _sessions = sessions;
            if (!stillActive || _activeSessionId == 's3') {
              _activeSessionId = sessions.first.id;
              _activeSessionTitle = sessions.first.title;
            } else {
              final cur = sessions.firstWhere((s) => s.id == _activeSessionId);
              _activeSessionTitle = cur.title;
            }
          }
        });
        if (sessions.isNotEmpty) {
          SettingsStore.saveSession(
            wsUrl: _wsClient.targetUrl,
            token: _wsClient.authToken ?? '',
            sessionId: _activeSessionId,
          );
        }
      }
    } catch (_) {
    } finally {
      _sessionsFetching = false;
    }
  }

  /// Rafraîchit la liste des sessions à chaque événement daemon (stream_end,
  /// approval_expired, …) pour que le sidebar reste synchronisé en direct.
  /// ponytail: rafraîchissement plein — pas de delta — plafond acceptable pour
  /// un volume faible de sessions ; à affiner si le daemon émet > 5 events/s.
  StreamSubscription<Map<String, dynamic>>? _sessionsSub;

  void _watchSessionEvents() {
    _sessionsSub?.cancel();
    _sessionsSub = _api?.events.listen((msg) {
      if (!mounted) return;
      final type = msg['type'] as String?;
      // stream_delta à haute fréquence → on ne rafraîchit qu'à la fin du
      // stream et sur les événements discrets (approbation expirée, etc.).
      if (type == 'stream_delta') return;
      _refreshSessions();
    });
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

  void _showSessionHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConversationHistoryScreen(
          sessions: _sessions,
          activeSessionId: _activeSessionId,
          onRefresh: _refreshSessions,
          onSessionSelected: (id) {
            setState(() {
              _activeSessionId = id;
              final s = _sessions.firstWhere(
                (s) => s.id == id,
                orElse: () => const CascadeSession(
                  id: '',
                  workspacePath: '',
                  title: 'Session',
                  status: '',
                  time: '',
                ),
              );
              _activeSessionTitle = s.title;
            });
            _refreshContext();
          },
        ),
      ),
    );
  }

  /// Stub scheduled tasks : la liste est vide tant que le daemon n'expose pas
  /// de RPC tasks ; l'écran affiche l'empty state et les callbacks sont des
  /// no-ops sûrs.
  /// ponytail: stub volontaire (M5) — pas de tâches planifiées réelles côté
  /// daemon aujourd'hui ; à brancher sur un RPC `list_scheduled_tasks` quand
  /// il existera, sans changer la signature de ScheduledTasksScreen.
  void _showScheduledTasks() {
    final workspaces = _sessions
        .map((s) {
          var clean = s.workspacePath.replaceAll('\\', '/');
          if (clean.startsWith('file:///')) clean = clean.substring(8);
          if (clean.startsWith('file://')) clean = clean.substring(7);
          final segs = clean.split('/').where((p) => p.isNotEmpty).toList();
          return segs.isNotEmpty ? segs.last : 'Outside of Project';
        })
        .toSet()
        .toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScheduledTasksScreen(
          tasks: const [],
          api: _api,
          workspaces: workspaces.isNotEmpty ? workspaces : ['antigravity-add-model-main'],
          onTriggerNow: (id) => _api?.triggerScheduledTask(id),
          onCancelTask: (id) => _api?.cancelScheduledTask(id),
          onToggleTask: (id, enabled) {},
          onAddTask: (task) => _api?.scheduleTask(task),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
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
        projects: _projects,
        isConnected: isConnected,
        onToggleConnection: () {
          if (isConnected) {
            _wsClient.disconnect();
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DiscoveryScreen(
                  onConnect: (host, port, token) async {
                    final url = _formatWsUrl(host, port);
                    _wsClient.disconnect();
                    await _wsClient.connect(customUrl: url, authToken: token);
                    return _wsClient.statusNotifier.value == ConnectionStatus.connected;
                  },
                ),
              ),
            );
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
        onNewConversation: () async {
          final api = _api;
          if (api == null) return;
          try {
            var ws = _sessions.isNotEmpty ? _sessions.first.workspacePath : '';
            if (ws.isEmpty) {
              final cur = _sessions.where((s) => s.id == _activeSessionId);
              if (cur.isNotEmpty) ws = cur.first.workspacePath;
            }
            final res = await api.createCascade(ws);
            String newId = '';
            if (res['cascadeId'] is String) {
              newId = res['cascadeId'] as String;
            } else if (res['id'] is String) {
              newId = res['id'] as String;
            } else if (res['fields'] is List) {
              for (final f in res['fields']) {
                if (f is Map && f['text'] is String && (f['text'] as String).isNotEmpty) {
                  newId = f['text'] as String;
                  break;
                }
              }
            }
            if (newId.isNotEmpty && mounted) {
              setState(() {
                _activeSessionId = newId;
                _activeSessionTitle = 'Nouvelle conversation';
              });
              await _refreshSessions();
            }
          } catch (_) {}
        },
        onConversationHistory: () {
          _showSessionHistory();
        },
        onScheduledTasks: () {
          _showScheduledTasks();
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
                  final url = _formatWsUrl(host, port);
                  _wsClient.disconnect();
                  await _wsClient.connect(customUrl: url, authToken: token);
                  final ok = _wsClient.statusNotifier.value == ConnectionStatus.connected;
                  if (ok) {
                    // Persiste l'appairage : le tunnel Cloudflare peut avoir
                    // changé d'URL depuis la dernière sauvegarde.
                    SettingsStore.saveSession(
                      wsUrl: url,
                      token: token,
                      sessionId: _activeSessionId,
                    );
                  }
                  return ok;
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
                  // Déconnexion manuelle explicite : la session persistée est
                  // oubliée pour ne pas se reconnecter toute seule au tunnel.
                  SettingsStore.clearSession();
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
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
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
                        color: isConnected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        isConnected ? '💻 PC Direct' : 'Offline',
                        key: ValueKey<bool>(isConnected),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isConnected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
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
            icon: Icon(Icons.terminal_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              HapticFeedback.selectionClick();
              RemoteTerminalSheet.show(
                context,
                api: _api,
                projectName: _activeProjectName,
              );
            },
            tooltip: 'Ouvrir le terminal distant',
          ),
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



