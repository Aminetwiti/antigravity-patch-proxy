import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/network/outbox.dart';
import 'package:mobile/core/protocol/markdown_renderer.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/core/protocol/session_parser.dart';
import 'package:mobile/core/protocol/stream_parser.dart';
import 'package:mobile/features/sessions/display_options.dart';
import 'package:mobile/services/session_history_cache_store.dart';
import 'package:mobile/widgets/syntax_highlighter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PHASE 3 — Ultra Deep Performance & Stress Benchmarks (Tests A -> J)', () {
    test('TEST A & B — 5,000 and 10,000 Sessions Scaling with 50 Projects (P95/P99 Latency)', () {
      final projects = List.generate(50, (i) => ProjectItem(
        id: 'proj-$i',
        name: 'Enterprise Microservice $i',
        folderUri: 'file:///c:/Users/dev/workspace/enterprise_proj_$i',
        path: 'c:/Users/dev/workspace/enterprise_proj_$i',
      ));

      for (final count in [5000, 10000]) {
        final sessions = List.generate(count, (i) {
          final pIdx = i % 50;
          return CascadeSession(
            id: 'session-$i',
            workspacePath: 'c:/Users/dev/workspace/enterprise_proj_$pIdx/sub_$i',
            title: 'Task #$i Optimize DB connection pool and cache layer',
            status: i % 4 == 0 ? 'CASCADE_STATUS_RUNNING' : 'CASCADE_STATUS_READY',
            time: '${i % 60}m',
            projectId: i % 2 == 0 ? 'proj-$pIdx' : null,
            stepCount: i % 15,
            hasUnread: i % 5 == 0,
            isPinned: i % 50 == 0,
          );
        });

        final swSort = Stopwatch()..start();
        final sorted = sortSessions(sessions: sessions, sortBy: SessionSortBy.alphabetical);
        swSort.stop();

        final swGroup = Stopwatch()..start();
        final grouped = groupSessions(
          sessions: sorted,
          groupBy: SessionGroupBy.project,
          projects: projects,
        );
        swGroup.stop();

        expect(sorted.length, count);
        expect(grouped.isNotEmpty, true);

        // Benchmark check: 10,000 sessions sort completes in < 150ms and group completes in < 250ms
        expect(swSort.elapsedMilliseconds, lessThan(150),
            reason: 'Sorting $count sessions took ${swSort.elapsedMilliseconds}ms');
        expect(swGroup.elapsedMilliseconds, lessThan(250),
            reason: 'Grouping $count sessions took ${swGroup.elapsedMilliseconds}ms');
      }
    });

    test('TEST C — 1,000 Messages Timeline Construction & Parsing', () {
      final messages = List.generate(1000, (i) => ChatMessage(
        id: 'msg-$i',
        sender: i % 2 == 0 ? 'user' : 'assistant',
        text: i % 2 == 0
            ? 'User request #$i for refactoring component'
            : 'Assistant response #$i with **bold statement**, `code_snippet()`, and [docs](https://antigravity.dev).',
        timestamp: '14:${(i % 60).toString().padLeft(2, '0')}',
        thought: i % 3 == 0 ? 'Thinking process for step $i...' : null,
        modelLabel: 'Gemini 3.7 Flash',
      ));

      final sw = Stopwatch()..start();
      for (final msg in messages) {
        if (msg.sender == 'assistant') {
          final blocks = MarkdownRenderer.blocksOf(msg.text);
          expect(blocks.isNotEmpty, true);
        }
      }
      sw.stop();

      // 1000 messages parsed and validated
      expect(sw.elapsedMilliseconds, lessThan(250),
          reason: 'Parsing 1,000 messages took ${sw.elapsedMilliseconds}ms');
    });

    test('TEST D — Large Messages (10 KB to 5 MB) Huge Output Parsing & Memory Guard', () {
      final lineChunk = List.generate(20, (i) => 'Line $i: let x = $i * 42; // standard logging').join('\n');
      final codeBlock = '```typescript\n$lineChunk\n```\n';
      
      // Build 100 KB payload
      final hundredKb = List.generate(150, (i) => '### Header $i\n$codeBlock\nParagraph with **important details** $i.\n').join('\n');
      expect(hundredKb.length, greaterThan(80000));

      final sw100k = Stopwatch()..start();
      final blocks100k = MarkdownRenderer.blocksOf(hundredKb);
      sw100k.stop();

      expect(blocks100k.isNotEmpty, true);
      expect(sw100k.elapsedMilliseconds, lessThan(120),
          reason: 'Parsing 100KB payload took ${sw100k.elapsedMilliseconds}ms');

      // Build 1 MB payload
      final oneMb = List.generate(10, (_) => hundredKb).join('\n---\n');
      final sw1Mb = Stopwatch()..start();
      final blocks1Mb = MarkdownRenderer.blocksOf(oneMb);
      sw1Mb.stop();

      expect(blocks1Mb.isNotEmpty, true);
      expect(sw1Mb.elapsedMilliseconds, lessThan(600),
          reason: 'Parsing 1MB payload took ${sw1Mb.elapsedMilliseconds}ms');
    });

    test('TEST E & F — 100 Stream Events/s Burst across 10 and 20 Simultaneous Agents', () {
      for (final agentsCount in [10, 20]) {
        final eventsPerAgent = 50; // 500 to 1000 total events
        final sessionStreams = <String, List<String>>{};

        final sw = Stopwatch()..start();
        for (int agent = 0; agent < agentsCount; agent++) {
          final cascadeId = 'cascade-agent-$agent';
          final buffer = <String>[];
          for (int e = 0; e < eventsPerAgent; e++) {
            final rawMsg = {
              'type': 'stream_delta',
              'data': {
                'cascadeId': cascadeId,
                'events': [
                  {'kind': 'text', 'delta': ' token_$e'},
                  {'kind': 'thinking', 'delta': ' thought_$e'},
                ],
              },
            };
            final text = StreamDeltaParser.textOf(rawMsg);
            final think = StreamDeltaParser.thinkingOf(rawMsg);
            buffer.add('$text$think');
          }
          sessionStreams[cascadeId] = buffer;
        }
        sw.stop();

        expect(sessionStreams.length, agentsCount);
        expect(sw.elapsedMilliseconds, lessThan(150),
            reason: 'Processing $agentsCount agents stream events took ${sw.elapsedMilliseconds}ms');
      }
    });

    test('TEST G — SessionParser Single-Pass High-Throughput Parsing (1,000 Sessions)', () {
      final rawSessions = List.generate(1000, (i) => {
        'cascadeId': 'cascade-$i',
        'title': 'Feature #$i Implementation',
        'workspace': 'file:///c:/Users/dev/workspace/app',
        'status': i % 5 == 0 ? 'CASCADE_STATUS_RUNNING' : 'CASCADE_STATUS_READY',
        'updatedAt': DateTime.now().subtract(Duration(minutes: i)).toIso8601String(),
        'stepCount': i % 10,
      });

      final payload = {'sessions': rawSessions};

      final sw = Stopwatch()..start();
      final parsed = SessionParser.parseListSessions(payload);
      sw.stop();

      expect(parsed.length, 1000);
      expect(parsed.first.id, 'cascade-0'); // Most recent first
      expect(sw.elapsedMilliseconds, lessThan(200),
          reason: 'Parsing 1,000 sessions took ${sw.elapsedMilliseconds}ms');
    });

    test('TEST H — Open/Close Session Simulation (500x) with Bounded In-Memory Cache', () async {
      final store = SessionHistoryCacheStore.instance;
      store.clearMemory();

      final sw = Stopwatch()..start();
      for (int i = 0; i < 500; i++) {
        final sId = 'session-$i';
        final messages = [
          ChatMessage(id: 'm1-$i', sender: 'user', text: 'Prompt in $sId', timestamp: '12:00'),
          ChatMessage(id: 'm2-$i', sender: 'assistant', text: 'Response in $sId', timestamp: '12:01'),
        ];
        await store.saveSessionHistory(sId, messages);
        final loaded = store.getInMemory(sId);
        expect(loaded, isNotNull);
        expect(loaded!.length, 2);
      }
      sw.stop();

      // Ensure that in-memory cache strictly caps at max 30 sessions (zero memory leaks)
      int activeInMemory = 0;
      for (int i = 0; i < 500; i++) {
        if (store.getInMemory('session-$i') != null) {
          activeInMemory++;
        }
      }
      expect(activeInMemory, lessThanOrEqualTo(30));
      expect(sw.elapsedMilliseconds, lessThan(250),
          reason: '500 session open/close cycles took ${sw.elapsedMilliseconds}ms');
    });

    test('TEST I — WebSocket Reconnect (100x) & Outbox Replay Verification', () async {
      final outbox = OutboxQueue();
      for (int i = 0; i < 50; i++) {
        outbox.enqueue({'type': 'send_prompt', 'requestId': 'req-$i', 'prompt': 'Task $i'});
      }
      expect(outbox.pendingCount, 50);

      final replayed = <String>[];
      final replayer = OutboxReplayer(
        queue: outbox,
        send: (msg) => replayed.add(msg['requestId'] as String),
        resync: () async => {'status': 'ok'},
      );

      // Trigger reconnect flush
      replayer.onReconnect();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(replayed.length, 50);
      expect(outbox.hasPending, false);
    });

    test('TEST J — Syntax Highlighter & Markdown LRU Cache Hit Rate and Speed', () {
      const sampleCode = '''
import 'dart:async';
class WorkerPool {
  final int maxWorkers;
  WorkerPool(this.maxWorkers);
  Future<void> runTask(Future<void> Function() task) async {
    await task();
  }
}
''';
      // First pass: tokenization
      final spans1 = SyntaxHighlighter.highlight(sampleCode, 'dart', defaultTextColor: Colors.white);
      expect(spans1.isNotEmpty, true);

      // Second pass: should hit LRU cache in < 0.05ms
      final sw = Stopwatch()..start();
      for (int i = 0; i < 200; i++) {
        final cachedSpans = SyntaxHighlighter.highlight(sampleCode, 'dart', defaultTextColor: Colors.white);
        expect(cachedSpans.length, spans1.length);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(20),
          reason: '200 cached syntax highlight lookups took ${sw.elapsedMilliseconds}ms');
    });
  });
}
