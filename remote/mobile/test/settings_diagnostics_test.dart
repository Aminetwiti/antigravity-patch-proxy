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
    // L'export échoue en test headless (path_provider/share_plus absents) :
    // la SnackBar d'erreur s'affiche puis se retire. pumpAndSettle bloquerait
    // sur l'animation d'entrée sous fake time — on pompe borné.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));

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
      send: (d) => out.add(d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map)),
      timeout: const Duration(seconds: 1), // rÃ©sout vite : aucun daemon dans le test
    );
    addTearDown(ctrl.close);
    // Un RPC sans rÃ©ponse laisse un Timer de timeout tourner : le rÃ©soudre
    // immÃ©diatement Ã©vite l'Ã©chec « A Timer is still pending » en fin de test.
    addTearDown(api.dispose);

    await _pumpScreen(tester, api: api);

    // Le dropdown du modèle est identifiable par sa valeur initiale
    // (« Gemini 3.6 Flash Medium ») — les deux autres dropdowns ont des
    // valeurs différentes (tier GE, région d'inférence).
    await tester.tap(find.text('Gemini 3.7 Flash Medium').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('GPT-4o').last);
    // Le choix envoie /model au daemon ; sans daemon, le RPC expire au bout
    // de 1 s (timeout court configuré) — on pompe au-delà pour ne laisser
    // aucun Timer fake en attente en fin de test.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.defaultModel'), 'GPT-4o');
    expect(
      out.map((m) => m['type']).contains('send_command'),
      isTrue,
      reason: 'le choix du modèle doit être appliqué au daemon via /model',
    );
  });

  testWidgets('approval timeout: persisté et set_approval_timeout envoyé au daemon',
      (tester) async {
    final out = <Map<String, dynamic>>[];
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) => out.add(d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map)),
      timeout: const Duration(seconds: 1),
    );
    addTearDown(ctrl.close);
    addTearDown(api.dispose);

    await _pumpScreen(tester, api: api);

    // initState pousse le réglage par défaut (5 min) au daemon.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      out.any((m) =>
          m['type'] == 'set_approval_timeout' &&
          (m['data'] as Map<String, dynamic>)['minutes'] == 5),
      isTrue,
      reason: 'le délai persisté doit être appliqué au daemon à l\'ouverture',
    );

    final timeoutField = find.byKey(const Key('settings-approval-timeout-field'));
    await tester.ensureVisible(timeoutField);
    await tester.pumpAndSettle();
    await tester.enterText(timeoutField, '12');

    final timeoutButton = find.byTooltip('Appliquer le délai au daemon');
    await tester.ensureVisible(timeoutButton);
    await tester.pumpAndSettle();
    await tester.tap(timeoutButton);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('settings.approvalTimeoutMinutes'), 12);
    expect(
      out.any((m) =>
          m['type'] == 'set_approval_timeout' &&
          (m['data'] as Map<String, dynamic>)['minutes'] == 12),
      isTrue,
      reason: 'le nouveau délai doit être poussé au daemon',
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('profil: modification du nom met à jour l\'avatar et persiste',
      (tester) async {
    await _pumpScreen(tester);

    final nameField = find.widgetWithText(TextField, 'Amine Developer');
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Sami Developer');
    await tester.pumpAndSettle();

    expect(find.text('S'), findsOneWidget,
        reason: 'l\'initiale de l\'avatar doit devenir S');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.displayName'), 'Sami Developer');
  });

  testWidgets('apparence: compactBubbles et monospaceCode persistent dans SettingsStore',
      (tester) async {
    await _pumpScreen(tester);

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

  testWidgets('enterprise & administration: toggles et politiques persistent',
      (tester) async {
    await _pumpScreen(tester);

    final mcpSwitch = find.text('Liste d\'autorisation MCP stricte');
    await tester.ensureVisible(mcpSwitch);
    await tester.tap(mcpSwitch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.mcpAllowlistStrict'), isFalse);
  });

  testWidgets('git worktree: sélection d\'une branche envoie /checkout au daemon et persiste',
      (tester) async {
    final out = <Map<String, dynamic>>[];
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) {
        final map = d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
        out.add(map);
        final reqId = map['requestId'] ?? map['id'];
        if (map['type'] == 'list_git_branches') {
          ctrl.add(jsonEncode({
            'type': 'response',
            'requestId': reqId,
            'data': {
              'branches': ['main', 'feature/remote-v2'],
            }
          }));
        }
        if (map['type'] == 'send_command') {
          ctrl.add(jsonEncode({
            'type': 'response',
            'requestId': reqId,
            'data': {'status': 'ok'},
          }));
        }
      },
      timeout: const Duration(seconds: 1),
    );
    addTearDown(ctrl.close);
    addTearDown(api.dispose);

    await _pumpScreen(tester, api: api);

    final branchTile = find.text('feature/remote-v2');
    await tester.ensureVisible(branchTile);
    await tester.tap(branchTile);
    await tester.pump(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.activeBranch'), 'feature/remote-v2');
    expect(
      out.any((m) =>
          m['type'] == 'send_command' &&
          ((m['data'] as Map?)?['command'] == '/checkout feature/remote-v2' ||
              m['command'] == '/checkout feature/remote-v2')),
      isTrue,
      reason: '/checkout doit être envoyé au daemon lors du changement de branche',
    );
  });

  testWidgets('projet: suppression demande confirmation et envoie /clear au daemon',
      (tester) async {
    final out = <Map<String, dynamic>>[];
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) => out.add(d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map)),
      timeout: const Duration(seconds: 1),
    );
    addTearDown(ctrl.close);
    addTearDown(api.dispose);

    await _pumpScreen(tester, api: api);

    final deleteButton = find.text('Supprimer le projet');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Supprimer définitivement le projet ?'), findsOneWidget);

    await tester.tap(find.text('Supprimer définitivement'));
    await tester.pump(const Duration(seconds: 2));

    expect(
      out.any((m) =>
          m['type'] == 'send_command' &&
          ((m['data'] as Map?)?['command'] == '/clear' || m['command'] == '/clear')),
      isTrue,
      reason: '/clear doit être envoyé au daemon lors de la réinitialisation du projet',
    );
  });
}

