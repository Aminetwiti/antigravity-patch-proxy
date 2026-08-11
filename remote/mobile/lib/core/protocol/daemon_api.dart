import 'dart:async';
import 'dart:convert';

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

  int _nextRequestId = 0;

  /// Broadcast of every decoded daemon message (UI listeners, logging).
  Stream<Map<String, dynamic>> get events => _events.stream;

  DaemonApi({
    required Stream<dynamic> incoming,
    required void Function(dynamic) send,
    Duration timeout = const Duration(seconds: 5),
  })  : _incoming = incoming,
        _send = send,
        _timeout = timeout {
    _incoming.listen(_onMessage);
  }

  String _newRequestId() => 'r${++_nextRequestId}';

  /// Unary call resolved when a `response`/`error` with the same requestId
  /// arrives (30s timeout).
  Future<Map<String, dynamic>> call(
    String type, [
    Map<String, dynamic> params = const {},
  ]) {
    final id = _newRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'type': type, 'requestId': id, ...params});
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

  Future<Map<String, dynamic>> readFile(String filePath) =>
      call('read_file', {'filePath': filePath});

  Future<Map<String, dynamic>> getContext() => call('get_context');

  Future<Map<String, dynamic>> submitApproval({
    required String cascadeId,
    required String callId,
    required bool allow,
  }) =>
      call('submit_approval', {
        'cascadeId': cascadeId,
        'callId': callId,
        'decision': allow ? 'allow' : 'deny',
      });

  /// Streaming call: emits each decoded message (`stream_start`,
  /// `stream_delta`, ...) until `stream_end` closes the stream.
  Stream<Map<String, dynamic>> sendPrompt(String cascadeId, String prompt) {
    final id = _newRequestId();
    final controller = StreamController<Map<String, dynamic>>();
    _streams[id] = controller;
    _send({
      'type': 'send_prompt',
      'requestId': id,
      'cascadeId': cascadeId,
      'prompt': prompt,
    });
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
        _events.add({...msg, 'broadcast': true});
        return;
      }
      if (type == 'stream_end') {
        controller.close();
        _streams.remove(requestId);
      } else {
        controller.add(msg);
      }
      _events.add(msg);
      return;
    }

    _events.add(msg);

    final completer = _pending.remove(requestId);
    if (completer == null) return;
    if (type == 'error' || error != null) {
      completer.completeError(Exception(error ?? 'Unknown daemon error'));
    } else {
      completer.complete(data);
    }
  }

  void dispose() {
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
}
