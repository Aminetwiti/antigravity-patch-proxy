import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/db/database_helper.dart';
import '../network/outbox.dart';
import 'messages.dart';

class CallError implements Exception {
  final String message;
  CallError(this.message);
  @override
  String toString() => 'CallError: $message';
}

/// High-level typed client over the Daemon Bridge WebSocket (protocol v1).
///
/// Wire protocol (source of truth: remote/daemon/pkg/gateway/websocket.go):
///   → {"type":"list_sessions","requestId":"r1"}
///   ← {"type":"response","requestId":"r1","data":{...}}
///   → {"type":"send_prompt","requestId":"p1","cascadeId":"...","prompt":"..."}
///   ← {"type":"stream_start","requestId":"p1"}
///   ← {"type":"stream_delta","requestId":"p1","data":{"events":[...]}}
///   ← {"type":"stream_end","requestId":"p1"}
///   → {"type":"submit_approval","requestId":"r2","cascadeId":"...","callId":"...","decision":"allow"|"deny"}
///
/// Requests are correlated by `requestId`; streaming calls surface as a
/// Dart [Stream] that closes on `stream_end`.
class DaemonApi {
  final Stream<dynamic> _incoming;
  final void Function(dynamic) _send;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final Duration _timeout;

  /// Batching des broadcasts (A3) : quand le daemon relaie une rafale de
  /// frames (stream_start + N deltas + stream_end), on les regroupe en UNE
  /// émission toutes les 100 ms au lieu de N setState — l'UI reste fluide
  /// (le rendu des bulles est déjà throttlé côté écran, celui-ci protège
  /// les autres auditeurs globaux comme la liste des sessions).
  ///
  /// La PREMIÈRE frame d'une rafale est émise immédiatement (zéro latence
  /// pour un événement isolé comme approval_expired) ; les suivantes qui
  /// arrivent dans la fenêtre de 100 ms sont regroupées puis délivrées en
  /// une seule passe.
  /// ponytail: délai fixe de 100 ms (pas de fenêtre glissante adaptative),
  /// plafond acceptable — chemin d'upgrade si le daemon émet par salves > 10/s.
  Timer? _batchTimer;
  final List<Map<String, dynamic>> _batch = [];
  static const _batchWindow = Duration(milliseconds: 100);

  int _nextRequestId = 0;

  /// Résolution et migration automatique des anciens chemins de stockage 1.x vers Antigravity 2.0
  /// Prise en charge explicite des caractères CJK (Chinois/Japonais/Coréen) et accents.
  static String resolveWorkspacePath(String rawPath) {
    try {
      final decoded = utf8.decode(rawPath.codeUnits, allowMalformed: true);
      if (decoded.contains('.gemini/antigravity') && !decoded.contains('antigravity-ide')) {
        return decoded.replaceAll('.gemini/antigravity', '.gemini/antigravity-ide');
      }
      return decoded;
    } catch (_) {
      return rawPath;
    }
  }

  /// Broadcast de chaque message daemon décodé (UI listeners, logging).
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Retourne les messages broadcast en attente d'émission par le batch 100 ms
  /// (utile aux tests pour forcer le flush).
  @visibleForTesting
  int get pendingBatchCount => _batch.length;

  DaemonApi({
    required Stream<dynamic> incoming,
    required void Function(dynamic) send,
    Duration timeout = const Duration(seconds: 5),
    OutboxQueue? outbox,
  }) : _incoming = incoming,
       _send = send,
       _timeout = timeout,
       _outbox = outbox {
    _incoming.listen(_onMessage);
  }

  String _newRequestId() => 'r${++_nextRequestId}';

  /// Envoie un message et attend la réponse, mais signale un échec réseau
  /// plutôt que de planter : renvoie false quand le socket est coupé (le
  /// message est mis en outbox pour être rejoué à la reconnexion).
  /// Utilisé par l'UI pour afficher « Message mis en file » vs « Envoyé ».
  Future<bool> sendWithResult(
    String type, [
    Map<String, dynamic> params = const {},
  ]) async {
    final id = _newRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = {'type': type, 'requestId': id, ...params};
    final outbox = _outbox;
    if (outbox != null) {
      outbox.enqueue(message);
    }
    _send(message);
    try {
      await completer.future.timeout(
        _timeout,
        onTimeout: () {
          _pending.remove(id);
          throw TimeoutException('Daemon did not respond to $type ($id)');
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Émet un message broadcast vers tous les abonnés : le premier message
  /// d'une rafale part immédiatement, les suivants dans la fenêtre de 100 ms
  /// sont regroupés. Un événement isolé ne subit donc AUCUNE latence.
  void _emitBatched(Map<String, dynamic> msg) {
    if (_batchTimer == null || !_batchTimer!.isActive) {
      // Cas nominal : émission immédiate, sans latence.
      _events.add(msg);
      // Ouvre la fenêtre : tout ce qui arrive pendant 100 ms est groupé.
      _batchTimer = Timer(_batchWindow, _flushBatch);
      return;
    }
    _batch.add(msg);
  }

  /// Vide la fenêtre de batch immédiatement. Appelée par le timer (fin de
  /// fenêtre) et par [DaemonApi._onMessage] sur un `stream_end` : un état
  /// terminal (tâche finie, annulée, bloquée) doit atteindre l'UI sans
  /// latence résiduelle, même s'il arrive 30 ms après un delta.
  void _flushBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_batch.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_batch);
    _batch.clear();
    for (final m in pending) {
      _events.add(m);
    }
  }

  // Étape 5 : si un outbox est fourni, les messages envoyés hors-ligne sont
  // mis en file ; à la reconnexion (reconnectVersion change), on les rejoue
  // PUIS on re-synchronise toujours (même file vide : les sessions peuvent
  // avoir changé pendant la coupure).
  final OutboxQueue? _outbox;
  OutboxReplayer? _replayer;
  int _lastReconnectVersion = 0;
  ValueListenable<int>? _reconnectVersion;
  VoidCallback? _reconnectListener;

  void attachReconnect(
    ValueListenable<int> version,
    Future<Map<String, dynamic>> Function() resync,
  ) {
    _reconnectVersion?.removeListener(_reconnectListener!);
    _reconnectVersion = version;
    final outbox = _outbox;
    // Le replayer est créé une fois : onReconnect() rejoue la file (si non
    // vide) puis appelle toujours resync — la re-synchronisation n'est donc
    // plus conditionnée à outbox.hasPending (reconnexion « silencieuse »).
    _replayer = OutboxReplayer(
      queue: outbox ?? OutboxQueue(),
      send: (msg) {
        final clean = Map<String, dynamic>.from(msg)..remove('queuedAt');
        _send(clean);
      },
      resync: resync,
    );
    _reconnectListener = () {
      final v = version.value;
      if (v == _lastReconnectVersion) return;
      _lastReconnectVersion = v;
      _replayer!.onReconnect();
    };
    version.addListener(_reconnectListener!);
  }

  void dispose() {
    _reconnectVersion?.removeListener(_reconnectListener!);
    _batchTimer?.cancel();
    if (_batch.isNotEmpty) {
      for (final m in List<Map<String, dynamic>>.from(_batch)) {
        _events.add(m);
      }
      _batch.clear();
    }
    _events.close();
    for (final c in _pending.values) {
      c.completeError(StateError('DaemonApi disposed'));
    }
    _pending.clear();
    for (final s in _streams.values) {
      s.close();
    }
    _streams.clear();
  }

  /// Unary call resolved when a `response`/`error` with the same requestId
  /// arrives (30s timeout).
  Future<Map<String, dynamic>> rpc(
    String type, [
    Map<String, dynamic> params = const {},
  ]) {
    final id = _newRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = {'type': type, 'requestId': id, ...params};
    final outbox = _outbox;
    if (outbox != null) {
      outbox.enqueue(message); // file jusqu'à réponse ; drainé à la réponse
    }
    _send(message);
    return completer.future.timeout(
      _timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Daemon did not respond to $type ($id)');
      },
    );
  }

  Future<Map<String, dynamic>> heartbeat() => rpc('heartbeat');

  Future<Map<String, dynamic>> listSessions() async {
    try {
      final data = await rpc('list_sessions');
      if (data['fields'] != null) {
        try {
          await DatabaseHelper.instance.saveSessions(data['fields'] as List<dynamic>);
        } catch (_) {}
      }
      return data;
    } catch (e) {
      // Offline fallback
      final sessions = await DatabaseHelper.instance.getSessions();
      return {'fields': sessions};
    }
  }

  Future<Map<String, dynamic>> getSessionHistory(String cascadeId) async {
    try {
      final data = await rpc('get_session_history', {'cascadeId': cascadeId});
      if (data['messages'] != null) {
        await DatabaseHelper.instance.saveSessionMessages(cascadeId, data['messages'] as List<dynamic>);
      }
      return data;
    } catch (e) {
      final messages = await DatabaseHelper.instance.getSessionMessages(cascadeId);
      if (messages != null) {
        return {'messages': messages};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCascade(String workspacePath) =>
      rpc('create_cascade', {'workspacePath': workspacePath});

  Future<Map<String, dynamic>> listFiles(String workspacePath) =>
      rpc('list_files', {'workspacePath': workspacePath});

  Future<Map<String, dynamic>> readFile(
    String filePath, {
    String? workspacePath,
  }) => rpc('read_file', {
    'filePath': filePath,
    if (workspacePath != null) 'workspacePath': workspacePath,
  });

  Future<Map<String, dynamic>> getContext() => rpc('get_context');

  Future<Map<String, dynamic>> submitApproval({
    required String cascadeId,
    required String callId,
    required bool allow,
    String trajectoryId = '',
    int stepIndex = -1,
    String approvalType = 'approval',
    String command = '',
    ApprovalScope scope = ApprovalScope.once,
  }) => rpc('submit_approval', {
    'cascadeId': cascadeId,
    'callId': callId,
    'trajectoryId': trajectoryId,
    'stepIndex': stepIndex,
    'approvalType': approvalType,
    'command': command,
    'scope': scope == ApprovalScope.session ? 'session' : 'once',
    'decision': allow ? 'allow' : 'deny',
  });

  /// B2 — contexte d'une approbation en attente (tap sur la notification
  /// locale alors que le stream_delta d'origine a pu être perdu). Renvoie
  /// null si aucune approbation n'est en attente pour cette cascade.
  Future<Map<String, dynamic>?> getPendingApproval(String cascadeId) async {
    final data = await rpc('get_pending_approval', {'cascadeId': cascadeId});
    final info = data['data'] ?? data;
    return info is Map && info.isNotEmpty ? info.cast<String, dynamic>() : null;
  }

  /// Streaming call: emits each decoded message (`stream_start`,
  /// `stream_delta`, ...) until `stream_end` closes the stream.
  Stream<Map<String, dynamic>> sendPrompt(String cascadeId, String prompt) {
    final id = _newRequestId();
    final controller = StreamController<Map<String, dynamic>>();
    _streams[id] = controller;
    final message = {
      'type': 'send_prompt',
      'requestId': id,
      'cascadeId': cascadeId,
      'prompt': prompt,
    };
    final outbox = _outbox;
    if (outbox != null) {
      outbox.enqueue(message); // file jusqu'à stream_end ; drainé à la fin
    }
    _send(message);
    return controller.stream;
  }

  static const Duration mcpTimeout = Duration(seconds: 15);

  /// Exécute un outil MCP avec un délai d'attente explicite de 15s
  /// pour éviter le blocage indéfini de l'agent.
  Future<Map<String, dynamic>> executeMcpTool({
    required String serverName,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    final id = _newRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = {
      'type': 'call_mcp_tool',
      'requestId': id,
      'serverName': serverName,
      'toolName': toolName,
      'arguments': arguments,
    };
    _send(message);
    try {
      return await completer.future.timeout(
        mcpTimeout,
        onTimeout: () {
          _pending.remove(id);
          throw TimeoutException(
            'L\'appel de l\'outil MCP "$toolName" sur le serveur "$serverName" a expiré après ${mcpTimeout.inSeconds}s.',
          );
        },
      );
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('auth')) {
        // Tentative automatique de rafraîchissement du jeton OAuth au lieu de supprimer les identifiants
        await refreshOAuthToken(serverName);
        return rpc('call_mcp_tool', {
          'serverName': serverName,
          'toolName': toolName,
          'arguments': arguments,
        });
      }
      rethrow;
    }
  }

  /// Rafraîchissement automatique des jetons OAuth pour Salesforce et Atlassian MCP
  Future<Map<String, dynamic>> refreshOAuthToken(String serverName) async {
    final provider = serverName.toLowerCase();
    final endpoint = provider.contains('salesforce')
        ? '/services/oauth2/token'
        : provider.contains('atlassian')
            ? 'https://auth.atlassian.com/oauth/token'
            : '/oauth/token';

    return rpc('refresh_mcp_oauth_token', {
      'serverName': serverName,
      'endpoint': endpoint,
      'grantType': 'refresh_token',
    });
  }

  /// Connexion à un serveur MCP avec timeout de 15s.
  Future<Map<String, dynamic>> connectMcpServer(String serverName) async {
    return rpc('connect_mcp_server', {'serverName': serverName}).timeout(
      mcpTimeout,
      onTimeout: () => throw TimeoutException('Connexion au serveur MCP "$serverName" a expiré après 15s.'),
    );
  }

  /// Sends a slash command (e.g. `/model`, `/compact`) to the daemon, which
  /// routes it to the language server via HandleStreamingCommand (terminal
  /// source). Unary call: resolves with the `response` message data.
  Future<Map<String, dynamic>> sendCommand(String command) {
    return rpc('send_command', {'command': command});
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return; // daemon sends JSON text only
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String? ?? '';
    final requestId = msg['requestId'] as String? ?? '';
    final rawData = msg['data'];
    // Tolerant : certaines réponses poussées par le daemon portent un payload
    // non-map (string, nombre…). On les neutralise plutôt que de planter —
    // l'événement reste broadcasté avec data vide (A6).
    final data =
        rawData is Map
            ? rawData.map((k, v) => MapEntry('$k', v))
            : const <String, dynamic>{};
    final error = msg['error'] as String?;

    if (type == 'stream_start' || type == 'stream_delta') {
      final controller = _streams[requestId];
      if (controller == null) {
        // Stream déclenché par une AUTRE surface (PC ou autre téléphone) :
        // le broadcast daemon le relaie ici sans requestId local. On le
        // réémet sur _events (marqué) pour que l'UI suive la session.
        _emitBatched({...msg, 'broadcast': true});
        return;
      }
      controller.add(msg);
      _emitBatched(msg);
      return;
    }

    if (type == 'stream_end') {
      _outbox?.remove(requestId);
      final controller = _streams[requestId];
      if (controller != null) {
        // Livre le message stream_end (outcome structuré) au listener local
        // AVANT de fermer : onDone ne transporte pas de données.
        controller.add(msg);
        controller.close();
        _streams.remove(requestId);
      }
      // Toujours broadcasté — un stream_end sans controller local (session
      // pilotée depuis une autre surface, ou stream déjà fermé) doit quand
      // même fermer le statut « en cours » dans l'UI (A8).
      _emitBatched(msg);
      return;
    }

    final completer = _pending.remove(requestId);
    // Drain même si le completer a expiré (timeout) : la réponse est arrivée,
    // rejouer ce message à la reconnexion créerait un doublon.
    _outbox?.remove(requestId);
    if (completer == null) {
      // Événement poussé par le serveur sans requête locale (approval_expired,
      // …) : re-marqué broadcast pour que les écouteurs de session le voient.
      _emitBatched({...msg, 'broadcast': true});
      return;
    }
    if (type == 'error' || error != null) {
      completer.completeError(Exception(error ?? 'Unknown daemon error'));
    } else {
      completer.complete(data);
    }
    _emitBatched(msg);
  }
}
