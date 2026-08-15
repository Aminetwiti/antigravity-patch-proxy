/// Centralise la conversion d'un chemin de workspace (file://, \\, /) vers un
/// nom court lisible : le dernier segment du chemin, ou le [fallback] pour les
/// chemins vides/racine.
///
/// Historique : cette logique était dupliquée dans
/// `conversation_history_screen.dart` et `sessions_list.dart` (audit
/// clean-code-guard H5) — un seul helper à maintenir désormais.
class WorkspacePath {
  static String displayName(
    String rawPath, {
    String fallback = 'Outside of Project',
  }) {
    if (rawPath.isEmpty || rawPath == '.') return fallback;
    var clean = rawPath.replaceAll('\\', '/');
    if (clean.startsWith('file:///')) clean = clean.substring(8);
    if (clean.startsWith('file://')) clean = clean.substring(7);
    final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) return segments.last;
    return fallback;
  }
}
