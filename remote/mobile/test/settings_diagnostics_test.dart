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
// Tests du câblage fonctionnel de SettingsScreen :
//   1. « Télécharger les diagnostics » → GET /health/diagnostic.
//   2. « Enregistrer la configuration » → SettingsStore persisté + callback.
//   3. Toggle notifications → ApprovalNotifier.setEnabled synchronisé.
//   4. Modèle par défaut → persisté + /model envoyé au daemon.
//
// La ListView de Settings est très longue : le viewport de test est agrandi
// (800×6000) pour que toutes les sections soient construites et tapables.
// ──────────────────────────────────────────────────────────────────────────────

Future<void> _pumpScreen(
  WidgetTester tester, {
  http.Client? httpClient,
  DaemonApi? api,
  ApprovalNotifier? notifier,
  ValueChanged<Map<String, dynamic>>? onDaemonSaved,
  Map<String, dynamic> initialSettings = const {},
}) async {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

    await _pumpScreen(tester, httpClient: client);

    await tester.tap(find.text('Télécharger les diagnostics'));
    await tester.pumpAndSettle();

    expect(requested, isTrue,
        reason: 'le tap doit déclencher un appel au daemon');
    // En test headless, path_provider/share_plus ne sont pas disponibles :
    // l'écran avale l'erreur (SnackBar « Export impossible ») — le point
    // vérifié ici est la requête HTTP, pas le partage natif.
  });

  testWidgets('daemon: enregistrer persiste via SettingsStore + callback',
      (tester) async {
    Map<String, dynamic>? saved;
    await _pumpScreen(
      tester,
      initialSettings: {
        'host': '192.168.1.50',
        'port': 8090,
        'ssl': false,
      },
      onDaemonSaved: (c) => saved = c,
    );

    await tester.tap(find.text('Enregistrer la configuration'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['host'], '192.168.1.50');
    expect(saved!['port'], 8090);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.daemonHost'), '192.168.1.50');
    expect(prefs.getInt('settings.daemonPort'), 8090);
  });

  testWidgets('notifications: le toggle synchronise ApprovalNotifier',
      (tester) async {
    final notifier = ApprovalNotifier.instance;
    notifier.setEnabled(true);
    await _pumpScreen(tester, notifier: notifier);

    await tester.tap(find.text('Notifications Push (Tool Approvals)'));
    await tester.pumpAndSettle();

    expect(notifier.isEnabled, isFalse,
        reason: 'le toggle doit désactiver le notifier singleton');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.toolNotifications'), isFalse);
  });

  testWidgets('modèle par défaut: persisté et /model envoyé au daemon',
      (tester) async {
    final out = <Map<String, dynamic>>[];
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) => out.add(d as Map<String, dynamic>),
    );
    addTearDown(ctrl.close);

    await _pumpScreen(tester, api: api);

    // Le dropdown du modèle est identifiable par sa valeur initiale
    // (« Gemini 3.6 Flash Medium ») — les deux autres dropdowns ont des
    // valeurs différentes (tier GE, région d'inférence).
    final modelDropdown = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField<String> && w.value == 'Gemini 3.6 Flash Medium',
    );
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-4o').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.defaultModel'), 'GPT-4o');
    expect(
      out.map((m) => m['type']).contains('send_command'),
      isTrue,
      reason: 'le choix du modèle doit être appliqué au daemon via /model',
    );
  });
}
