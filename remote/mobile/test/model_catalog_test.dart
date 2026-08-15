import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/core/protocol/model_catalog.dart';
import 'package:mobile/widgets/chat_input_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ModelCatalog Unit Tests', () {
    test('Standard models include Antigravity 2.0 native catalog', () {
      final models = ModelCatalog.standardModels;
      expect(models.any((m) => m.displayName.contains('Gemini 3.7 Flash')), isTrue);
      expect(models.any((m) => m.displayName.contains('Gemini 3.6 Flash')), isTrue);
      expect(models.any((m) => m.displayName.contains('Gemini 3.5 Flash')), isTrue);
      expect(models.any((m) => m.displayName.contains('Gemini 3.1 Pro')), isTrue);
      expect(models.any((m) => m.displayName.contains('Claude Sonnet 4.6')), isTrue);
      expect(models.any((m) => m.displayName.contains('Claude Opus 4.6')), isTrue);
      expect(models.any((m) => m.displayName.contains('GPT-OSS 120B')), isTrue);
    });

    test('fetchCustomModels parses enabled custom providers and models', () async {
      final ctrl = StreamController<dynamic>();
      final out = <Map<String, dynamic>>[];
      final api = DaemonApi(
        incoming: ctrl.stream,
        send: (d) {
          final msg = d as Map<String, dynamic>;
          out.add(msg);
          if (msg['type'] == 'read_file') {
            final jsonConfig = jsonEncode({
              'providers': [
                {
                  'id': 'p1',
                  'name': 'opencode',
                  'enabled': true,
                  'status': 'online',
                  'latencyMs': 441,
                  'models': [
                    {
                      'id': 'deepseek-v4-flash',
                      'displayName': 'deepseek-v4-flash',
                      'enabled': true,
                    },
                    {
                      'id': 'disabled-model',
                      'displayName': 'disabled-model',
                      'enabled': false,
                    }
                  ],
                },
                {
                  'id': 'p2',
                  'name': 'disabled-provider',
                  'enabled': false,
                  'models': [
                    {'id': 'qwen', 'displayName': 'qwen', 'enabled': true}
                  ],
                }
              ]
            });
            ctrl.add(jsonEncode({
              'type': 'response',
              'requestId': msg['requestId'],
              'data': {'content': jsonConfig},
            }));
          }
        },
        timeout: const Duration(seconds: 1),
      );
      addTearDown(ctrl.close);
      addTearDown(api.dispose);

      final custom = await ModelCatalog.fetchCustomModels(api);
      expect(custom.length, 1);
      expect(custom.first.id, 'deepseek-v4-flash');
      expect(custom.first.latencyMs, 441);
      expect(custom.first.customLabel, '441ms • deepseek-v4-flash');
      expect(custom.first.isCustom, isTrue);
    });
  });

  group('ChatInputBar Model Dropdown & Sync Tests', () {
    testWidgets('ChatInputBar displays Antigravity 2.0 dropdown and selects model', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final out = <Map<String, dynamic>>[];
      final ctrl = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: ctrl.stream,
        send: (d) {
          final msg = d as Map<String, dynamic>;
          out.add(msg);
          // Respond immediately so no timers remain pending
          ctrl.add(jsonEncode({
            'type': 'response',
            'requestId': msg['requestId'],
            'data': msg['type'] == 'read_file' ? {'content': ''} : {'ok': true},
          }));
        },
        timeout: const Duration(seconds: 1),
      );
      addTearDown(ctrl.close);
      addTearDown(api.dispose);

      String? selectedModelFromCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              onSend: (_, {queued = false, modelUID, modelEnum}) {},
              isConnected: true,
              api: api,
              onModelChanged: (m) => selectedModelFromCallback = m,
            ),
          ),
        ),
      );

      // Verify default model display
      expect(find.textContaining('Gemini 3.7 Flash'), findsOneWidget);

      // Tap model button to open dropdown
      await tester.tap(find.textContaining('Gemini 3.7 Flash'));
      await tester.pumpAndSettle();

      // Dropdown should show Antigravity 2.0 models & View Usage
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Gemini 3.7 Flash Medium'), findsOneWidget);
      expect(find.text('Claude Sonnet 4.6 (Thinking)'), findsOneWidget);
      expect(find.text('View Usage'), findsOneWidget);

      // Select Claude Sonnet 4.6
      await tester.tap(find.text('Claude Sonnet 4.6 (Thinking)'));
      await tester.pumpAndSettle();

      expect(selectedModelFromCallback, 'Claude Sonnet 4.6 (Thinking)');
      expect(find.textContaining('Claude Sonnet 4.6'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings.defaultModel'), 'Claude Sonnet 4.6 (Thinking)');

      // Verify /model command was dispatched
      expect(
        out.any((m) => m['type'] == 'send_command' && m['command'].toString().contains('/model')),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('View Usage opens Quota Limits modal without overflow on small screens', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              onSend: (_, {queued = false, modelUID, modelEnum}) {},
              isConnected: true,
            ),
          ),
        ),
      );

      // Tap model button
      await tester.tap(find.textContaining('Gemini 3.7 Flash'));
      await tester.pumpAndSettle();

      // Tap View Usage
      await tester.tap(find.text('View Usage'));
      await tester.pumpAndSettle();

      // Verify Quota stats present and no overflow exception occurred
      expect(tester.takeException(), isNull);
      expect(find.text('Gemini Models'), findsOneWidget);
      expect(find.text('Claude and GPT models'), findsOneWidget);
    });

    testWidgets('ChatInputBar forwards selected modelUID and modelEnum on send', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? sentMessage;
      String? sentModelUID;
      int? sentModelEnum;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              onSend: (msg, {queued = false, modelUID, modelEnum}) {
                sentMessage = msg;
                sentModelUID = modelUID;
                sentModelEnum = modelEnum;
              },
              isConnected: true,
            ),
          ),
        ),
      );

      // Select Claude Opus 4.6 (Thinking)
      await tester.tap(find.textContaining('Gemini 3.7 Flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude Opus 4.6 (Thinking)'));
      await tester.pumpAndSettle();

      // Enter message and send
      await tester.enterText(find.byType(TextField), 'Test model prompt');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump();

      expect(sentMessage, 'Test model prompt');
      expect(sentModelUID, 'claude-opus-4.6-thinking');
      expect(sentModelEnum, 291);
    });

    test('DaemonApi.sendPrompt includes modelUID and modelEnum in JSON message', () async {
      final out = <Map<String, dynamic>>[];
      final ctrl = StreamController<dynamic>();
      final api = DaemonApi(
        incoming: ctrl.stream,
        send: (d) => out.add(d as Map<String, dynamic>),
      );
      addTearDown(ctrl.close);
      addTearDown(api.dispose);

      api.sendPrompt(
        'c-test',
        'Hello model',
        modelUID: 'deepseek-v4-flash',
        modelEnum: 342,
      );

      expect(out.length, 1);
      final sent = out.first;
      expect(sent['type'], 'send_prompt');
      expect(sent['cascadeId'], 'c-test');
      expect(sent['prompt'], 'Hello model');
      expect(sent['modelUID'], 'deepseek-v4-flash');
      expect(sent['modelEnum'], 342);
    });
  });
}
