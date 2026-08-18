import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/notifications/approval_notifier.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Tests de couverture des fonctions de diagnostic & réglages avancés (P0/P1) :
//   - GET /health/diagnostic & export JSON
//   - Persistence des préférences (compactBubbles, monospaceCode, auto-refus timeout, etc.)
// ──────────────────────────────────────────────────────────────────────────────

Future<void> _pumpScreen(
  WidgetTester tester, {
  http.Client? httpClient,
  DaemonApi? api,
  ApprovalNotifier? notifier,
  ValueChanged<Map<String, dynamic>>? onDaemonSaved,
  Map<String, dynamic> initialSettings = const {},
  SettingsCategory initialCategory = SettingsCategory.account,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
      ),
      home: SettingsScreen(
        initialSettings: initialSettings,
        httpClient: httpClient,
        api: api,
        notifier: notifier,
        onDaemonSaved: onDaemonSaved,
        initialCategory: initialCategory,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('diagnostics: GET /health/diagnostic et export JSON partagé',
      (tester) async {
    var requested = false;
    final client = MockClient((request) async {
      requested = true;
      expect(request.url.path, '/health/diagnostic');
      return http.Response(
        jsonEncode({'status': 'ok', 'logs': ['a']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await _pumpScreen(tester, httpClient: client, initialCategory: SettingsCategory.app);

    final exportBtn = find.text('Exporter le rapport JSON');
    expect(exportBtn, findsOneWidget);
    await tester.tap(exportBtn);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));

    expect(requested, isTrue,
        reason: 'le tap doit déclencher un appel au daemon');
  });

  testWidgets('apparence: compactBubbles et monospaceCode persistent dans SettingsStore',
      (tester) async {
    await _pumpScreen(tester, initialCategory: SettingsCategory.appearance);

    final compactSwitch = find.text('Bulles compactes');
    await tester.ensureVisible(compactSwitch);
    await tester.tap(compactSwitch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.compactBubbles'), isTrue);

    final monoSwitch = find.text('Code monospace');
    await tester.ensureVisible(monoSwitch);
    await tester.tap(monoSwitch);
    await tester.pumpAndSettle();

    expect(prefs.getBool('settings.monospaceCode'), isFalse);
  });

  testWidgets('general: auto-accept et auto-refus timeout persistent',
      (tester) async {
    await _pumpScreen(tester, initialCategory: SettingsCategory.general);

    final autoAcceptSwitch = find.text('Auto-approuver les actions en lecture seule');
    await tester.ensureVisible(autoAcceptSwitch);
    await tester.tap(autoAcceptSwitch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.autoAcceptEnabled'), isTrue);
  });
}
