import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsStore session', () {
    test('round-trip save/load sans session', () async {
      SharedPreferences.setMockInitialValues({});
      final before = await SettingsStore.loadSession();
      expect(before, isEmpty);

      await SettingsStore.saveSession(
        wsUrl: 'wss://abc.trycloudflare.com/ws',
        token: 'tok-123',
        sessionId: 'sess-1',
      );
      final after = await SettingsStore.loadSession();
      expect(after['wsUrl'], 'wss://abc.trycloudflare.com/ws');
      expect(after['token'], 'tok-123');
      expect(after['sessionId'], 'sess-1');
      expect(after['savedAt'], isA<DateTime>());
    });

    test('session expirée (> 24 h) → vide', () async {
      SharedPreferences.setMockInitialValues({
        'session.lastWsUrl': 'wss://old.trycloudflare.com/ws',
        'session.lastWsToken': 'tok-old',
        'session.lastSessionId': 'sess-old',
        'session.savedAt':
            DateTime.now().subtract(const Duration(hours: 25)).toIso8601String(),
      });
      final s = await SettingsStore.loadSession();
      expect(s, isEmpty);
    });

    test('clearSession efface tout', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsStore.saveSession(
        wsUrl: 'wss://x/ws',
        token: 't',
        sessionId: 's',
      );
      await SettingsStore.clearSession();
      final s = await SettingsStore.loadSession();
      expect(s, isEmpty);
    });
  });
}
