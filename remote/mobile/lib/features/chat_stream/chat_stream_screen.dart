import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/websocket_client.dart';
import '../../core/notifications/approval_notifier.dart';
import '../../core/protocol/daemon_api.dart';
import '../../core/protocol/markdown_renderer.dart';
import '../../core/protocol/messages.dart';
import '../../core/protocol/stream_parser.dart';
import '../../widgets/ask_question_choice_card.dart';
import '../../widgets/chat_input_bar.dart';
import '../../widgets/connection_banner.dart';
import '../../widgets/markdown_bubble.dart';
import '../../widgets/tool_approval_card.dart';
import '../../widgets/session_top_tabs.dart';
import '../../widgets/artifact_cards.dart';
import '../../widgets/side_question_card.dart';
import '../../widgets/background_tasks_bar.dart';
import '../../widgets/background_task_output_sheet.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/unified_diff_viewer.dart';
import '../../widgets/artifact_viewer_modal.dart';
import '../../widgets/project_selector_bottom_sheet.dart';
import '../../widgets/session_breadcrumb.dart';
import 'widgets/execution_progress_view.dart';
import 'widgets/overview_panel_view.dart';
import 'widgets/session_review_view.dart';
import 'widgets/queued_messages_card.dart';
import '../subagents/subagents_tree_sheet.dart';
import '../subagents/models/subagent_item.dart';
import '../subagents/widgets/subagent_tree_card.dart';
import 'package:mobile/theme/app_colors.dart';

class ChatStreamScreen extends StatefulWidget {
  final DaemonApi? api;
  final String activeSessionId;
  final String activeProjectName;
  final String? activeSessionTitle;
  final bool isConnected;

  /// Client WebSocket partagé (null en tests/aperçu) — fournit l'état de
  /// connexion en temps réel (statut, tentative, compte à rebours) au banner.
  final DaemonWebSocketClient? wsClient;

  /// Notifie le parent (main.dart) du changement d'état de streaming pour
  /// une session spécifique afin de mettre à jour son statut dans la barre latérale.
  final void Function(String sessionId, bool isStreaming)? onStreamingSessionChanged;

  /// Notifie le parent (main.dart) du changement d'état de streaming global.
  final ValueChanged<bool>? onStreamingStateChanged;

  /// Crée une nouvelle conversation (bouton « + » des tabs). Laissé au parent
  /// (main.dart) : il connaît la liste des sessions et le workspace actif.
  final VoidCallback? onNewConversation;

  /// Workspace racine pour la détection VCS et fichiers modifiés.
  final String? workspacePath;

  /// Liste des projets officiels disponibles
  final List<ProjectItem>? projects;

  /// Callback de changement de projet workspace
  final void Function(ProjectItem project)? onSelectProject;

  const ChatStreamScreen({
    super.key,
    required this.api,
    required this.activeSessionId,
    required this.activeProjectName,
    this.activeSessionTitle,
    this.workspacePath,
    this.projects,
    this.onSelectProject,
    this.isConnected = true,
    this.wsClient,
    this.onStreamingSessionChanged,
    this.onStreamingStateChanged,
    this.onNewConversation,
  });

  @override
  State<ChatStreamScreen> createState() => _ChatStreamScreenState();
}

class _ChatStreamScreenState extends State<ChatStreamScreen>
    with WidgetsBindingObserver {
  // Bug #9 : messages sauvegardés par session pour ne pas les perdre lors d'un
  // changement d'onglet pendant un stream actif.
  // ponytail: Map simple, pas de provider — l'historique n'est pas persisté sur
  // disque (session restart repart de zéro, ce qui est le comportement voulu).
  final Map<String, List<ChatMessage>> _sessionMessages = {};
  final Map<String, List<Map<String, dynamic>>> _sessionMessageQueues = {};

  List<ChatMessage> get _messages {
    return _sessionMessages.putIfAbsent(widget.activeSessionId, () => []);
  }

  // P6 : brouillons persistés par session — SharedPreferences pour survivre
  // au switch de session/onglet ET au redémarrage de l'app.
  // ponytail: getter/setter synchrones sur cache mémoire + écriture fire-and-forget
  // (même schéma que P4 pinning). Pas de debounce : chaque setDraft écrit ~2-3x
  // par seconde au pire, SharedPreferences supporte très bien ce débit.
  static const String _draftPrefsPrefix = 'session_draft_';
  static final Map<String, String> _draftCache = {};
  String get currentDraft => _draftCache[widget.activeSessionId] ?? '';
  void setDraft(String draft) {
    _draftCache[widget.activeSessionId] = draft;
    SharedPreferences.getInstance().then((prefs) => prefs.setString(
        '$_draftPrefsPrefix${widget.activeSessionId}', draft));
  }

  // File d'attente des approbations : isolée par session
  final Map<String, List<ToolApprovalRequest>> _sessionApprovals = {};
  final Map<String, int> _sessionApprovalIndices = {};

  // Questions interactives à choix multiples (AskQuestion) : isolée par session
  final Map<String, List<AskQuestionChoiceRequest>> _sessionQuestions = {};

  // callIds dont le daemon a broadcasté approval_expired : la carte reste
  // affichée (pourquoi elle a disparu) mais passe en lecture seule.
  final Set<String> _expiredCallIds = {};

  List<AskQuestionChoiceRequest> get _currentSessionQuestions =>
      _sessionQuestions.putIfAbsent(widget.activeSessionId, () => []);

  List<ToolApprovalRequest> get _currentSessionApprovals =>
      _sessionApprovals.putIfAbsent(widget.activeSessionId, () => []);

  int get _approvalIndex =>
      _sessionApprovalIndices[widget.activeSessionId] ?? -1;
  set _approvalIndex(int idx) =>
      _sessionApprovalIndices[widget.activeSessionId] = idx;

  ToolApprovalRequest? get _currentApproval {
    final list = _currentSessionApprovals;
    if (list.isEmpty) return null;
    final idx = _approvalIndex;
    if (idx < 0 || idx >= list.length) {
      return list.first;
    }
    return list[idx];
  }

  StreamSubscription<Map<String, dynamic>>? _streamSub;
  StreamSubscription<Map<String, dynamic>>? _tapSub;
  int _messageCounter = 0;

  static const _stillWorkingDelay = Duration(seconds: 15);
  final Set<String> _pendingApprovalCallIds = {};
  final Set<String> _processedCallIds = {};
  Timer? _stillWorkingTimer;
  final List<Timer> _settleTimers = [];
  
  // Streaming multi-session : ensemble des sessions actuellement en train de streamer
  final Set<String> _activeStreamingSessions = {};
  int get _activeStreamCount => _activeStreamingSessions.length;
  bool get _hasCurrentActiveStream => _activeStreamingSessions.contains(widget.activeSessionId);
  
  bool _showStillWorking = false;
  final Map<String, Map<String, dynamic>> _sessionLastStreamEnds = {};
  final Map<String, String> _externalThoughts = {};
  final Map<String, String> _streamRequestToMessageId = {};

  Timer? _throttleTimer;
  bool _needsStateUpdate = false;
  static const _throttleDuration = Duration(milliseconds: 25);

  // Bug persistance pensées : état d'expansion stocké ici par message ID
  // pour survivre aux switches de session et aux rebuilds de la liste.
  // ponytail: Set suffit (expandé = dans le Set, replié = absent).
  final Set<String> _expandedThoughts = {};

  // Auto-scroll pendant le streaming (audit UX P1-6).
  final ScrollController _scrollController = ScrollController();
  // ignore: prefer_final_fields
  bool _isInitialScrollSettling = true;

  // Bouton flottant « retour en bas » (P1) : visible quand l'utilisateur
  // scrolle loin du bas pendant un stream. Compte les nouveaux messages
  // arrivés pendant qu'il lit l'historique, et se cache dès qu'il revient
  // près du bas (ou tape le bouton).
  bool _showJumpToBottom = false;
  int _hiddenNewCount = 0;

  // ── Session Top Tabs & Artifact state (isolé par session) ───────────
  final Map<String, SessionTabType> _sessionTabs = {};
  SessionTabType get _currentTab => _sessionTabs[widget.activeSessionId] ?? SessionTabType.chat;
  set _currentTab(SessionTabType tab) => _sessionTabs[widget.activeSessionId] = tab;

  final Map<String, Set<String>> _sessionModifiedFiles = {};
  final Map<String, List<SessionModifiedFile>> _sessionModifiedFileList = {};
  final Map<String, List<String>> _sessionArtifacts = {};
  final Map<String, int> _sessionSubagentCounts = {};
  final Map<String, List<SubagentItem>> _sessionSubagents = {};
  final Map<String, String?> _sessionActiveArtifacts = {};
  final Map<String, String?> _sessionPlanTexts = {};

  Set<String> get _modifiedFiles => _sessionModifiedFiles.putIfAbsent(widget.activeSessionId, () => {});
  List<SessionModifiedFile> get _modifiedFileList => _sessionModifiedFileList.putIfAbsent(widget.activeSessionId, () => []);
  List<String> get _artifacts => _sessionArtifacts.putIfAbsent(widget.activeSessionId, () => []);
  int get _subagentsCount => _sessionSubagentCounts[widget.activeSessionId] ?? _subagents.length;
  List<SubagentItem> get _subagents => _sessionSubagents.putIfAbsent(widget.activeSessionId, () => []);
  String? get _activeArtifact => _sessionActiveArtifacts[widget.activeSessionId];
  set _activeArtifact(String? art) => _sessionActiveArtifacts[widget.activeSessionId] = art;
  String? get _latestPlanText => _sessionPlanTexts[widget.activeSessionId];

  List<SessionTabType> get _swipeableTabs => [
        SessionTabType.chat,
        SessionTabType.review,
        SessionTabType.overview,
        if (_latestPlanText != null) SessionTabType.plan,
        if (_hasCurrentActiveStream) SessionTabType.tasks,
      ];

  // ── Side Question (/btw) & Background Tasks state ───────────────────
  final Map<String, String?> _sessionSideQuestions = {};
  final Map<String, String?> _sessionSideQuestionAnswers = {};
  final Map<String, bool> _sessionSideQuestionLoadings = {};

  String? get _sideQuestion => _sessionSideQuestions[widget.activeSessionId];
  set _sideQuestion(String? q) => _sessionSideQuestions[widget.activeSessionId] = q;

  String? get _sideQuestionAnswer => _sessionSideQuestionAnswers[widget.activeSessionId];
  set _sideQuestionAnswer(String? a) => _sessionSideQuestionAnswers[widget.activeSessionId] = a;

  bool get _isSideQuestionLoading => _sessionSideQuestionLoadings[widget.activeSessionId] ?? false;
  set _isSideQuestionLoading(bool l) => _sessionSideQuestionLoadings[widget.activeSessionId] = l;

  final List<String> _runningBackgroundTasks = [];
  final Map<String, StringBuffer> _taskOutputs = {};
  final Map<String, String> _taskStatuses = {};
  final Map<String, StreamController<String>> _taskOutputControllers = {};

  void _openTaskOutputSheet(String taskNameOrId) {
    final initialOut = _taskOutputs[taskNameOrId]?.toString() ?? '';
    final status = _taskStatuses[taskNameOrId] ?? 'running';
    final ctrl = _taskOutputControllers.putIfAbsent(
      taskNameOrId,
      () => StreamController<String>.broadcast(),
    );

    BackgroundTaskOutputSheet.show(
      context,
      taskId: taskNameOrId,
      command: taskNameOrId,
      initialOutput: initialOut,
      status: status,
      outputStream: ctrl.stream,
      onStop: () => _handleStopBackgroundTask(taskNameOrId),
    );
  }

  void _handleStopBackgroundTask(String taskNameOrId) {
    widget.api?.killRunningTask(taskNameOrId);
    setState(() {
      _runningBackgroundTasks.remove(taskNameOrId);
      _taskStatuses[taskNameOrId] = 'killed';
    });
  }

  // ── Sync & Catch-up status ─────────────────────────────────────────
  bool _isSyncing = false;
  Timer? _syncTimer;

  // ── Quota temps réel (P8) ───────────────────────────────────────────
  Map<String, dynamic>? _quotaSummary;
  Timer? _quotaTimer;

  // ── État de connexion live (alimenté par wsClient) ─────────────────────
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _attempt = 0;
  Duration _nextRetryIn = Duration.zero;
  bool _isManualDisconnect = false;
  bool _notifiedLost = false;
  // L'app est au premier plan : le banner suffit, pas besoin de notification
  // locale (qui vise l'écran verrouillé / l'app en arrière-plan).
  bool _appInForeground = true;

  // ── Fenêtre paginée de conversation (Reverse Chunked Pagination) ──
  // Principe : tous les messages sont en mémoire dans _messages (chargés une
  // seule fois depuis l'historique). On n'affiche que les N derniers
  // (_visibleCount). Quand l'utilisateur scrolle vers le haut jusqu'au bord,
  // on incrémente _visibleCount de _pageSize — ce qui révèle les N messages
  // précédents sans aucun appel réseau supplémentaire.
  // Temps de rendu initial = O(1) quel que soit le nombre total de messages.
  static const int _pageSize = 20;
  final Map<String, int> _visibleCounts = {};
  int get _visibleCount =>
      _visibleCounts.putIfAbsent(widget.activeSessionId, () => _pageSize);
  bool _isLoadingMoreOlder = false;

  List<ChatMessage> get _visibleMessages {
    final all = _messages;
    final count = _visibleCount;
    if (all.length <= count) return all;
    return all.sublist(all.length - count);
  }

  int get _hiddenOlderCount {
    final all = _messages;
    final count = _visibleCount;
    if (all.length <= count) return 0;
    return all.length - count;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isInitialScrollSettling) return;
    final pos = _scrollController.position;
    // P1 : bascule du bouton flottant — on ne setState que lors d'un
    // changement d'état (une fois par départ/retour, pas à chaque pixel).
    final nearBottom = (pos.maxScrollExtent - pos.pixels) < 120;
    if (nearBottom != _showJumpToBottom) {
      setState(() {
        _showJumpToBottom = !nearBottom;
        if (nearBottom) _hiddenNewCount = 0;
      });
    }
    if (!_isLoadingMoreOlder && pos.pixels <= 80 && _hiddenOlderCount > 0 && pos.maxScrollExtent > 100) {
      _loadMoreOlderMessages();
    }
  }

  void _jumpToBottom() {
    HapticFeedback.lightImpact();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    setState(() {
      _showJumpToBottom = false;
      _hiddenNewCount = 0;
    });
  }

  void _loadMoreOlderMessages() {
    if (_isLoadingMoreOlder || _hiddenOlderCount <= 0) return;
    setState(() {
      _isLoadingMoreOlder = true;
      final current = _visibleCounts[widget.activeSessionId] ?? _pageSize;
      _visibleCounts[widget.activeSessionId] = current + _pageSize;
    });
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _isLoadingMoreOlder = false;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _watchBroadcastStreams();
    _setupConnectionListeners();
    _watchNotificationTaps();
    // Sans wsClient (tests/aperçu), l'état vient de la prop isConnected.
    if (widget.wsClient == null) {
      _status = widget.isConnected
          ? ConnectionStatus.connected
          : ConnectionStatus.disconnected;
    }
    _loadHistoryIfEmpty();
    _refreshQuotaSummary();
    _quotaTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _refreshQuotaSummary();
    });
    _loadPersistedDraft();
  }

  /// P6 : recharge le brouillon persisté de la session courante dans le cache
  /// mémoire (le widget ChatInputBar lit `currentDraft` à son initState).
  Future<void> _loadPersistedDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || widget.activeSessionId.isEmpty) return;
    _draftCache[widget.activeSessionId] =
        prefs.getString('$_draftPrefsPrefix${widget.activeSessionId}') ?? '';
  }

  Future<void> _refreshQuotaSummary() async {
    final api = widget.api;
    if (api == null || !widget.isConnected) return;
    try {
      final q = await api.getUserQuotaSummary();
      if (mounted) {
        setState(() => _quotaSummary = q);
      }
    } catch (_) {}
  }

  void _scrollToBottomSettled({int maxAttempts = 4}) {
    if (!mounted) return;
    _isInitialScrollSettling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _isInitialScrollSettling = false;
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      for (final t in _settleTimers) {
        t.cancel();
      }
      _settleTimers.clear();
      if (!mounted) return;
      if (maxAttempts > 1) {
        _settleTimers.add(Timer(const Duration(milliseconds: 60), () {
          if (!mounted || !_scrollController.hasClients) {
            _isInitialScrollSettling = false;
            return;
          }
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          if (maxAttempts > 2) {
            _settleTimers.add(Timer(const Duration(milliseconds: 150), () {
              if (!mounted || !_scrollController.hasClients) {
                _isInitialScrollSettling = false;
                return;
              }
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
              if (maxAttempts > 3) {
                _settleTimers.add(Timer(const Duration(milliseconds: 250), () {
                  if (mounted && _scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                  _isInitialScrollSettling = false;
                }));
              } else {
                _isInitialScrollSettling = false;
              }
            }));
          } else {
            _isInitialScrollSettling = false;
          }
        }));
      } else {
        _isInitialScrollSettling = false;
      }
    });
  }

  void _loadHistoryIfEmpty([String? targetSessionId]) {
    final targetSession = targetSessionId ?? widget.activeSessionId;
    _loadSessionContextAndArtifacts(targetSession);
    _fetchVcsChanges();
    if (targetSession.isNotEmpty) {
      widget.api?.getSessionHistory(targetSession).then((data) {
        if (!mounted) return;
        final rawMessages = data['messages'] as List?;
        final parsed = <ChatMessage>[];
        if (rawMessages != null && rawMessages.isNotEmpty) {
          for (final m in rawMessages) {
            if (m is Map) {
              parsed.add(ChatMessage(
                id: m['id']?.toString() ?? '',
                sender: m['sender']?.toString() ?? 'assistant',
                text: m['text']?.toString() ?? '',
                thought: m['thought']?.toString(),
                timestamp: m['timestamp']?.toString() ?? '',
                isError: m['isError'] == true && (m['text']?.toString().trim().isEmpty ?? true),
              ));
            }
          }
        }

        final isStreaming = data['isStreaming'] == true;
        final isStreamingLive = _activeStreamingSessions.contains(targetSession);
        final activeReqId = data['activeRequestId']?.toString() ?? 'live';
        if (isStreaming && !parsed.any((m) => m.id == 'ext-$activeReqId' || m.isStreaming)) {
          parsed.add(ChatMessage(
            id: 'ext-$activeReqId',
            sender: 'assistant',
            text: '',
            timestamp: _timestamp(),
            isStreaming: true,
          ));
        }

        final buf = _sessionMessages.putIfAbsent(targetSession, () => []);
        if (!isStreamingLive) {
          if (parsed.isNotEmpty || buf.isEmpty) {
            buf
              ..clear()
              ..addAll(parsed);
          }
          if (isStreaming) {
            _onStreamStarted(targetSession);
            // Catch up any in-flight live events from the daemon's StepRecovery buffer
            widget.api?.syncSession(cascadeId: targetSession, lastStepIndex: 0);
            if (data['hasPendingApproval'] == true) {
              widget.api?.getPendingApproval(targetSession);
            }
          } else {
            _onStreamEnded(targetSession);
          }
        }

        if (widget.activeSessionId == targetSession) {
          setState(() {});
          _scrollToBottomSettled();
        }
      }).catchError((_) {
        // Ignorer l'erreur
      });
    }
  }

  Future<void> _loadSessionContextAndArtifacts([String? targetSessionId]) async {
    final targetSession = targetSessionId ?? widget.activeSessionId;
    final api = widget.api;
    if (targetSession.isEmpty || api == null) return;
    try {
      final res = await api.getContext(cascadeId: targetSession);
      final rawArts = res['artifacts'] as List<dynamic>? ?? [];
      final artNames = <String>[];
      for (final a in rawArts) {
        if (a is Map && a['name'] != null) {
          artNames.add(a['name'].toString());
        } else if (a is String) {
          artNames.add(a);
        }
      }
      final subCount = (res['subagentsCount'] as int?) ?? 0;
      final plan = res['plan']?.toString() ?? res['latestPlanText']?.toString();
      final rawModFiles = res['modifiedFiles'] as List<dynamic>? ?? [];
      final modFiles = <String>[];
      for (final f in rawModFiles) {
        if (f is String && f.isNotEmpty) {
          modFiles.add(f);
        } else if (f is Map && f['path'] != null) {
          modFiles.add(f['path'].toString());
        }
      }

      if (mounted) {
        if (artNames.isNotEmpty) {
          _sessionArtifacts[targetSession] = artNames;
        }
        _sessionSubagentCounts[targetSession] = subCount;
        if (plan != null && plan.isNotEmpty) {
          _sessionPlanTexts[targetSession] = plan;
        }
        final targetModFiles = _sessionModifiedFiles.putIfAbsent(targetSession, () => {});
        final targetModFileList = _sessionModifiedFileList.putIfAbsent(targetSession, () => []);
        for (final p in modFiles) {
          var clean = p.replaceAll('\\', '/');
          if (clean.startsWith('file:///')) clean = clean.substring(8);
          if (clean.startsWith('file://')) clean = clean.substring(7);
          if (!targetModFiles.contains(clean)) {
            targetModFiles.add(clean);
          }
          if (!targetModFileList.any((f) => f.path == clean)) {
            targetModFileList.add(SessionModifiedFile(path: clean, additions: 1, deletions: 0));
          }
        }
        if (subCount > 0) {
          _fetchSubagentsForSession(targetSession);
        }
        if (widget.activeSessionId == targetSession) {
          setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchSubagentsForSession(String targetSession) async {
    final api = widget.api;
    if (api == null || targetSession.isEmpty) return;
    try {
      final raw = await api.getSubagents(targetSession);
      if (!mounted) return;
      final parsed = raw.map((m) => SubagentItem.fromJson(m)).toList();
      setState(() {
        _sessionSubagents[targetSession] = parsed;
        _sessionSubagentCounts[targetSession] = parsed.length;
      });
    } catch (_) {}
  }

  /// B2 — tap-to-deep-link : quand l'utilisateur tape la notification locale
  /// « Approbation requise » (app en arrière-plan ou tuée), on re-fetch le
  /// contexte via get_pending_approval et on pousse la carte. Le daemon garde
  /// l'approbation même si le stream_delta d'origine a été perdu.
  ///
  /// Phase 3 — action inline : la notification porte des boutons
  /// « Autoriser / Refuser » (Android). Le même stream délivre alors
  /// `action: allow|deny` : on soumet la décision directement après le
  /// re-fetch du contexte, sans afficher la carte.
  void _watchNotificationTaps() {
    _tapSub?.cancel();
    _tapSub = ApprovalNotifier.instance.taps.listen((tap) {
      if (!mounted) return;
      final cascadeId = tap['cascadeId'] ?? '';
      if (tap['kind'] != 'approval' || cascadeId.isEmpty) return;
      if (cascadeId != widget.activeSessionId) {
        // La session concernée n'est pas celle affichée : on ne peut pas
        // re-router ici (l'écran chat est monté par main.dart). Le daemon a
        // déjà pushé approval_pending — il sera consommé quand l'utilisateur
        // ouvrira la session. On se contente d'afficher la carte si la
        // session affichée EST la bonne.
        return;
      }
      final action = tap['action'] as String?;
      if (action != null) {
        _submitApprovalFromNotification(action);
      } else {
        _pendingApprovalFromTap();
      }
    });
  }

  /// Phase 3 — action inline « Autoriser/Refuser » d'une notification :
  /// re-fetch le contexte en attente puis soumet la décision, comme si
  /// l'utilisateur avait tapé le bouton de la carte.
  Future<void> _submitApprovalFromNotification(String action) async {
    final api = widget.api;
    if (api == null) return;
    try {
      final info = await api.getPendingApproval(widget.activeSessionId);
      if (!mounted || info == null || info.isEmpty) return;
      await api.submitApproval(
        cascadeId: widget.activeSessionId,
        callId: info['callId'] as String? ?? '',
        allow: action == 'allow',
        trajectoryId: info['trajectoryId'] as String? ?? '',
        stepIndex: (info['stepIndex'] as num?)?.toInt() ?? -1,
        approvalType: info['approvalType'] as String? ?? 'approval',
        command: info['command'] as String? ?? '',
      );
      final callId = info['callId'] as String? ?? '';
      if (callId.isNotEmpty && mounted) {
        // Retire immédiatement la carte si elle est affichée (l'utilisateur
        // a répondu depuis la notification, pas depuis l'app).
        _processedCallIds.add(callId);
        _removeApproval(callId);
      }
      // La réponse du daemon (approval_resolved / stream_delta) nettoiera la
      // carte si elle est affichée ; on annule la notification localement
      // pour un retour immédiat.
      ApprovalNotifier.instance.cancelApprovalByCascadeId(widget.activeSessionId);
      ApprovalNotifier.instance.cancelTask(widget.activeSessionId);
    } catch (_) {
      // Daemon injoignable ou approbation déjà résolue : silencieux — la
      // notification d'origine a pu être remplacée/annulée par le daemon.
    }
  }

  Future<void> _pendingApprovalFromTap() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final info = await api.getPendingApproval(widget.activeSessionId);
      if (!mounted || info == null || info.isEmpty) return;
      _addApproval(ToolApprovalRequest(
        callId: info['callId'] as String? ?? '',
        toolName: info['approvalType'] as String? ?? 'run_command',
        command: info['command'] as String? ?? '',
        description: 'Tool execution requires your confirmation',
        cascadeId: widget.activeSessionId,
        trajectoryId: info['trajectoryId'] as String? ?? '',
        stepIndex: (info['stepIndex'] as num?)?.toInt() ?? -1,
        approvalType: info['approvalType'] as String? ?? 'approval',
      ), fromTap: true);
    } catch (_) {
      // Daemon injoignable ou pas d'approbation en attente : silencieux.
    }
  }

  void _setupConnectionListeners() {
    final client = widget.wsClient;
    if (client == null) return;

    setState(() {
      _status = client.status;
    });

    client.statusNotifier.addListener(_onConnectionStatusChanged);
    client.retryInfo.addListener(_onRetryInfoChanged);
  }

  void _onConnectionStatusChanged() {
    if (!mounted) return;
    final client = widget.wsClient;
    if (client == null) return;
    final newStatus = client.status;
    final manual = client.isManualDisconnect;

    if (_status == ConnectionStatus.connected &&
        newStatus != ConnectionStatus.connected &&
        !manual &&
        !_notifiedLost) {
      _notifiedLost = true;
      // Phase UX : notification locale quand la connexion au daemon est
      // perdue alors que l'utilisateur n'est PAS sur l'app (écran verrouillé
      // ou app en arrière-plan). Au premier plan, le banner suffit.
      if (!_appInForeground) {
        ApprovalNotifier.instance.notifyConnectionLost();
      }
    } else if (newStatus == ConnectionStatus.connected) {
      if (_notifiedLost) {
        // On était en panne : prévenir du retour à la normale (même id de
        // notification → remplace la « perdue »).
        ApprovalNotifier.instance.notifyConnectionRestored();
      }
      _notifiedLost = false;
      if (widget.activeSessionId.isNotEmpty) {
        _loadHistoryIfEmpty(widget.activeSessionId);
      }
      _refreshQuotaSummary();
    }

    setState(() {
      _status = newStatus;
      _isManualDisconnect = manual;
    });
  }

  void _onRetryInfoChanged() {
    if (!mounted) return;
    final client = widget.wsClient;
    if (client == null) return;
    setState(() {
      _attempt = client.retryInfo.value.attempt;
      _nextRetryIn = client.retryInfo.value.nextRetryIn;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Track du premier plan pour ne notifier la perte de connexion que si
    // l'utilisateur ne regarde pas l'app (écran verrouillé / background).
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appInForeground = false;
        break;
    }
    // Garder le stream actif en arrière-plan pour ingérer les tokens et recevoir
    // les approbations/notifications même écran éteint. Le throttle 100ms
    // évite toute surconsommation CPU en fond.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scrollToBottomSettled();
    }
  }

  @override
  void didUpdateWidget(covariant ChatStreamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSessionId != widget.activeSessionId) {
      _sessionApprovalIndices.putIfAbsent(
        widget.activeSessionId,
        () => _currentSessionApprovals.isEmpty ? -1 : 0,
      );
      _visibleCounts[widget.activeSessionId] = _pageSize;
      if (!_activeStreamingSessions.contains(widget.activeSessionId)) {
        _stillWorkingTimer?.cancel();
        _stillWorkingTimer = null;
        if (_showStillWorking) {
          _showStillWorking = false;
        }
      }
      _loadHistoryIfEmpty();
      _loadPersistedDraft();
      _scrollToBottomSettled();
    }
    if (oldWidget.api != widget.api) {
      // Reconnexion : réinitialiser l'état
      _activeStreamingSessions.clear();
      _stillWorkingTimer?.cancel();
      if (mounted && _showStillWorking) setState(() => _showStillWorking = false);
      _watchBroadcastStreams();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _throttleTimer?.cancel();
    _streamSub?.cancel();
    _tapSub?.cancel();
    _stillWorkingTimer?.cancel();
    _syncTimer?.cancel();
    _quotaTimer?.cancel();
    for (final t in _settleTimers) {
      t.cancel();
    }
    _settleTimers.clear();
    _scrollController.dispose();
    final client = widget.wsClient;
    client?.statusNotifier.removeListener(_onConnectionStatusChanged);
    client?.retryInfo.removeListener(_onRetryInfoChanged);
    super.dispose();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _onStreamStarted(String sessionId) {
    final wasEmpty = _activeStreamingSessions.isEmpty;
    _activeStreamingSessions.add(sessionId);
    widget.onStreamingSessionChanged?.call(sessionId, true);
    if (wasEmpty) {
      widget.onStreamingStateChanged?.call(true);
    }
    if (sessionId == widget.activeSessionId) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = Timer(_stillWorkingDelay, () {
        if (mounted && _activeStreamingSessions.contains(widget.activeSessionId)) {
          setState(() => _showStillWorking = true);
        }
      });
    }
  }

  void _onStreamEnded(String sessionId) {
    _activeStreamingSessions.remove(sessionId);
    widget.onStreamingSessionChanged?.call(sessionId, false);
    if (_activeStreamingSessions.isEmpty) {
      widget.onStreamingStateChanged?.call(false);
    }
    if (!_activeStreamingSessions.contains(widget.activeSessionId)) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = null;
      if (_showStillWorking && mounted) {
        setState(() => _showStillWorking = false);
      }
    }
    final queue = _sessionMessageQueues[sessionId] ?? [];
    final lastEnd = _sessionLastStreamEnds[sessionId];
    final outcome = lastEnd?['data']?['outcome'] as String? ?? 'done';
    if (outcome == 'done' && queue.isNotEmpty) {
      final next = queue.removeAt(0);
      final text = next['text'] as String;
      final modelUID = next['modelUID'] as String?;
      final modelEnum = next['modelEnum'] as int?;
      final buf = _sessionMessages.putIfAbsent(sessionId, () => []);
      setState(() {
        buf.add(ChatMessage(
          id: 'm${++_messageCounter}',
          sender: 'user',
          text: text,
          timestamp: _timestamp(),
        ));
      });
      _sendPromptToDaemon(text, targetSessionOverride: sessionId, modelUID: modelUID, modelEnum: modelEnum);
    }
  }

  void _handleStreamEnded(Map<String, dynamic> msg, [String? targetSessionId]) {
    final data = msg['data'];
    if (data is! Map<String, dynamic>) return;
    if (msg['data']?['hostActive'] == true) return;
    final outcome = data['outcome'] as String? ?? 'done';
    final cascadeId = targetSessionId ?? data['cascadeId'] as String? ?? widget.activeSessionId;
    final message = data['message'] as String? ?? '';

    ApprovalNotifier.instance.notifyTaskEnded(
      cascadeId: cascadeId,
      outcome: outcome,
      message: message,
    );
    if (outcome == 'done' || outcome == 'cancelled') {
      HapticFeedback.lightImpact();
    }
  }


  void _addApproval(ToolApprovalRequest approval,
      {bool hostActive = false, bool fromTap = false}) {
    // Bug #7 : guard broadcast path — un même callId ne doit jamais re-afficher
    // sa carte après reconnexion si l'utilisateur l'a déjà traitée.
    if (_processedCallIds.contains(approval.callId)) return;
    final cascadeId = approval.cascadeId.isNotEmpty ? approval.cascadeId : widget.activeSessionId;
    final list = _sessionApprovals.putIfAbsent(cascadeId, () => []);
    if (list.any((a) => a.callId == approval.callId)) return;
    _expiredCallIds.remove(approval.callId);
    if ((_sessionApprovalIndices[cascadeId] == null || _sessionApprovalIndices[cascadeId]! < 0) && cascadeId == widget.activeSessionId) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      final wasEmpty = list.isEmpty;
      list.add(approval);
      // UX P0-1 : une 2ᵉ approbation ne « vole » pas la carte affichée —
      // l'index reste sur la demande en cours (la nouvelle se rejoint via ▶).
      if (wasEmpty) _sessionApprovalIndices[cascadeId] = 0;
      _pendingApprovalCallIds.add(approval.callId);
      final fp = approval.filePath;
      if (fp != null && fp.isNotEmpty) {
        final modFiles = _sessionModifiedFiles.putIfAbsent(cascadeId, () => {});
        final modFileList = _sessionModifiedFileList.putIfAbsent(cascadeId, () => []);
        modFiles.add(fp);
        if (!modFileList.any((f) => f.path == fp)) {
          modFileList.add(SessionModifiedFile(
            path: fp,
            additions: 1,
            deletions: 0,
          ));
        }
      }
    });
    if (!hostActive && !fromTap && ApprovalNotifier.instance.initialized) {
      ApprovalNotifier.instance.notifyApprovalRequired(
        callId: approval.callId,
        cascadeId: cascadeId,
        toolName: approval.toolName,
        command: approval.command,
      );
    }
  }

  void _removeApproval(String callId, [String? targetSessionId]) {
    setState(() {
      _sessionApprovals.forEach((cid, list) {
        final i = list.indexWhere((a) => a.callId == callId);
        if (i >= 0) {
          list.removeAt(i);
          // L'index reste sur la demande qui suit celle retirée (ou la dernière
          // restante) : la carte visible bascule proprement et le compteur
          // « x/total » reflète la pile restante.
          _sessionApprovalIndices[cid] = list.isEmpty
              ? -1
              : math.min(i, list.length - 1);
        }
      });
      _pendingApprovalCallIds.remove(callId);
    });
    ApprovalNotifier.instance.cancelApproval(callId);
  }

  void _addQuestion(AskQuestionChoiceRequest q) {
    final cascadeId = q.cascadeId.isNotEmpty ? q.cascadeId : widget.activeSessionId;
    final list = _sessionQuestions.putIfAbsent(cascadeId, () => []);
    if (list.any((item) => item.requestId == q.requestId)) return;
    if (cascadeId == widget.activeSessionId) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      list.add(q);
    });
  }

  void _removeQuestion(String requestId) {
    setState(() {
      _sessionQuestions.forEach((cid, list) {
        list.removeWhere((item) => item.requestId == requestId);
      });
    });
  }

  void _handleQuestionSubmit(
    AskQuestionChoiceRequest q,
    List<String> selectedAnswers,
    String? customAnswer,
  ) async {
    // H3 (audit clean-code-guard) : on ne retire la carte qu'après
    // confirmation du daemon — un échec réseau la laisse visible pour un
    // nouvel essai au lieu de faire disparaître silencieusement la question.
    try {
      await widget.api?.submitQuestionResponse(
        cascadeId: q.cascadeId.isNotEmpty ? q.cascadeId : widget.activeSessionId,
        trajectoryId: q.trajectoryId.isNotEmpty ? q.trajectoryId : null,
        stepIndex: q.stepIndex >= 0 ? q.stepIndex : null,
        selectedAnswers: selectedAnswers,
        customAnswer: customAnswer,
      );
      _removeQuestion(q.requestId);
    } catch (_) {
      // Réseau indisponible ou daemon injoignable : on garde la question
      // (l'utilisateur pourra re-soumettre) — l'outbox ne prend pas en charge
      // les réponses à question.
    }
  }

  void _watchBroadcastStreams() {
    _streamSub?.cancel();
    _streamSub = widget.api?.events.listen((msg) {
      final type = msg['type'] as String?;
      final isBroadcast = msg['broadcast'] == true ||
          type == 'stream_delta' ||
          type == 'stream_start' ||
          type == 'stream_end' ||
          type == 'approval_pending' ||
          type == 'approval_required' ||
          type == 'question_pending' ||
          type == 'question_required' ||
          type == 'approval_resolved' ||
          type == 'approval_expired' ||
          type == 'session_status_update' ||
          type == 'quota_update' ||
          type == 'sessions_updated';
      if (!isBroadcast || !mounted) return;
      final requestId = msg['requestId'] as String? ?? '';
      String? sessionId = (msg['cascadeId'] ?? msg['data']?['cascadeId']) as String?;
      if (sessionId == null || sessionId.isEmpty) {
        final data = msg['data'];
        if (data is Map) {
          final events = data['events'];
          if (events is List && events.isNotEmpty && events.first is Map) {
            sessionId = events.first['cascadeId'] as String?;
          }
        }
      }

      if (type == 'quota_update') {
        final data = msg['data'] as Map<String, dynamic>?;
        if (data != null && data.isNotEmpty && mounted) {
          setState(() => _quotaSummary = data);
        }
        return;
      }

      if (type == 'sessions_updated') {
        if (mounted && widget.activeSessionId.isNotEmpty) {
          _loadHistoryIfEmpty(widget.activeSessionId);
        }
        return;
      }

      if (type == 'task_started') {
        final data = msg['data'] as Map<String, dynamic>? ?? {};
        final cmd = data['command'] as String? ?? data['id'] as String? ?? 'Task';
        final taskId = data['id'] as String? ?? cmd;
        if (!_runningBackgroundTasks.contains(cmd)) {
          setState(() {
            _runningBackgroundTasks.add(cmd);
            _taskStatuses[cmd] = 'running';
            _taskStatuses[taskId] = 'running';
            _taskOutputs.putIfAbsent(cmd, () => StringBuffer());
            _taskOutputs.putIfAbsent(taskId, () => StringBuffer());
          });
        }
        return;
      } else if (type == 'task_output') {
        final data = msg['data'] as Map<String, dynamic>? ?? {};
        final cmd = data['command'] as String? ?? data['id'] as String? ?? '';
        final taskId = data['id'] as String? ?? cmd;
        final delta = data['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          _taskOutputs[cmd]?.write(delta);
          _taskOutputs[taskId]?.write(delta);
          _taskOutputControllers[cmd]?.add(delta);
          _taskOutputControllers[taskId]?.add(delta);
        }
        return;
      } else if (type == 'task_ended') {
        final data = msg['data'] as Map<String, dynamic>? ?? {};
        final cmd = data['command'] as String? ?? data['id'] as String? ?? '';
        final taskId = data['id'] as String? ?? cmd;
        final status = data['status'] as String? ?? 'completed';
        setState(() {
          _runningBackgroundTasks.remove(cmd);
          _runningBackgroundTasks.remove(taskId);
          _taskStatuses[cmd] = status;
          _taskStatuses[taskId] = status;
        });
        return;
      }

      // Règle fondamentale : un événement sans cascadeId explicite ne doit JAMAIS
      // être attribué à la session affichée par défaut.
      if (sessionId == null || sessionId.isEmpty) {
        return;
      }

      final targetSessionId = sessionId;

      // P1 : notification « Tâche démarrée » — uniquement quand l'app est en
      // arrière-plan/verrouillée ET que personne n'est actif sur le PC hôte
      // (le daemon fournit hostActive sur stream_start, idle detection Go).
      // Couvre les prompts envoyés depuis le PC, les autres surfaces et les
      // envois locaux si l'utilisateur a verrouillé juste après.
      if (type == 'stream_start' &&
          !_appInForeground &&
          msg['data']?['hostActive'] != true) {
        ApprovalNotifier.instance.notifyTaskStarted(
          cascadeId: targetSessionId,
          prompt: 'Une tâche a démarré sur le PC hôte',
        );
      }

      // Bug tâches arrière-plan : si l'évènement concerne une autre session,
      // on le bufferise dans _sessionMessages[targetSessionId] au lieu de le jeter.
      final thKey = '${targetSessionId}_$requestId';
      final isActiveSession = targetSessionId == widget.activeSessionId;
      final buf = _sessionMessages.putIfAbsent(targetSessionId, () => []);

      if (type == 'stream_start') {
        _onStreamStarted(targetSessionId);
        if (isActiveSession && _showJumpToBottom) _hiddenNewCount++;

        if (buf.isNotEmpty && buf.last.sender == 'assistant') {
          _streamRequestToMessageId[thKey] = buf.last.id;
          buf.last = buf.last.copyWith(isStreaming: true);
        } else {
          final msgId = 'ext-$requestId';
          _streamRequestToMessageId[thKey] = msgId;
          if (!buf.any((m) => m.id == msgId)) {
            buf.add(ChatMessage(
              id: msgId,
              sender: 'assistant',
              text: '',
              timestamp: _timestamp(),
              isStreaming: true,
            ));
          }
        }
        if (isActiveSession && mounted) {
          setState(() {});
        }
      } else if (type == 'sync_catchup') {
        setState(() => _isSyncing = true);
        _syncTimer?.cancel();
        _syncTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _isSyncing = false);
        });
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final missedEvents = data['missedEvents'] as List<dynamic>? ?? const [];
        if (missedEvents.isNotEmpty) {
          for (final rawEv in missedEvents) {
            if (rawEv is Map) {
              final evMap = rawEv.cast<String, dynamic>();
              final reqId = evMap['requestId'] as String? ?? '';
              final textDelta = StreamDeltaParser.textOf(evMap);
              final thoughtDelta = StreamDeltaParser.thinkingOf(evMap);
              final key = '${targetSessionId}_$reqId';
              final idx = buf.indexWhere((m) =>
                  m.id == 'ext-$reqId' ||
                  (buf.isNotEmpty && m == buf.last && m.isStreaming));
              if (idx >= 0) {
                final current = buf[idx];
                _externalThoughts[key] = (_externalThoughts[key] ?? '') + thoughtDelta;
                buf[idx] = current.copyWith(
                  text: current.text + textDelta,
                  thought: _externalThoughts[key]!.isNotEmpty
                      ? _externalThoughts[key]!.trim()
                      : current.thought,
                );
              }
            }
          }
          if (isActiveSession) {
            _scheduleThrottledUpdate();
          }
        }
        final pending = (data['pendingMessages'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (pending.isNotEmpty) {
          for (final p in pending) {
            final reqId = p['requestId'] as String? ?? '';
            if (reqId.isEmpty) continue;
            final id = 'pending-$reqId';
            if (buf.any((m) => m.id == id)) continue;
            buf.add(ChatMessage(
              id: id,
              sender: 'user',
              text: p['prompt']?.toString() ?? '',
              timestamp: _timestamp(),
              isQueued: true,
            ));
          }
          if (isActiveSession && mounted) {
            setState(() {});
          }
        }
      } else if (type == 'stream_delta') {
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);

        final targetId = _streamRequestToMessageId[thKey] ?? 'ext-$requestId';
        var idx = buf.indexWhere((m) => m.id == targetId);
        if (idx < 0) {
          final lastStreamingIdx = buf.lastIndexWhere((m) => m.isStreaming);
          if (lastStreamingIdx >= 0) {
            idx = lastStreamingIdx;
            _streamRequestToMessageId[thKey] = buf[idx].id;
          } else if (buf.isNotEmpty && buf.last.sender == 'assistant') {
            idx = buf.length - 1;
            _streamRequestToMessageId[thKey] = buf.last.id;
          } else if (textDelta.isNotEmpty || thoughtDelta.isNotEmpty) {
            _onStreamStarted(targetSessionId);
            final msgId = 'ext-$requestId';
            _streamRequestToMessageId[thKey] = msgId;
            buf.add(ChatMessage(
              id: msgId,
              sender: 'assistant',
              text: '',
              timestamp: _timestamp(),
              isStreaming: true,
            ));
            idx = buf.length - 1;
          }
        }
        if (idx >= 0) {
          final current = buf[idx];
          _externalThoughts[thKey] =
              (_externalThoughts[thKey] ?? '') + thoughtDelta;
          buf[idx] = current.copyWith(
            text: current.text + textDelta,
            thought: _externalThoughts[thKey]!.isNotEmpty
                ? _externalThoughts[thKey]!.trim()
                : current.thought,
            isStreaming: true,
          );
        }
        if (approval != null) {
          final hostActive = msg['data']?['hostActive'] == true;
          _addApproval(
            ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId.isNotEmpty ? approval.cascadeId : targetSessionId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            ),
            hostActive: hostActive,
          );
        }

        final question = StreamDeltaParser.questionOf(msg);
        if (question != null) {
          _addQuestion(question);
        }

        if (isActiveSession && mounted) {
          _scheduleThrottledUpdate();
        }
      } else if (type == 'stream_end') {
        _onStreamEnded(targetSessionId);
        _handleStreamEnded(msg, targetSessionId);
        final targetId = _streamRequestToMessageId[thKey] ?? 'ext-$requestId';
        final idx = buf.indexWhere((m) => m.id == targetId);

        // Stamp the completed assistant message with the session's file-change summary.
        final changedFiles = (_sessionModifiedFiles[targetSessionId] ?? {}).toList();
        final modFileList = _sessionModifiedFileList[targetSessionId] ?? [];
        final totalAdded = modFileList.fold(0, (s, f) => s + f.additions);
        final totalRemoved = modFileList.fold(0, (s, f) => s + f.deletions);

        if (idx >= 0) {
          buf[idx] = buf[idx].copyWith(
            isStreaming: false,
            filesChanged: changedFiles.isNotEmpty ? changedFiles : null,
            additions: changedFiles.isNotEmpty ? totalAdded : null,
            deletions: changedFiles.isNotEmpty ? totalRemoved : null,
          );
        } else {
          final lastStreamingIdx = buf.lastIndexWhere((m) => m.isStreaming);
          if (lastStreamingIdx >= 0) {
            buf[lastStreamingIdx] = buf[lastStreamingIdx].copyWith(
              isStreaming: false,
              filesChanged: changedFiles.isNotEmpty ? changedFiles : null,
              additions: changedFiles.isNotEmpty ? totalAdded : null,
              deletions: changedFiles.isNotEmpty ? totalRemoved : null,
            );
          }
        }
        _externalThoughts.remove(thKey);
        _streamRequestToMessageId.remove(thKey);

        if (isActiveSession && mounted) {
          setState(() {});
          _scrollToBottomSettled();
        }
      } else if (type == 'session_status_update') {
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final status = (data['status'] ?? '').toString().toUpperCase();
        final cascadeId = (msg['cascadeId'] ?? data['cascadeId'] ?? '').toString();
        if (cascadeId.isNotEmpty) {
          if (status.contains('RUNNING') || status.contains('BUSY')) {
            _onStreamStarted(cascadeId);
          } else if (status.contains('IDLE') || status.contains('READY') || status.contains('DONE')) {
            _onStreamEnded(cascadeId);
          }
          if (mounted && cascadeId == widget.activeSessionId) {
            setState(() {});
          }
        }
      } else if (type == 'approval_pending' || type == 'approval_required') {
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final approval = StreamDeltaParser.parseApprovalMap(data, cascadeId: (msg['cascadeId'] ?? data['cascadeId']) as String? ?? targetSessionId);
        if (approval != null) {
          final hostActive = data['hostActive'] == true;
          _addApproval(
            ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId.isNotEmpty ? approval.cascadeId : targetSessionId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            ),
            hostActive: hostActive,
          );
        }
      } else if (type == 'question_pending' || type == 'question_required') {
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final q = StreamDeltaParser.parseQuestionMap(data, cascadeId: (msg['cascadeId'] ?? data['cascadeId']) as String? ?? targetSessionId);
        if (q != null) {
          _addQuestion(q);
        }
      } else if (type == 'approval_expired') {
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final callId = data['callId'] as String? ??
            data['approvalId'] as String? ??
            '';
        final cascadeId = (msg['cascadeId'] ?? data['cascadeId']) as String? ?? '';
        if (callId.isNotEmpty && _pendingApprovalCallIds.contains(callId)) {
          setState(() => _expiredCallIds.add(callId));
          _pendingApprovalCallIds.remove(callId);
          ApprovalNotifier.instance.cancelApproval(callId);
        } else if (cascadeId.isNotEmpty) {
          ApprovalNotifier.instance
              .cancelApprovalByCascadeId(cascadeId);
        }
      } else if (type == 'approval_resolved') {
        final data = msg['data'] as Map<String, dynamic>? ?? const {};
        final callId = data['callId'] as String? ?? '';
        final cascadeId = (msg['cascadeId'] ?? data['cascadeId']) as String? ?? '';
        if (callId.isNotEmpty && _pendingApprovalCallIds.contains(callId)) {
          _removeApproval(callId, cascadeId);
        } else if (cascadeId.isNotEmpty) {
          setState(() {
            final list = _sessionApprovals[cascadeId];
            if (list != null) {
              list.clear();
              _sessionApprovalIndices[cascadeId] = -1;
            }
          });
          ApprovalNotifier.instance.cancelApprovalByCascadeId(cascadeId);
        }
      }
    });
  }

  void _handleSendMessage(
    String text, {
    bool queued = false,
    String? modelUID,
    int? modelEnum,
  }) {
    if (text.trim().startsWith('/btw ') || text.trim().startsWith('/btw')) {
      final sideQ = text.trim().replaceFirst(RegExp(r'^/btw\s*'), '');
      setState(() {
        _sideQuestion = sideQ.isNotEmpty ? sideQ : 'Question parallèle';
        _isSideQuestionLoading = true;
        _sideQuestionAnswer = null;
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _isSideQuestionLoading = false;
            _sideQuestionAnswer = 'Réponse à la question : "$sideQ" prise en compte dans le contexte.';
          });
        }
      });
      return;
    }

    final targetSession = widget.activeSessionId;
    final isStreaming = _activeStreamingSessions.contains(targetSession);

    if (queued || isStreaming) {
      final queue = _sessionMessageQueues.putIfAbsent(targetSession, () => []);
      setState(() {
        queue.add({
          'text': text,
          'activeSessionId': targetSession,
          'modelUID': modelUID,
          'modelEnum': modelEnum,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      });
      return;
    }

    final buf = _sessionMessages.putIfAbsent(targetSession, () => []);
    setState(() {
      buf.add(ChatMessage(
        id: 'm${++_messageCounter}',
        sender: 'user',
        text: text,
        timestamp: _timestamp(),
      ));
    });

    final api = widget.api;
    if (api == null) return;

    _sendPromptToDaemon(text, targetSessionOverride: targetSession, modelUID: modelUID, modelEnum: modelEnum);
  }

  void _handleQueueSendNow(int index) {
    final queue = _sessionMessageQueues[widget.activeSessionId];
    if (queue == null || index < 0 || index >= queue.length) return;
    final item = queue.removeAt(index);
    final text = item['text'] as String? ?? '';
    final modelUID = item['modelUID'] as String?;
    final modelEnum = item['modelEnum'] as int?;
    final targetSession = widget.activeSessionId;

    final buf = _sessionMessages.putIfAbsent(targetSession, () => []);
    setState(() {
      buf.add(ChatMessage(
        id: 'm${++_messageCounter}',
        sender: 'user',
        text: text,
        timestamp: _timestamp(),
      ));
    });
    _sendPromptToDaemon(text, targetSessionOverride: targetSession, modelUID: modelUID, modelEnum: modelEnum);
  }

  void _handleQueueEdit(int index) {
    final queue = _sessionMessageQueues[widget.activeSessionId];
    if (queue == null || index < 0 || index >= queue.length) return;
    final item = queue.removeAt(index);
    final text = item['text'] as String? ?? '';
    setState(() {
      setDraft(text);
    });
  }

  void _handleQueueDelete(int index) {
    final queue = _sessionMessageQueues[widget.activeSessionId];
    if (queue == null || index < 0 || index >= queue.length) return;
    setState(() {
      queue.removeAt(index);
    });
  }

  void _sendPromptToDaemon(String text, {String? targetSessionOverride, String? modelUID, int? modelEnum}) {
    final api = widget.api;
    if (api == null) return;

    final targetSession = targetSessionOverride ?? widget.activeSessionId;
    final assistantId = 'a${++_messageCounter}';
    _sessionLastStreamEnds.remove(targetSession);
    final modelLabel = modelUID != null && modelUID.isNotEmpty
        ? modelUID
        : 'Gemini 3.7 Flash';

    final buf = _sessionMessages.putIfAbsent(targetSession, () => []);
    setState(() {
      buf.add(ChatMessage(
        id: assistantId,
        sender: 'assistant',
        text: '',
        timestamp: _timestamp(),
        isStreaming: true,
        modelLabel: modelLabel,
      ));
      _activeStreamingSessions.add(targetSession);
    });
    if (targetSession == widget.activeSessionId) {
      _scrollToBottom();
    }

    var thoughtBuffer = StringBuffer();
    _onStreamStarted(targetSession);
    api.sendPrompt(
      targetSession,
      text,
      modelUID: modelUID,
      modelEnum: modelEnum,
    ).listen(
      (msg) {
        if (msg['type'] == 'stream_end') {
          _sessionLastStreamEnds[targetSession] = msg;
        }
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        if (!mounted) return;

        if (textDelta.isNotEmpty || thoughtDelta.isNotEmpty) {
          final idx = buf.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            final current = buf[idx];
            thoughtBuffer.write(thoughtDelta);
            buf[idx] = current.copyWith(
              text: current.text + textDelta,
              thought: thoughtBuffer.isNotEmpty
                  ? thoughtBuffer.toString().trim()
                  : current.thought,
            );
          }
        }
        if (approval != null) {
          final hostActive = msg['data']?['hostActive'] == true;
          _addApproval(
            ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId.isNotEmpty ? approval.cascadeId : targetSession,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            ),
            hostActive: hostActive,
          );
        }

        if (mounted && widget.activeSessionId == targetSession) {
          _scheduleThrottledUpdate();
        }
      },
      onDone: () {
        if (!mounted) return;
        final localEnd = _sessionLastStreamEnds[targetSession];
        _onStreamEnded(targetSession);
        _handleStreamEnded(localEnd ?? const {}, targetSession);
        setState(() {
          final idx = buf.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            final localData = localEnd?['data'];
            String? error = localEnd?['error'] as String? ??
                (localData is Map
                    ? (localData['outcome'] == 'error'
                        ? localData['message'] as String? ?? 'Erreur'
                        : null)
                    : null);
            if (error != null && (error.contains('MODEL_CAPACITY_EXHAUSTED') || error.contains('No capacity available') || error.contains('503'))) {
              error = '⚠️ Capacité du modèle saturée sur les serveurs (HTTP 503 / MODEL_CAPACITY_EXHAUSTED).\nVeuillez basculer vers Gemini 3.7 Flash, Claude ou un modèle custom via le sélecteur ci-dessous.';
            }
            buf[idx] = buf[idx].copyWith(
              isStreaming: false,
              isError: error != null,
              text: error != null
                  ? (buf[idx].text.isEmpty ? error : buf[idx].text)
                  : buf[idx].text,
            );
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        _onStreamEnded(targetSession);
        setState(() {
          final idx = buf.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            buf[idx] = buf[idx].copyWith(
              isStreaming: false,
              isError: true,
              text: 'Erreur: $err',
            );
          }
        });
      },
    );
  }

  void _handleToolDecision(ToolDecision decision,
      {ApprovalScope scope = ApprovalScope.once, String denyReason = ''}) {
    final approval = _currentApproval;
    if (approval == null) return;

    // Scénarios Extrêmes (1 & 7) : On marque cet appel comme traité pour ne plus jamais
    // ré-afficher cette carte si le serveur rejoue le message après une perte de connexion.
    _processedCallIds.add(approval.callId);

    if (_expiredCallIds.contains(approval.callId)) {
      // La carte affichait déjà l'état expiré : on nettoie juste l'état.
      _removeApproval(approval.callId);
      return;
    }
    _removeApproval(approval.callId);
    widget.api?.submitApproval(
      cascadeId: approval.cascadeId.isEmpty
          ? widget.activeSessionId
          : approval.cascadeId,
      callId: approval.callId,
      allow: decision == ToolDecision.allow,
      trajectoryId: approval.trajectoryId,
      stepIndex: approval.stepIndex,
      approvalType: approval.approvalType,
      command: approval.command,
      scope: scope,
      denyReason: denyReason,
    ).catchError((_) => <String, dynamic>{});
  }

  void _scheduleThrottledUpdate() {
    if (_throttleTimer?.isActive ?? false) {
      _needsStateUpdate = true;
      return;
    }

    setState(() {}); // Immediate update

    _throttleTimer = Timer(_throttleDuration, () {
      if (_needsStateUpdate && mounted) {
        setState(() {});
        _needsStateUpdate = false;
      }
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // N'auto-scroll pendant le streaming que si l'utilisateur est déjà proche du bas (< 120px)
    if ((maxScroll - currentScroll) < 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } else {
      if (!_showJumpToBottom) {
        setState(() {
          _showJumpToBottom = true;
          _hiddenNewCount++;
        });
      }
    }
  }

  Widget _buildReminderBanners() {
    final children = <Widget>[];
    if (_showStillWorking) {
      children.add(const _ReminderBanner(
        icon: Icons.hourglass_top_outlined,
        message: 'La tâche tourne toujours — suivez la depuis le téléphone',
      ));
    }
    final pendingApprovals = _pendingApprovalCallIds.length;
    if (pendingApprovals >= 2) {
      children.add(const _ReminderBanner(
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

  /// Carte d'approbation épinglée au-dessus de la barre de saisie (audit UX
  /// P0-2) : toujours visible, même en fin de longue conversation. Navigable
  /// ◀ ▶ quand plusieurs demandes sont empilées.
  Widget _buildApprovalArea() {
    final questions = _currentSessionQuestions;
    if (questions.isNotEmpty) {
      final q = questions.first;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AskQuestionChoiceCard(
          request: q,
          onSubmit: (selected, custom) =>
              _handleQuestionSubmit(q, selected, custom),
        ),
      );
    }

    final approval = _currentApproval;
    if (approval == null) return const SizedBox.shrink();
    final total = _currentSessionApprovals.length;
    final expired = _expiredCallIds.contains(approval.callId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (total > 1)
                IconButton(
                  key: const Key('approval-prev'),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  tooltip: 'Approbation précédente',
                  onPressed: () => setState(() {
                    _approvalIndex =
                        (_approvalIndex - 1 + total) % total;
                  }),
                ),
              Text(
                'Approbation ${_approvalIndex + 1}/$total',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (total > 1)
                IconButton(
                  key: const Key('approval-next'),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  tooltip: 'Approbation suivante',
                  onPressed: () => setState(() {
                    _approvalIndex = (_approvalIndex + 1) % total;
                  }),
                ),
              const Spacer(),
              IconButton(
                key: const Key('approval-dismiss'),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Fermer cette approbation',
                onPressed: () => _removeApproval(approval.callId),
              ),
            ],
          ),
          TweenAnimationBuilder<double>(
            key: ValueKey('approval-${approval.callId}'),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutQuart,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - value)),
                child: child,
              ),
            ),
            child: ToolApprovalCard(
              request: approval,
              onDecision: _handleToolDecision,
              isExpired: expired,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusBadge(ColorScheme scheme) {
    int pendingCount = 0;
    try {
      pendingCount = widget.api?.outbox?.pendingCount ?? 0;
    } catch (_) {}
    if (!_isSyncing && pendingCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isSyncing
            ? scheme.primary.withValues(alpha: 0.12)
            : const Color(0xFFD29922).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: _isSyncing
              ? scheme.primary.withValues(alpha: 0.3)
              : const Color(0xFFD29922).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSyncing) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Rattrapage des messages en cours…',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.primary,
              ),
            ),
          ] else ...[
            const Icon(Icons.cloud_upload_outlined, size: 12, color: Color(0xFFD29922)),
            const SizedBox(width: 6),
            Text(
              '$pendingCount message${pendingCount > 1 ? 's' : ''} en attente de connexion',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD29922),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Badge de quotas temps réel (P8).
  Widget _buildQuotaBadge(ColorScheme scheme) {
    if (_quotaSummary == null) return const SizedBox.shrink();
    final gRaw = _quotaSummary?['weeklyPercent'] ?? _quotaSummary?['geminiQuotaPercent'];
    final cRaw = _quotaSummary?['weeklyPercentClaude'] ?? _quotaSummary?['claudeQuotaPercent'];
    final gVal = gRaw is num ? gRaw.round() : null;
    final cVal = cRaw is num ? cRaw.round() : null;
    if (gVal == null && cVal == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_outlined, size: 11, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          if (gVal != null)
            Text(
              'Gemini: $gVal%',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: gVal > 85 ? scheme.error : scheme.onSurfaceVariant),
            ),
          if (gVal != null && cVal != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('•', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          if (cVal != null)
            Text(
              'Claude: $cVal%',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cVal > 85 ? scheme.error : scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  void _showProjectSelector(BuildContext context) {
    final projs = widget.projects ?? [];
    if (projs.isEmpty) return;
    ProjectSelectorBottomSheet.show(
      context,
      projects: projs,
      activeProjectPath: widget.activeProjectName,
      onSelectProject: (p) => widget.onSelectProject?.call(p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    Widget connectivityBanner = AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuart,
      child: ConnectionBanner(
        status: _status,
        attempt: _attempt,
        nextRetryIn: _nextRetryIn,
        isManualDisconnect: _isManualDisconnect,
        onRetry: widget.wsClient?.retryNow,
      ),
    );

    // Source unique de vérité pour l'état connecté de la barre de saisie :
    // le banner et l'input partagent le même statut (audit UX P2-12).
    final isConnected = widget.wsClient == null
        ? widget.isConnected
        : _status == ConnectionStatus.connected;

    final breadcrumb = SessionBreadcrumb(
      projectName: widget.activeProjectName,
      sessionTitle: widget.activeSessionTitle ?? '',
      projects: widget.projects,
      onSelectProject: (widget.projects != null && widget.projects!.length > 1)
          ? () => _showProjectSelector(context)
          : null,
      onOpenIde: () {
        AppToast.show(context, message: 'Session synchronisée avec Antigravity Desktop IDE');
      },
    );

    if (_messages.isEmpty && _currentApproval == null && _currentSessionQuestions.isEmpty) {
      return Column(
        children: [
          connectivityBanner,
          breadcrumb,
          if (!hasKeyboard) ...[
            _buildSyncStatusBadge(scheme),
            _buildQuotaBadge(scheme),
          ],
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WelcomeEmptyState(
                        projectName: widget.activeProjectName,
                        onSuggestionTap: (text) => _handleSendMessage(text, queued: false),
                        onSelectProject: (widget.projects != null && widget.projects!.length > 1)
                            ? () => _showProjectSelector(context)
                            : null,
                      ),
                      const SizedBox(height: 32),
                      if ((_sessionMessageQueues[widget.activeSessionId]?.isNotEmpty ?? false))
                        QueuedMessagesCard(
                          queuedMessages: _sessionMessageQueues[widget.activeSessionId]!,
                          onSendNow: _handleQueueSendNow,
                          onEdit: _handleQueueEdit,
                          onDelete: _handleQueueDelete,
                        ),
                      ChatInputBar(
                        onSend: _handleSendMessage,
                        isConnected: isConnected,
                        hasActiveStream: _activeStreamCount > 0,
                        onStop: _handleStopGeneration,
                        api: widget.api,
                        cascadeId: widget.activeSessionId,
                        initialText: currentDraft,
                        onDraftChanged: setDraft,
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        connectivityBanner,
        SessionTopTabs(
          activeTab: _currentTab,
          onTabChanged: (tab) {
            setState(() {
              _activeArtifact = null;
              _currentTab = tab;
            });
            if (tab == SessionTabType.review) {
              _fetchVcsChanges();
            }
          },
          filesChangedCount: _modifiedFiles.length,
          hasPlan: _latestPlanText != null,
          hasTasks: false,
          runningTasksCount: _activeStreamCount,
          artifactTabs: _artifacts,
          activeArtifact: _activeArtifact,
          onOpenArtifact: (art) => setState(() {
            _activeArtifact = art;
          }),
          onNewTab: () {
            final projs = widget.projects ?? [];
            if (projs.length > 1) {
              _showProjectSelector(context);
            } else {
              widget.onNewConversation?.call();
            }
          },
        ),
        if (!hasKeyboard) ...[
          _buildSyncStatusBadge(scheme),
          _buildQuotaBadge(scheme),
        ],
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                // P6 : swipe horizontal gauche/droite pour changer d'onglet.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    if (_activeArtifact != null) return; // onglet artefact : pas de swipe
                    final tabs = _swipeableTabs;
                    if (tabs.length < 2) return;
                    final idx = tabs.indexOf(_currentTab);
                    if (idx < 0) return;
                    final velocity = details.primaryVelocity ?? 0;
                    final next = velocity < -200
                        ? idx + 1
                        : velocity > 200
                            ? idx - 1
                            : -1;
                    if (next < 0 || next >= tabs.length) return;
                    final nextTab = tabs[next];
                    setState(() {
                      _activeArtifact = null;
                      _currentTab = nextTab;
                    });
                    if (nextTab == SessionTabType.review) {
                      _fetchVcsChanges();
                    }
                  },
                  child: _buildActiveTabContent(scheme, isConnected),
                ),
              ),
              // P1 : bouton flottant « retour en bas » — uniquement sur
              // l'onglet chat, quand l'utilisateur s'est éloigné du bas.
              if (_showJumpToBottom &&
                  _activeArtifact == null &&
                  _currentTab == SessionTabType.chat)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: _JumpToBottomButton(
                    count: _hiddenNewCount,
                    onTap: _jumpToBottom,
                  ),
                ),
            ],
          ),
        ),
        _buildApprovalArea(),
        if (_sideQuestion != null)
          SideQuestionCard(
            question: _sideQuestion!,
            answer: _sideQuestionAnswer,
            isLoading: _isSideQuestionLoading,
            onClose: () => setState(() {
              _sideQuestion = null;
              _sideQuestionAnswer = null;
            }),
          ),
        if (_runningBackgroundTasks.isNotEmpty)
          BackgroundTasksBar(
            runningTasks: _runningBackgroundTasks,
            onTapTask: _openTaskOutputSheet,
            onStopTask: _handleStopBackgroundTask,
            onViewTasks: () {
              if (_runningBackgroundTasks.isNotEmpty) {
                _openTaskOutputSheet(_runningBackgroundTasks.first);
              }
            },
          ),
        if ((_sessionMessageQueues[widget.activeSessionId]?.isNotEmpty ?? false))
          QueuedMessagesCard(
            queuedMessages: _sessionMessageQueues[widget.activeSessionId]!,
            onSendNow: _handleQueueSendNow,
            onEdit: _handleQueueEdit,
            onDelete: _handleQueueDelete,
          ),
        if (_hasCurrentActiveStream)
          _buildLiveAgentActivityDock(scheme),
        ChatInputBar(
          onSend: _handleSendMessage,
          isConnected: isConnected,
          hasActiveStream: _hasCurrentActiveStream,
          onStop: _handleStopGeneration,
          api: widget.api,
          cascadeId: widget.activeSessionId,
          initialText: currentDraft,
          onDraftChanged: setDraft,
        ),
      ],
    );
  }

  Widget _buildLiveAgentActivityDock(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF232D42) : scheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          _scrollToBottomSettled();
          HapticFeedback.selectionClick();
        },
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentBlueBright,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x6638BDF8),
                    blurRadius: 5,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Agent en cours d\'exécution…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.accentBlueBright : scheme.primary,
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    'Toucher pour suivre les actions en direct',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? const Color(0xFF8B8D98) : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                _handleStopGeneration();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF381519) : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFF7F1D1D) : scheme.error,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.stop_rounded,
                      size: 12,
                      color: isDark ? const Color(0xFFFCA5A5) : scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Arrêter',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFFCA5A5) : scheme.onErrorContainer,
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

  void _handleStopGeneration() {
    final targetSession = widget.activeSessionId;
    widget.api?.stopGeneration(cascadeId: targetSession);
    setState(() {
      _activeStreamingSessions.remove(targetSession);
      _showStillWorking = false;
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = null;
      final buf = _sessionMessages[targetSession];
      if (buf != null) {
        final idx = buf.lastIndexWhere((m) => m.isStreaming);
        if (idx >= 0) {
          buf[idx] = buf[idx].copyWith(isStreaming: false);
        }
      }
    });
    widget.onStreamingSessionChanged?.call(targetSession, false);
    if (_activeStreamingSessions.isEmpty) {
      widget.onStreamingStateChanged?.call(false);
    }
  }

  Widget _buildActiveTabContent(ColorScheme scheme, bool isConnected) {
    if (_activeArtifact != null) {
      return _buildArtifactTabContent(_activeArtifact!);
    }

    switch (_currentTab) {
      case SessionTabType.overview:
        return OverviewPanelView(
          sessionTitle: widget.activeProjectName.isNotEmpty ? widget.activeProjectName : 'Session',
          workspacePath: widget.activeProjectName,
          modifiedFiles: _modifiedFiles.toList(),
          artifacts: _artifacts,
          subagentsCount: _subagentsCount,
          backgroundTasks: _runningBackgroundTasks,
          onOpenReview: () => setState(() {
            _activeArtifact = null;
            _currentTab = SessionTabType.review;
          }),
          onOpenPlan: () => setState(() {
            _activeArtifact = null;
            _currentTab = SessionTabType.plan;
          }),
          onOpenSubagents: () {
            SubagentsTreeSheet.show(
              context,
              api: widget.api,
              cascadeId: widget.activeSessionId,
            );
          },
        );
      case SessionTabType.review:
        return _buildReviewTabContent();
      case SessionTabType.plan:
        return _buildPlanTabContent();
      case SessionTabType.tasks:
        return _buildTasksTabContent();
      case SessionTabType.chat:
        final visibleList = _visibleMessages;
        final hiddenCount = _hiddenOlderCount;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final scheme = Theme.of(context).colorScheme;

        final headerWidgets = <Widget>[
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _loadMoreOlderMessages,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            size: 14,
                            color: AppColors.accentBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Charger les $hiddenCount messages précédents',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.accentBlue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          _buildReminderBanners(),
          if (_subagents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SubagentTreeCard(
                subagents: _subagents,
                onOpenFullTree: () {
                  SubagentsTreeSheet.show(
                    context,
                    api: widget.api,
                    cascadeId: widget.activeSessionId,
                  );
                },
                onSelectSubagent: (sub) {
                  SubagentsTreeSheet.show(
                    context,
                    api: widget.api,
                    cascadeId: widget.activeSessionId,
                  );
                },
              ),
            ),
        ];

        final totalCount = headerWidgets.length + visibleList.length;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: false,
          child: RefreshIndicator(
            onRefresh: () async {
              if (widget.activeSessionId.isNotEmpty) {
                _loadHistoryIfEmpty(widget.activeSessionId);
              }
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: totalCount,
              itemBuilder: (ctx, index) {
              if (index < headerWidgets.length) {
                return headerWidgets[index];
              }

              final msgIndex = index - headerWidgets.length;
              final msg = visibleList[msgIndex];
              final isLatest = msgIndex == visibleList.length - 1;

              final bubbleWidget = _MessageBubble(
                message: msg,
                api: widget.api,
                workspacePath: widget.activeProjectName,
                onLocalFile: _openLocalFile,
                onOpenArtifact: _openArtifactByName,
                isThoughtExpanded: _expandedThoughts.contains(msg.id),
                onToggleThought: () => setState(() {
                  if (_expandedThoughts.contains(msg.id)) {
                    _expandedThoughts.remove(msg.id);
                  } else {
                    _expandedThoughts.add(msg.id);
                  }
                }),
                onProceedPlan: () => _handleSendMessage('Proceed', queued: false),
                onViewPlan: () => setState(() => _currentTab = SessionTabType.plan),
                onViewReview: () => setState(() => _currentTab = SessionTabType.review),
                onStop: _handleStopGeneration,
                onResend: (m) {
                  final reqId = m.id.startsWith('pending-')
                      ? m.id.substring('pending-'.length)
                      : '';
                  if (reqId.isEmpty) return;
                  widget.api?.resendPending({'requestId': reqId});
                  setState(() {
                    _messages.removeWhere((item) => item.id == m.id);
                  });
                  AppToast.show(
                    context,
                    message: 'Prompt retransmis au daemon',
                    icon: Icons.send_outlined,
                    type: ToastType.success,
                  );
                },
              );

              // N'anime l'entrée que pour le dernier message en cours et uniquement si Reduce Motion est inactif
              if (isLatest && ctx.shouldAnimate) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(msg.id),
                    duration: AppMotion.slow,
                    curve: AppMotion.easeOut,
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: bubbleWidget,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: bubbleWidget,
              );
            },
          ),
        ),
      );
    }
  }

  /// P5 : exécute une commande shell sur le workspace hôte via le daemon
  /// (mode legacy send_command — aucun besoin de PTY pour git apply).
  Future<void> _runWorkspaceCommand(String command) async {
    final api = widget.api;
    if (api == null) return;
    try {
      await api.sendCommand(command);
    } catch (_) {
      // Silencieux : le terminal / logs affichent déjà l'erreur côté daemon.
    }
  }

  /// P5 : confirmation avant action groupée (accepter / rejeter tout).
  Future<void> _confirmBulkAction({
    required String title,
    required String message,
    required String confirmLabel,
    required String command,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainer,
        title: Text(title, style: TextStyle(fontSize: 15, color: scheme.onSurface)),
        content: Text(
          message,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: confirmLabel == 'Tout rejeter'
                  ? AppColors.danger
                  : scheme.primary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _runWorkspaceCommand(command);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmLabel == 'Tout rejeter'
                  ? 'Modifications rejetées — commande envoyée au workspace.'
                  : 'Modifications acceptées — commande envoyée au workspace.',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _fetchVcsChanges() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final ws = widget.workspacePath?.isNotEmpty == true
          ? widget.workspacePath
          : (widget.activeProjectName.isNotEmpty ? widget.activeProjectName : null);

      // Priorité 1 : get_context.modifiedFiles (parsés du transcript) —
      // même source que le badge filesChangedCount. Toujours cohérent.
      final ctx = await api.getContext(
        cascadeId: widget.activeSessionId.isNotEmpty ? widget.activeSessionId : null,
        workspacePath: ws,
      );
      final ctxFiles = ctx['modifiedFiles'];
      final list = <SessionModifiedFile>[];
      if (ctxFiles is List && ctxFiles.isNotEmpty) {
        for (final item in ctxFiles) {
          if (item is! String || item.isEmpty) continue;
          var clean = item.replaceAll('\\', '/');
          if (clean.startsWith('file:///')) clean = clean.substring(8);
          if (clean.startsWith('file://')) clean = clean.substring(7);
          if (!_modifiedFiles.contains(clean)) _modifiedFiles.add(clean);
          if (!list.any((f) => f.path == clean)) {
            list.add(SessionModifiedFile(path: clean, additions: 1, deletions: 0));
          }
        }
      }

      // Fallback : git status (staged + working tree)
      if (list.isEmpty) {
        final res = await api.getVcsState(workspacePath: ws);
        for (final key in const ['workingDirectoryChanges', 'stagedChanges']) {
          final entries = res[key];
          if (entries is List) {
            for (final item in entries) {
              String path = '';
              if (item is String && item.isNotEmpty) {
                path = item;
              } else if (item is Map && item['uri'] is String) {
                path = item['uri'] as String;
              }
              if (path.isNotEmpty) {
                var clean = path.replaceAll('\\', '/');
                if (clean.startsWith('file:///')) clean = clean.substring(8);
                if (clean.startsWith('file://')) clean = clean.substring(7);
                if (!_modifiedFiles.contains(clean)) _modifiedFiles.add(clean);
                if (!list.any((f) => f.path == clean)) {
                  list.add(SessionModifiedFile(path: clean, additions: 1, deletions: 0));
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _modifiedFileList
            ..clear()
            ..addAll(list);
        });
      }
    } catch (_) {}
  }

  Widget _buildReviewTabContent() {
    return SessionReviewView(
      files: _modifiedFileList.isNotEmpty
          ? _modifiedFileList
          : _modifiedFiles
              .map((p) => SessionModifiedFile(
                    path: p,
                    additions: 1,
                    deletions: 0,
                  ))
              .toList(),
      onOpenFileDiff: (file) {
        _openUnifiedDiffViewer(
          fileName: file.fileName,
          diffContent: file.diffContent,
        );
      },
      onSplitDiffView: () {
        _openUnifiedDiffViewer(
          fileName: _modifiedFiles.isNotEmpty ? _modifiedFiles.first : null,
        );
      },
      onExpandAll: () {
        _openUnifiedDiffViewer(
          fileName: _modifiedFiles.isNotEmpty ? _modifiedFiles.first : null,
        );
      },
      onAcceptAll: () => _confirmBulkAction(
        title: 'Accepter toutes les modifications ?',
        message:
            'Les changements de cette session seront appliqués au workspace (git apply).',
        confirmLabel: 'Tout accepter',
        command: 'git apply --3way',
      ),
      onDiscardAll: () => _confirmBulkAction(
        title: 'Rejeter toutes les modifications ?',
        message:
            'Les changements de cette session seront annulés dans le workspace (git checkout).',
        confirmLabel: 'Tout rejeter',
        command: 'git checkout -- .',
      ),
    );
  }

  Widget _buildArtifactTabContent(String artifactName) {
    return _ArtifactTabContent(
      api: widget.api,
      artifactName: artifactName,
      activeSessionId: widget.activeSessionId,
      onOpenPlan: () => setState(() {
        _activeArtifact = null;
        _currentTab = SessionTabType.plan;
      }),
    );
  }

  Future<void> _openUnifiedDiffViewer({String? fileName, String? diffContent}) async {
    String diff = diffContent ?? '';
    if (diff.isEmpty && fileName != null && widget.api != null) {
      try {
        final res = await widget.api!.readFile(fileName);
        final fileContent = res['content'] as String? ?? '';
        if (fileContent.isNotEmpty) {
          final lines = fileContent.split('\n');
          final buf = StringBuffer();
          buf.writeln('--- a/$fileName');
          buf.writeln('+++ b/$fileName');
          buf.writeln('@@ -1,${lines.length} +1,${lines.length} @@');
          for (final l in lines) {
            buf.writeln(' $l');
          }
          diff = buf.toString();
        }
      } catch (_) {}
    }
    if (diff.isEmpty) {
      diff = '''--- a/${fileName ?? 'workspace/file.dart'}
+++ b/${fileName ?? 'workspace/file.dart'}
@@ -1,1 +1,1 @@
 // Aucun diff disponible pour ce fichier
''';
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UnifiedDiffViewer(
        diffContent: diff,
        fileName: fileName,
        onClose: () => Navigator.of(ctx).pop(),
        onSendReview: (comments) {
          Navigator.of(ctx).pop();
          _handleSendMessage('Revue de code sur ${fileName ?? "les modifications"} :\n$comments', queued: false);
        },
      ),
    );
  }

  /// P5 : tap sur un lien markdown file:/// (ex. implémentation_plan.md)
  /// → lit le fichier via le RPC officiel ReadFile du LS (le daemon gère
  /// l'URI file:/// telle quelle) et l'affiche dans ArtifactViewerModal.
  /// Ponytail : pas de workspacePath — les liens IDE sont des chemins
  /// absolus hôte, la voie RPC les accepte directement.
  void _openLocalFile(String filePath) {
    final api = widget.api;
    if (api == null) return;
    final name = filePath.split('/').last.split('\\').last;
    ArtifactViewerModal.show(
      context,
      api: api,
      artifactPath: filePath,
      artifactName: name.isEmpty ? 'fichier' : name,
      cascadeId: widget.activeSessionId,
      workspacePath: widget.workspacePath,
    );
  }

  void _openArtifactByName(String artifactName) {
    final api = widget.api;
    if (api == null) return;
    final cleanName = artifactName.trim();
    final fileName = cleanName.toLowerCase().contains('plan') && !cleanName.endsWith('.md')
        ? 'implementation_plan.md'
        : cleanName;
    ArtifactViewerModal.show(
      context,
      api: api,
      artifactPath: fileName,
      artifactName: cleanName.isNotEmpty ? cleanName : 'Implementation Plan',
      cascadeId: widget.activeSessionId,
      workspacePath: widget.workspacePath,
    );
  }

  Widget _buildPlanTabContent() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_latestPlanText == null || _latestPlanText!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.architecture_rounded, size: 36, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Aucun plan actif',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Les plans d\'implémentation générés par l\'agent apparaîtront ici.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: isDark ? AppColors.borderSubtle : scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Implementation Plan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
              GestureDetector(
                onTap: () => _handleSendMessage('Proceed', queued: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'Proceed ⌘↵',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MarkdownBubble(
          text: _latestPlanText!,
          api: widget.api,
          workspacePath: widget.activeProjectName,
          onLocalFile: _openLocalFile,
        ),
      ],
    );
  }

  Widget _buildTasksTabContent() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl_outlined, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Suivi des tâches',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            const Text(
              'Les tâches et sous-tâches de la session s\'afficheront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// P3 : API daemon pour le bouton « Exécuter » des blocs shell.
  final DaemonApi? api;

  /// P3 : chemin du workspace hôte pour créer le PTY du terminal.
  final String workspacePath;
  final bool isThoughtExpanded;
  final VoidCallback? onToggleThought;
  final VoidCallback? onProceedPlan;
  final VoidCallback? onViewPlan;
  final VoidCallback? onViewReview;
  final VoidCallback? onStop;
  final ValueChanged<ChatMessage>? onResend;

  /// P5 : tap sur un lien markdown file:/// → ouvre le fichier distant.
  final LocalFileTap? onLocalFile;
  final ValueChanged<String>? onOpenArtifact;

  const _MessageBubble({
    required this.message,
    this.api,
    this.workspacePath = '',
    this.onLocalFile,
    this.onOpenArtifact,
    this.isThoughtExpanded = false,
    this.onToggleThought,
    this.onProceedPlan,
    this.onViewPlan,
    this.onViewReview,
    this.onStop,
    this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isUser) {
      return RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.only(bottom: 16, left: 48),
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(
                color: isDark ? AppColors.borderStrong : scheme.outlineVariant,
                width: 0.8,
              ),
            ),
            child: SelectableText(
              message.text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: isDark ? AppColors.inkPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    final isError = message.isError;
    final hasContent = message.text.trim().isNotEmpty;
    final hasThought = message.thought != null && message.thought!.trim().isNotEmpty;

    if (!hasContent && !hasThought && !isError && !message.isStreaming) {
      return const SizedBox.shrink();
    }

    // isCompact = thought-only message (no body text, no error, not streaming)
    // → hide timestamp/action row, tighten margin
    final isCompact = !hasContent && !isError && !message.isStreaming;

    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.only(bottom: isCompact ? 6 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.modelLabel != null && message.modelLabel!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant, width: 0.6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 11,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        message.modelLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (hasThought || message.isStreaming) ...[
              ExecutionProgressView(
                messageId: message.id,
                thoughtText: message.thought,
                isStreaming: message.isStreaming,
                modelLabel: message.modelLabel,
                initiallyExpanded: isThoughtExpanded,
                onToggleExpand: onToggleThought,
                onStop: onStop,
                onOpenArtifact: onOpenArtifact,
              ),
            ],
            if (isError && (message.text.length < 120 && !message.text.contains('\n') && !message.text.startsWith('#')))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1214) : scheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF5C1D24) : scheme.error.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: isDark ? AppColors.danger : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.text,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: isDark ? const Color(0xFFFCA5A5) : scheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (hasContent || (message.isStreaming && message.text.isNotEmpty))
                MarkdownBubble(
                  text: message.text,
                  isStreaming: message.isStreaming,
                  api: api,
                  workspacePath: workspacePath,
                  onLocalFile: onLocalFile,
                ),
              if (!message.isStreaming &&
                  (message.text.contains('Implementation Plan') ||
                      message.text.contains('implementation_plan.md') ||
                      message.text.contains('# Plan')))
                ImplementationPlanCard(
                  summary: 'Le plan d\'implémentation est prêt. Vous pouvez l\'examiner ou approuver directement.',
                  onProceed: onProceedPlan ?? () {},
                  onViewPlan: onViewPlan ?? () {},
                ),
              if (!message.isStreaming && message.filesChanged.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilesChangedCard(
                    files: message.filesChanged,
                    additions: message.additions,
                    deletions: message.deletions,
                    onReview: onViewReview ?? () {},
                  ),
                ),
            ],
            if (!isCompact) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                Text(
                  message.timestamp,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
                if (message.sender == 'user') ...[
                  const SizedBox(width: 8),
                  if (message.isQueued) ...[
                    Icon(Icons.schedule_outlined, size: 12, color: scheme.tertiary),
                    const SizedBox(width: 3),
                    Text(
                      'En attente',
                      style: TextStyle(fontSize: 10, color: scheme.tertiary, fontWeight: FontWeight.w600),
                    ),
                  ] else ...[
                    Icon(Icons.done_all, size: 12, color: scheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      'Envoyé',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
                const Spacer(),
                if (message.isQueued && onResend != null) ...[
                  InkWell(
                    onTap: () => onResend?.call(message),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send_outlined, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Retransmettre',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (hasContent) ...[
                  Tooltip(
                    message: 'Copier le message',
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.text));
                        AppToast.show(
                          context,
                          message: 'Message copié dans le presse-papiers',
                          icon: Icons.copy_outlined,
                          type: ToastType.success,
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          label: 'Copier le message',
                          button: true,
                          child: Icon(Icons.copy_outlined,
                              size: 15, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Utile',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppToast.show(
                          context,
                          message: 'Merci pour votre retour !',
                          icon: Icons.thumb_up_outlined,
                          type: ToastType.info,
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          label: 'Marquer comme utile',
                          button: true,
                          child: Icon(Icons.thumb_up_outlined,
                              size: 15, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Pas utile',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppToast.show(
                          context,
                          message: 'Retour enregistré',
                          icon: Icons.thumb_down_outlined,
                          type: ToastType.info,
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          label: 'Marquer comme pas utile',
                          button: true,
                          child: Icon(Icons.thumb_down_outlined,
                              size: 15, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    ),
  );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _JumpToBottomButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('jump-to-bottom'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 4),
              if (count > 0) ...[
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                count > 0 ? 'nouveaux' : 'Retour en bas',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeEmptyState extends StatelessWidget {
  final String projectName;
  final ValueChanged<String> onSuggestionTap;
  final VoidCallback? onSelectProject;

  const _WelcomeEmptyState({
    required this.projectName,
    required this.onSuggestionTap,
    this.onSelectProject,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.terminal_rounded,
              size: 26,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Antigravity 2.0',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onSelectProject,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceInput : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppColors.borderSubtle : scheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_outlined, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  projectName.isNotEmpty ? projectName : 'Select project',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                if (onSelectProject != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _SuggestionChip(
              icon: Icons.edit_note_rounded,
              label: '/plan Concevoir une fonctionnalité',
              onTap: () => onSuggestionTap('/plan '),
            ),
            _SuggestionChip(
              icon: Icons.rate_review_outlined,
              label: '/review Auditer le code',
              onTap: () => onSuggestionTap('/review '),
            ),
            _SuggestionChip(
              icon: Icons.quiz_outlined,
              label: '/grill-me Cadrer l\'architecture',
              onTap: () => onSuggestionTap('/grill-me '),
            ),
            _SuggestionChip(
              icon: Icons.search,
              label: 'Rechercher dans le codebase',
              onTap: () => onSuggestionTap('Recherche dans le codebase : '),
            ),
          ],
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
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

class _ArtifactTabContent extends StatefulWidget {
  final DaemonApi? api;
  final String artifactName;
  final String activeSessionId;
  final VoidCallback? onOpenPlan;

  const _ArtifactTabContent({
    required this.api,
    required this.artifactName,
    required this.activeSessionId,
    this.onOpenPlan,
  });

  @override
  State<_ArtifactTabContent> createState() => _ArtifactTabContentState();
}

class _ArtifactTabContentState extends State<_ArtifactTabContent> {
  bool _isLoading = true;
  String _content = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ArtifactTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artifactName != widget.artifactName ||
        oldWidget.activeSessionId != widget.activeSessionId) {
      _load();
    }
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _isLoading = false;
        _error = 'Déconnecté du daemon';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await api.readFile(
        widget.artifactName,
        workspacePath: '.gemini/antigravity/brain/${widget.activeSessionId}',
      );
      if (mounted) {
        setState(() {
          _content = res['content'] as String? ?? '';
          _isLoading = false;
        });
      }
    } catch (_) {
      try {
        final res2 = await api.readFile(
          widget.artifactName,
          workspacePath: '.gemini/antigravity-ide/brain/${widget.activeSessionId}',
        );
        if (mounted) {
          setState(() {
            _content = res2['content'] as String? ?? '';
            _isLoading = false;
          });
          return;
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _error = 'Impossible de charger l\'artefact ($e2)';
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(scheme.primary),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 36, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final isPlan = widget.artifactName.toLowerCase().contains('plan');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.article_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.artifactName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (isPlan)
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Proceed ⌘↵'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.onOpenPlan,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant),
        const SizedBox(height: 12),
        MarkdownBody(content: _content.isNotEmpty ? _content : 'Artefact vide.'),
      ],
    );
  }
}
