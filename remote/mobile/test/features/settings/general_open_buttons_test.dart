import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/settings/general_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('File Open button calls updateProjectSettings (BUG-SET-002)', (WidgetTester tester) async {
    final ctrl = StreamController<dynamic>.broadcast();
    final sent = <Map<String, dynamic>>[];

    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) {
        final map = d as Map<String, dynamic>;
        sent.add(map);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeneralSettingsSection(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Défile jusqu'au bouton File "Open" (hors écran par défaut).
    final openBtn = find.text('Open').first;
    await tester.scrollUntilVisible(openBtn, 200);
    await tester.pumpAndSettle();
    await tester.tap(openBtn);
    await tester.pumpAndSettle();

    final update = sent.where((m) => m['type'] == 'update_project_settings');
    expect(update, isNotEmpty);
    final data = update.first['data'] as Map;
    expect(data['fileAccessPolicy'], isNotNull);

    api.dispose();
    await ctrl.close();
  });
}
