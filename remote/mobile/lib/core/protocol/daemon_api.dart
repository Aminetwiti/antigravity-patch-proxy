import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, VoidCallback;
import 'package:meta/meta.dart';

import '../network/outbox.dart';
import 'messages.dart';

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
  /// ponytail: délai fixe de 100 ms (pas de fenêtre glissante adaptative),
  /// plafond acceptable — chemin d'upgrade si le daemon émet par salves > 10/s.
  Timer? _batchTimer;
  final List<Map<String, dynamic>> _batch = [];

  int _nextRequestId = 0;

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
  })  : _incoming = incoming,
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

  /// Émet un message broadcast vers tous les abonnés, en le groupant dans la
  /// fenêtre de 100 ms. Si un seul message arrive, il est émis immédiatement
  /// (pas de latence ajoutée au cas nominal).
  void _emitBatched(Map<String, dynamic> msg) {
    if (_batch.isEmpty && (_batchTimer == null || !_batchTimer!.isActive)) {
      // Cas nominal : émission immédiate, sans latence.
      _events.add(msg);
      return;
    }
    _batch.add(msg);
    _batchTimer ??= Timer(const Duration(milliseconds: 100), () {
      final pending = List<Map<String, dynamic>>.from(_batch);
      _batch.clear();
      _batchTimer = null;
      for (final m in pending) {
        _events.add(m);
      }
    });
  }

  // Étape 5 : si un outbox est fourni, les messages envoyés hors-ligne sont
  // mis en file ; à la reconnexion (reconnectVersion change), on les rejoue.
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
    _reconnectListener = () {
      final v = version.value;
      if (v == _lastReconnectVersion) return;
      _lastReconnectVersion = v;
      final outbox = _outbox;
      if (outbox != null && outbox.hasPending) {
        _replayer ??= OutboxReplayer(
          queue: outbox,
          send: (msg) {
            final clean = Map<String, dynamic>.from(msg)
              ..remove('queuedAt');
            _send(clean);
          },
          resync: resync,
        );
        _replayer!.onReconnect();
      }
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
  Future<Map<String, dynamic>> call(
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

  Future<Map<String, dynamic>> heartbeat() => call('heartbeat');

  /// Lists sessions (raw protobuf field dump from the daemon; `fields`
  /// length == trajectory count).
  Future<Map<String, dynamic>> listSessions() => call('list_sessions');

  Future<Map<String, dynamic>> createCascade(String workspacePath) =>
      call('create_cascade', {'workspacePath': workspacePath});

  Future<Map<String, dynamic>> listFiles(String workspacePath) =>
      call('list_files', {'workspacePath': workspacePath});

  Future<Map<String, dynamic>> readFile(String filePath, {String? workspacePath}) =>
      call('read_file', {
        'filePath': filePath,
        if (workspacePath != null) 'workspacePath': workspacePath,
      });

  Future<Map<String, dynamic>> getContext() => call('get_context');

  Future<Map<String, dynamic>> submitApproval({
    required String cascadeId,
    required String callId,
    required bool allow,
    String trajectoryId = '',
    int stepIndex = -1,
    String approvalType = 'approval',
    String command = '',
    ApprovalScope scope = ApprovalScope.once,
  }) =>
      call('submit_approval', {
        'cascadeId': cascadeId,
        'callId': callId,
        'trajectoryId': trajectoryId,
        'stepIndex': stepIndex,
        'approvalType': approvalType,
        'command': command,
        'scope': scope == ApprovalScope.session ? 'session' : 'once',
        'decision': allow ? 'allow' : 'deny',
      });

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
    final data = (msg['data'] as Map<String, dynamic>?) ?? const {};
    final error = msg['error'] as String?;

    if (type == 'stream_start' ||
        type == 'stream_delta' ||
        type == 'stream_end') {
      final controller = _streams[requestId];
      if (controller == null) {
        // Stream déclenché par une AUTRE surface (PC ou autre téléphone) :
        // le broadcast daemon le relaie ici sans requestId local. On le
        // réémet sur _events (marqué) pour que l'UI suive la session.
        _emitBatched({...msg, 'broadcast': true});
        return;
      }
      if (type == 'stream_end') {
        // Livre le message stream_end (outcome structuré) au listener local
        // AVANT de fermer : onDone ne transporte pas de données.
        _outbox?.remove(requestId);
        controller.add(msg);
        controller.close();
        _streams.remove(requestId);
      } else {
        controller.add(msg);
      }
      _emitBatched(msg);
      return;
    }

    _emitBatched(msg);
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
    _emitBatched(msg);
    if (type == 'error' || error != null) {
      completer.completeError(Exception(error ?? 'Unknown daemon error'));
    } else {
      completer.complete(data);
    }
  }
}
