import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/outbox.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/core/protocol/stream_parser.dart';

void main() {
  group('DaemonApi', () {
    test('correlates unary response by requestId', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) => outgoing.add(data as Map<String, dynamic>),
      );

      final future = api.listSessions();
      await Future<void>.delayed(Duration.zero);
      expect(outgoing, hasLength(1));
      expect(outgoing.first['type'], 'list_sessions');
      final requestId = outgoing.first['requestId'] as String;

      controller.add(jsonEncode({
        'type': 'response',
        'requestId': requestId,
        'data': {'fields': [{'field': 1, 'text': 'cascade-1'}]},
      }));

      final result = await future;
      expect((result['fields'] as List), hasLength(1));
      await controller.close();
      api.dispose();
    });

    test('streams deltas and closes on stream_end', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) => outgoing.add(data as Map<String, dynamic>),
      );

      final stream = api.sendPrompt('c1', 'hello');
      await Future<void>.delayed(Duration.zero);
      final requestId = outgoing.first['requestId'] as String;
      expect(outgoing.first['prompt'], 'hello');

      final deltas = <String>[];
      final done = Completer<void>();
      stream.listen(
        (msg) {
          final t = StreamDeltaParser.textOf(msg);
          if (t.isNotEmpty) deltas.add(t);
        },
        onDone: done.complete,
      );

      controller.add(jsonEncode({
        'type': 'stream_delta',
        'requestId': requestId,
        'data': {
          'events': [
            {'kind': 'thinking', 'delta': 'thinking...'},
            {'kind': 'text', 'delta': 'Hel'},
            {'kind': 'text', 'delta': 'lo'},
          ],
        },
      }));
      controller.add(jsonEncode({
        'type': 'stream_end',
        'requestId': requestId,
      }));

      await done.future;
      expect(deltas, ['Hello']);
      await controller.close();
      api.dispose();
    });

    test('surfaces approval_required events', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) => outgoing.add(data as Map<String, dynamic>),
      );

      final stream = api.sendPrompt('c1', 'run tests');
      await Future<void>.delayed(Duration.zero);
      final requestId = outgoing.first['requestId'] as String;

      ToolApproval? approval;
      final done = Completer<void>();
      stream.listen(
        (msg) {
          final a = StreamDeltaParser.approvalOf(msg);
          if (a != null) approval = a;
        },
        onDone: done.complete,
      );

      controller.add(jsonEncode({
        'type': 'stream_delta',
        'requestId': requestId,
        'data': {
          'events': [
            {
              'kind': 'approval_required',
              'callId': 'call_1',
              'tool': 'run_command',
              'detail': '{"command_line":"git status"}',
              'cascadeId': 'c1',
              'trajectoryId': 'traj_9',
              'stepIndex': 4,
            },
          ],
        },
      }));
      controller.add(jsonEncode({
        'type': 'stream_end',
        'requestId': requestId,
      }));

      await done.future;
      expect(approval, isNotNull);
      expect(approval!.tool, 'run_command');
      expect(approval!.detail, '{"command_line":"git status"}');
      expect(approval!.trajectoryId, 'traj_9');
      expect(approval!.stepIndex, 4);
      expect(approval!.approvalType, 'run_command');
      expect(approval!.command, 'git status');
      await controller.close();
      api.dispose();
    });

    test('timeouts when daemon never responds', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) => outgoing.add(data as Map<String, dynamic>),
        timeout: const Duration(milliseconds: 200),
      );

      await expectLater(
        api.heartbeat(),
        throwsA(isA<TimeoutException>()),
      );
      await controller.close();
      api.dispose();
    });

    test('re-emits broadcast streams from other surfaces on events', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) => outgoing.add(data as Map<String, dynamic>),
      );

      final broadcastEvents = <Map<String, dynamic>>[];
      final sub = api.events.listen(broadcastEvents.add);

      // Un stream déclenché par le PC (requestId inconnu localement) :
      // le daemon le broadcast, l'API doit le réémettre sur _events.
      controller.add(jsonEncode({
        'type': 'stream_delta',
        'requestId': 'r-external',
        'data': {
          'events': [
            {'kind': 'text', 'delta': 'Réponse depuis le PC'},
          ],
        },
      }));
      controller.add(jsonEncode({
        'type': 'stream_end',
        'requestId': 'r-external',
      }));

      await Future<void>.delayed(Duration.zero);
      expect(broadcastEvents, hasLength(2));
      expect(broadcastEvents.first['broadcast'], isTrue);
      expect(broadcastEvents.first['type'], 'stream_delta');
      expect(StreamDeltaParser.textOf(broadcastEvents.first), 'Réponse depuis le PC');
      expect(broadcastEvents.last['type'], 'stream_end');

      await sub.cancel();
      await controller.close();
      api.dispose();
    });

    test('outbox: sendPrompt offline is replayed on reconnect (Étape 5)', () async {
      final outgoing = <Map<String, dynamic>>[];
      final controller = StreamController<dynamic>();
      final outbox = OutboxQueue();
      // Simule le gate réseau du vrai client : hors-ligne, _send est un no-op.
      var online = false;
      final api = DaemonApi(
        incoming: controller.stream,
        send: (data) {
          if (online) outgoing.add(data as Map<String, dynamic>);
        },
        outbox: outbox,
      );
      final version = ValueNotifier<int>(0);

      var resyncCount = 0;
      api.attachReconnect(version, () async {
        resyncCount++;
        return const {'ok': true};
      });

      // Hors-ligne : le prompt est mis en file, rien n'est envoyé au daemon
      // (le send est un no-op tant que le socket est coupé).
      api.sendPrompt('c1', 'important prompt');
      expect(outbox.pendingCount, 1);
      expect(outgoing, isEmpty);

      // Reconnexion : version++ → replay de la queue puis re-sync.
      online = true;
      version.value = 1;
      await Future<void>.delayed(Duration.zero);
      expect(outgoing, hasLength(1));
      expect(outgoing.first['type'], 'send_prompt');
      expect(outgoing.first['prompt'], 'important prompt');
      expect(outgoing.first.containsKey('queuedAt'), isFalse);

      // La réponse arrive → le message est drainé de la queue (stream_end).
      final requestId = outgoing.first['requestId'] as String;
      controller.add(jsonEncode({
        'type': 'stream_start',
        'requestId': requestId,
        'data': {'cascadeId': 'c1'},
      }));
      controller.add(jsonEncode({
        'type': 'stream_end',
        'requestId': requestId,
        'data': {'cascadeId': 'c1', 'outcome': 'done'},
      }));
      await Future<void>.delayed(Duration.zero);
      expect(outbox.pendingCount, 0);

      // Nouvelle reconnexion : la queue est vide → le replayer ne tourne pas
      // (pas de re-sync). Seul le flush de la reconnexion v1 a resyncé.
      version.value = 2;
      await Future<void>.delayed(Duration.zero);
      expect(resyncCount, 1);

      await controller.close();
      api.dispose();
    });
  });
}
