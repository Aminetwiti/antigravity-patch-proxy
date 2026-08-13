import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/websocket_client.dart';
import '../../core/notifications/approval_notifier.dart';
import '../../core/protocol/daemon_api.dart';
import '../../core/protocol/messages.dart';
import '../../core/protocol/stream_parser.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat_input_bar.dart';
import '../../widgets/connection_banner.dart';
import '../../widgets/markdown_bubble.dart';
import '../../widgets/tool_approval_card.dart';

class ChatStreamScreen extends StatefulWidget {
  final DaemonApi? api;
  final String activeSessionId;
  final String activeProjectName;
  final bool isConnected;

  /// Client WebSocket partagé (null en tests/aperçu) — fournit l'état de
  /// connexion en temps réel (statut, tentative, compte à rebours) au banner.
  final DaemonWebSocketClient? wsClient;

  const ChatStreamScreen({
    super.key,
    required this.api,
    required this.activeSessionId,
    required this.activeProjectName,
    this.isConnected = true,
    this.wsClient,
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
  static final Map<String, String> _sessionDrafts = {};
  String get currentDraft => _sessionDrafts[widget.activeSessionId] ?? '';
  void setDraft(String draft) => _sessionDrafts[widget.activeSessionId] = draft;

  List<ChatMessage> get _messages {
    return _sessionMessages.putIfAbsent(widget.activeSessionId, () => []);
  }

  // File d'attente des approbations (audit UX P0-1) : une 2ᵉ demande ne doit
  // PLUS écraser la 1ʳᵉ — chaque carte reste approvable via ◀ ▶.
  final List<ToolApprovalRequest> _pendingApprovals = [];
  int _approvalIndex = -1;
  // callIds dont le daemon a broadcasté approval_expired : la carte reste
  // affichée (pourquoi elle a disparu) mais passe en lecture seule.
  final Set<String> _expiredCallIds = {};

  ToolApprovalRequest? get _currentApproval {
    if (_pendingApprovals.isEmpty ||
        _approvalIndex < 0 ||
        _approvalIndex >= _pendingApprovals.length) {
      return null;
    }
    return _pendingApprovals[_approvalIndex];
  }

  StreamSubscription<Map<String, dynamic>>? _streamSub;
  StreamSubscription<Map<String, String>>? _tapSub;
  int _messageCounter = 0;

  static const _stillWorkingDelay = Duration(seconds: 15);
  final Set<String> _pendingApprovalCallIds = {};
  final Set<String> _processedCallIds = {};
  Timer? _stillWorkingTimer;
  int _activeStreamCount = 0;
  bool _showStillWorking = false;
  Map<String, dynamic>? _lastLocalStreamEnd;
  final Map<String, String> _externalThoughts = {};

  Timer? _throttleTimer;
  bool _needsStateUpdate = false;
  static const _throttleDuration = Duration(milliseconds: 100);

  // Bug persistance pensées : état d'expansion stocké ici par message ID
  // pour survivre aux switches de session et aux rebuilds de la liste.
  // ponytail: Set suffit (expandé = dans le Set, replié = absent).
  final Set<String> _expandedThoughts = {};

  // Auto-scroll pendant le streaming (audit UX P1-6).
  final ScrollController _scrollController = ScrollController();

  // ── État de connexion live (alimenté par wsClient) ─────────────────────
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _attempt = 0;
  Duration _nextRetryIn = Duration.zero;
  bool _isManualDisconnect = false;
  bool _notifiedLost = false;
  // L'app est au premier plan : le banner suffit, pas besoin de notification
  // locale (qui vise l'écran verrouillé / l'app en arrière-plan).
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchBroadcastStreams();
    _setupConnectionListeners();
    _watchNotificationTaps();
    // Sans wsClient (tests/aperçu), l'état vient de la prop isConnected.
    if (widget.wsClient == null) {
      _status = widget.isConnected
          ? ConnectionStatus.connected
          : ConnectionStatus.disconnected;
    }
  }

  /// B2 — tap-to-deep-link : quand l'utilisateur tape la notification locale
  /// « Approbation requise » (app en arrière-plan ou tuée), on re-fetch le
  /// contexte via get_pending_approval et on pousse la carte. Le daemon garde
  /// l'approbation même si le stream_delta d'origine a été perdu.
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
      _pendingApprovalFromTap();
    });
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _streamSub?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _streamSub?.resume();
    }
  }

  @override
  void didUpdateWidget(covariant ChatStreamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSessionId != widget.activeSessionId) {
      // Bug #9 : ne vider que si aucun stream actif pour cette session.
      // Les messages sont préservés dans _sessionMessages par session.
      if (_activeStreamCount == 0) {
        _pendingApprovals.clear();
        _approvalIndex = -1;
        _expiredCallIds.clear();
        _pendingApprovalCallIds.clear();
      }
    }
    if (oldWidget.api != widget.api) {
      // Bug agent bloqué : réinitialiser le compteur de streams actifs à la
      // reconnexion pour ne pas rester bloqué si des stream_end ont été perdus
      // pendant la coupure réseau.
      _activeStreamCount = 0;
      _stillWorkingTimer?.cancel();
      if (mounted && _showStillWorking) setState(() => _showStillWorking = false);
      _watchBroadcastStreams();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _throttleTimer?.cancel();
    _streamSub?.cancel();
    _tapSub?.cancel();
    _stillWorkingTimer?.cancel();
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
      final outcome = _lastLocalStreamEnd?['data']?['outcome'] as String? ?? 'done';
      // Ne pas vider automatiquement la file si l'étape a été annulée ou s'est terminée par une erreur
      if (outcome == 'cancelled' || outcome == 'error') {
        _messageQueue.clear();
      } else if (_messageQueue.isNotEmpty) {
        final next = _messageQueue.removeAt(0);
        final text = next['text'] as String;
        _sendPromptToDaemon(text);
      }
    }
  }

  void _handleStreamEnded(Map<String, dynamic> msg) {
    final data = msg['data'];
    if (data is! Map<String, dynamic>) return;
    if (msg['data']?['hostActive'] == true) return;
    final outcome = data['outcome'] as String? ?? 'done';
    final cascadeId = data['cascadeId'] as String? ?? widget.activeSessionId;
    final message = data['message'] as String? ?? '';

    // Si une étape a été annulée, vider la file d'attente pour éviter les envois auto
    if (outcome == 'cancelled') {
      _messageQueue.clear();
    }

    ApprovalNotifier.instance.notifyTaskEnded(
      cascadeId: cascadeId,
      outcome: outcome,
      message: message,
    );
  }

  void _addApproval(ToolApprovalRequest approval,
      {bool hostActive = false, bool fromTap = false}) {
    // Bug #7 : guard broadcast path — un même callId ne doit jamais re-afficher
    // sa carte après reconnexion si l'utilisateur l'a déjà traitée.
    if (_processedCallIds.contains(approval.callId)) return;
    if (_pendingApprovals.any((a) => a.callId == approval.callId)) return;
    _expiredCallIds.remove(approval.callId);
    if (_currentApproval == null) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      final wasEmpty = _pendingApprovals.isEmpty;
      _pendingApprovals.add(approval);
      // UX P0-1 : une 2ᵉ approbation ne « vole » pas la carte affichée —
      // l'index reste sur la demande en cours (la nouvelle se rejoint via ▶).
      if (wasEmpty) _approvalIndex = 0;
      _pendingApprovalCallIds.add(approval.callId);
    });
    if (!hostActive && !fromTap && ApprovalNotifier.instance.initialized) {
      ApprovalNotifier.instance.notifyApprovalRequired(
        callId: approval.callId,
        cascadeId: approval.cascadeId.isEmpty
            ? widget.activeSessionId
            : approval.cascadeId,
        toolName: approval.toolName,
        command: approval.command,
      );
    }
  }

  void _removeApproval(String callId) {
    final i = _pendingApprovals.indexWhere((a) => a.callId == callId);
    if (i < 0) return;
    setState(() {
      _pendingApprovals.removeAt(i);
      // L'index reste sur la demande qui suit celle retirée (ou la dernière
      // restante) : la carte visible bascule proprement et le compteur
      // « x/total » reflète la pile restante. P0-1 : après décision sur la
      // 2ᵉ de 2, on retombe sur la 1ʳᵉ (1/1), pas sur une pile vide.
      _approvalIndex = _pendingApprovals.isEmpty
          ? -1
          : math.min(i, _pendingApprovals.length - 1);
      _pendingApprovalCallIds.remove(callId);
    });
    ApprovalNotifier.instance.cancelApproval(callId);
  }

  void _watchBroadcastStreams() {
    _streamSub?.cancel();
    _streamSub = widget.api?.events.listen((msg) {
      final isBroadcast = msg['broadcast'] == true;
      if (!isBroadcast || !mounted) return;
      final type = msg['type'] as String?;
      final requestId = msg['requestId'] as String? ?? '';
      final sessionId = msg['data']?['cascadeId'] as String?;

      // Bug tâches arrière-plan : si l'évènement concerne une autre session,
      // on le bufferise dans _sessionMessages[sessionId] au lieu de le jeter.
      // L'utilisateur verra les messages à jour quand il reviendra sur la session.
      final isActiveSession = sessionId == null || sessionId == widget.activeSessionId;
      if (!isActiveSession) {
        // sessionId is non-null here (isActiveSession=false implies sessionId != null)
        final buf = _sessionMessages.putIfAbsent(sessionId, () => []);
        if (type == 'stream_start') {
          buf.add(ChatMessage(
            id: 'ext-$requestId',
            sender: 'assistant',
            text: '',
            timestamp: _timestamp(),
            isStreaming: true,
          ));
        } else if (type == 'stream_delta') {
          final idx = buf.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            final textDelta = StreamDeltaParser.textOf(msg);
            final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
            _externalThoughts[requestId] =
                (_externalThoughts[requestId] ?? '') + thoughtDelta;
            buf[idx] = buf[idx].copyWith(
              text: buf[idx].text + textDelta,
              thought: _externalThoughts[requestId]!.isNotEmpty
                  ? _externalThoughts[requestId]!.trim()
                  : buf[idx].thought,
            );
          }
        } else if (type == 'stream_end') {
          final idx = buf.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) buf[idx] = buf[idx].copyWith(isStreaming: false);
          _externalThoughts.remove(requestId);
        }
        return; // ne pas toucher l'état UI de la session active
      }

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

        final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
        if (idx >= 0) {
          final current = _messages[idx];
          _externalThoughts[requestId] =
              (_externalThoughts[requestId] ?? '') + thoughtDelta;
          _messages[idx] = current.copyWith(
            text: current.text + textDelta,
            thought: _externalThoughts[requestId]!.isNotEmpty
                ? _externalThoughts[requestId]!.trim()
                : current.thought,
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
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            ),
            hostActive: hostActive,
          );
        }

        _scheduleThrottledUpdate();
      } else if (type == 'stream_end') {
        _onStreamEnded();
        _handleStreamEnded(msg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
          _externalThoughts.remove(requestId);
        });
        _scrollToBottom();
      } else if (type == 'approval_expired') {
        // Phase 6 : le daemon a auto-refusé l'approbation (timeout) — la carte
        // reste visible en lecture seule pour expliquer la disparition, et la
        // notification locale est annulée.
        final callId = msg['data']?['callId'] as String? ??
            msg['data']?['approvalId'] as String? ??
            '';
        if (callId.isNotEmpty && _pendingApprovalCallIds.contains(callId)) {
          setState(() => _expiredCallIds.add(callId));
          _pendingApprovalCallIds.remove(callId);
          ApprovalNotifier.instance.cancelApproval(callId);
        }
      }
    });
  }

  final List<Map<String, dynamic>> _messageQueue = [];

  void _handleSendMessage(String text, {bool queued = false}) {
    final api = widget.api;
    setState(() {
      _messages.add(ChatMessage(
        id: 'm${++_messageCounter}',
        sender: 'user',
        text: text + (queued ? ' (File d\'attente)' : ''),
        timestamp: _timestamp(),
      ));
    });

    if (api == null) return;

    if (queued && _activeStreamCount > 0) {
      _messageQueue.add({'text': text, 'activeSessionId': widget.activeSessionId});
      return;
    }

    _sendPromptToDaemon(text);
  }

  void _sendPromptToDaemon(String text) {
    final api = widget.api;
    if (api == null) return;

    _onStreamEnded();
    final assistantId = 'a${++_messageCounter}';
    _lastLocalStreamEnd = null;
    setState(() {
      _messages.add(ChatMessage(
        id: assistantId,
        sender: 'assistant',
        text: '',
        timestamp: _timestamp(),
        isStreaming: true,
      ));
    });
    _scrollToBottom();

    var thoughtBuffer = StringBuffer();
    _onStreamStarted();
    api.sendPrompt(widget.activeSessionId, text).listen(
      (msg) {
        if (msg['type'] == 'stream_end') {
          _lastLocalStreamEnd = msg;
        }
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        if (!mounted) return;

        if (textDelta.isNotEmpty || thoughtDelta.isNotEmpty) {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            final current = _messages[idx];
            thoughtBuffer.write(thoughtDelta);
            _messages[idx] = current.copyWith(
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
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            ),
            hostActive: hostActive,
          );
        }

        _scheduleThrottledUpdate();
      },
      onDone: () {
        if (!mounted) return;
        _onStreamEnded();
        _handleStreamEnded(_lastLocalStreamEnd ?? const {});
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            // Audit UX P2-9 : un stream_end avec error/outcome error doit
            // afficher la bulle d'erreur dédiée (fond danger), pas une bulle
            // vide ni du markdown brut.
            final end = _lastLocalStreamEnd ?? const {};
            final error =
                end['error'] as String? ??
                (end['data'] is Map
                    ? (end['data'] as Map)['outcome'] == 'error'
                        ? (end['data'] as Map)['message'] as String? ?? 'Erreur'
                        : null
                    : null);
            _messages[idx] = _messages[idx].copyWith(
              isStreaming: false,
              isError: error != null,
              text: error != null
                  ? (_messages[idx].text.isEmpty ? error : _messages[idx].text)
                  : _messages[idx].text,
            );
          }
        });
        _scrollToBottom();
      },
      onError: (e) {
        if (!mounted) return;
        _onStreamEnded();
        ApprovalNotifier.instance.notifyTaskEnded(
          cascadeId: widget.activeSessionId,
          outcome: 'error',
          message: e.toString(),
        );
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(
              text: _messages[idx].text.isEmpty ? 'Erreur : $e' : _messages[idx].text,
              isStreaming: false,
              isError: _messages[idx].text.isEmpty,
            );
          }
        });
      },
    );
  }

  void _handleToolDecision(ToolDecision decision,
      {ApprovalScope scope = ApprovalScope.once}) {
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
    // N'auto-scroll pendant la lecture que si l'utilisateur est déjà proche du bas (< 120px).
    if ((maxScroll - currentScroll) < 120 || currentScroll == 0) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
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
    final approval = _currentApproval;
    if (approval == null) return const SizedBox.shrink();
    final total = _pendingApprovals.length;
    final expired = _expiredCallIds.contains(approval.callId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (total > 1)
                IconButton(
                  key: const Key('approval-prev'),
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
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (total > 1)
                IconButton(
                  key: const Key('approval-next'),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  tooltip: 'Approbation suivante',
                  onPressed: () => setState(() {
                    _approvalIndex = (_approvalIndex + 1) % total;
                  }),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('approval-dismiss'),
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

  @override
  Widget build(BuildContext context) {
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

    if (_messages.isEmpty && _currentApproval == null) {
      return Column(
        children: [
          connectivityBanner,
          Expanded(
            child: Center(
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
                            widget.activeProjectName,
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ChatInputBar(
                        onSend: _handleSendMessage,
                        isConnected: isConnected,
                      ),
                      const SizedBox(height: 64),
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
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildReminderBanners(),
              ..._messages.map((msg) => TweenAnimationBuilder<double>(
                    key: ValueKey(msg.id),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuart,
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: _MessageBubble(
                        message: msg,
                        // Bug persistance pensées : state d'expansion géré
                        // dans le parent pour survivre aux rebuilds.
                        isThoughtExpanded: _expandedThoughts.contains(msg.id),
                        onToggleThought: () => setState(() {
                          if (_expandedThoughts.contains(msg.id)) {
                            _expandedThoughts.remove(msg.id);
                          } else {
                            _expandedThoughts.add(msg.id);
                          }
                        }),
                      ),
                  )),
            ],
          ),
        ),
        _buildApprovalArea(),
        ChatInputBar(
          onSend: _handleSendMessage,
          isConnected: isConnected,
          hasActiveStream: _activeStreamCount > 0,
        ),
      ],
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isThoughtExpanded;
  final VoidCallback? onToggleThought;

  const _MessageBubble({
    required this.message,
    this.isThoughtExpanded = false,
    this.onToggleThought,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    final scheme = Theme.of(context).colorScheme;

    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16, left: 40),
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SelectableText(
            message.text,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
          ),
        ),
      );
    }

    final isError = message.isError;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.thought != null) ...[
            InkWell(
              onTap: onToggleThought,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        message.thought!,
                        key: Key('thought-${message.id}'),
                        maxLines: isThoughtExpanded ? null : 1,
                        overflow: isThoughtExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isThoughtExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (isError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.danger,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            MarkdownBubble(
              text: message.text,
              isStreaming: message.isStreaming,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Timestamp capturé mais jamais affiché (audit UX P1-7).
              Text(
                message.timestamp,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Tooltip(
                message: 'Copier le message',
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
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
                    child: Semantics(
                      label: 'Copier le message',
                      button: true,
                      child: Icon(Icons.copy_outlined,
                          size: 14, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Utile',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Semantics(
                    label: 'Marquer comme utile',
                    button: true,
                    child: Icon(Icons.thumb_up_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Pas utile',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Semantics(
                    label: 'Marquer comme pas utile',
                    button: true,
                    child: Icon(Icons.thumb_down_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
