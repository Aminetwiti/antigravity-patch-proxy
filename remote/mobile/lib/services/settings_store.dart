import 'package:shared_preferences/shared_preferences.dart';

/// Persistance des réglages utilisateur via `shared_preferences`.
/// Écriture atomique par clé, lecture paresseuse au démarrage (initState).
/// ponytail: stockage clé/valeur simple — pas de schéma versionné; ajouter
/// un `settingsVersion` si le nombre de clés grandit.
class SettingsStore {
  static const _kHost = 'settings.daemonHost';
  static const _kPort = 'settings.daemonPort';
  static const _kSsl = 'settings.useSsl';
  static const _kCsrf = 'settings.csrfToken';
  static const _kThemeMode = 'settings.themeMode';
  static const _kDefaultModel = 'settings.defaultModel';
  static const _kDisplayName = 'settings.displayName';
  static const _kRole = 'settings.role';
  static const _kStatus = 'settings.status';

  SettingsStore._();

  /// Charge l'état initial (valeurs par défaut si jamais persistées).
  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString(_kHost) ?? '127.0.0.1',
      'port': prefs.getInt(_kPort) ?? 8090,
      'ssl': prefs.getBool(_kSsl) ?? false,
      'csrf': prefs.getString(_kCsrf) ?? '',
      'themeMode': prefs.getInt(_kThemeMode) ?? 0,
      'defaultModel': prefs.getString(_kDefaultModel) ?? 'Gemini 3.6 Flash Medium',
      'displayName': prefs.getString(_kDisplayName) ?? 'Amine Developer',
      'role': prefs.getString(_kRole) ?? 'Remote Host Controller',
      'status': prefs.getString(_kStatus) ?? 'Online',
    };
  }

  /// Persiste une carte de réglages (les clés absentes ne sont pas touchées).
  static Future<void> save(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      switch (entry.key) {
        case 'host':
          await prefs.setString(_kHost, entry.value as String);
        case 'port':
          await prefs.setInt(_kPort, entry.value as int);
        case 'ssl':
          await prefs.setBool(_kSsl, entry.value as bool);
        case 'csrf':
          await prefs.setString(_kCsrf, entry.value as String);
        case 'themeMode':
          await prefs.setInt(_kThemeMode, entry.value as int);
        case 'defaultModel':
          await prefs.setString(_kDefaultModel, entry.value as String);
        case 'displayName':
          await prefs.setString(_kDisplayName, entry.value as String);
        case 'role':
          await prefs.setString(_kRole, entry.value as String);
        case 'status':
          await prefs.setString(_kStatus, entry.value as String);
      }
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
