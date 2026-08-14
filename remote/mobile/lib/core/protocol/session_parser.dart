import 'dart:convert';
import 'dart:typed_data';

import 'messages.dart';

/// Parses the daemon's `list_sessions` response into [CascadeSession] items.
///
/// The gateway (remote/daemon/pkg/gateway/websocket.go) now returns structured
/// sessions: `{"sessions":[{cascadeId,title,workspace,status,updatedAt}]}`
/// (parsed server-side by connectrpc.ParseTrajectories).
///
/// Fallback: legacy daemons that still send the raw protobuf field dump
/// (`{"fields":[...]}`) are parsed heuristically (UUID + readable title).
class SessionParser {
  static List<CascadeSession> parseListSessions(Map<String, dynamic> data) {
    final sessions = data['sessions'];
    if (sessions is List) {
      var out = <CascadeSession>[];
      for (final s in sessions) {
        if (s is Map<String, dynamic>) {
          final id = s['cascadeId'] ?? s['id'];
          // Filtrer les entrées sans clé primaire ou non disponibles (archivées, killed, supprimées)
          if (id is String && id.isNotEmpty) {
            final session = CascadeSession.fromJson(s);
            if (session.isAvailable) {
              out.add(session);
            }
          }
        }
      }
      if (out.isNotEmpty) {
        // Tri par date de mise à jour décroissante.
        final byId = <String, DateTime>{};
        for (final s in sessions) {
          if (s is Map && s['cascadeId'] is String) {
            byId[s['cascadeId'] as String] =
                DateTime.tryParse(s['updatedAt'] as String? ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0);
          }
        }
        out.sort((a, b) =>
            (byId[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(byId[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0)));
        return out;
      }
    }
    return _parseLegacyFieldDump(data);
  }

  // ── Fallback : ancien daemon (dump de champs protobuf bruts) ──────────────

  static final RegExp _uuidRe = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  static List<CascadeSession> _parseLegacyFieldDump(Map<String, dynamic> data) {
    final fields = data['fields'];
    if (fields is! List) return const [];

    final sessions = <CascadeSession>[];
    for (final f in fields) {
      if (f is! Map<String, dynamic>) continue;
      if (f['field'] != 1) continue; // trajectory entries live in field 1

      final blob = _blobOf(f);
      final text = f['text'] is String ? f['text'] as String : '';
      final combined = '$text ${_asAscii(blob)}';
      final id = _uuidRe.firstMatch(combined)?.group(0) ?? '';
      final title = _legacyTitleOf(f, text, blob);
      if (id.isEmpty) continue;

      final session = CascadeSession(
        id: id,
        workspacePath: _workspaceOf(combined),
        title: title,
        status: 'CASCADE_STATUS_READY',
        time: 'Just now',
      );
      if (session.isAvailable) {
        sessions.add(session);
      }
    }
    return sessions;
  }

  static Uint8List _blobOf(Map<String, dynamic> field) {
    final b = field['bytes'];
    if (b is int) {
      // Gateway sends `bytes: <length>` — the payload itself is unavailable
      // in the field dump; fall back to the text snippet when present.
      return Uint8List(0);
    }
    if (b is List) {
      return Uint8List.fromList(b.whereType<int>().toList());
    }
    return Uint8List(0);
  }

  static String _asAscii(Uint8List blob) {
    return latin1.decode(blob, allowInvalid: true);
  }

  static String _legacyTitleOf(
    Map<String, dynamic> field,
    String text,
    Uint8List blob,
  ) {
    final cleaned = text
        .trim()
        .replaceFirst(RegExp(r'^\{[\s\S]*\}\s*'), '');
    if (cleaned.isNotEmpty && cleaned.length > 4) {
      return cleaned.split('\n').first;
    }
    // Fallback: readable runs of printable chars inside the blob.
    final ascii = _asAscii(blob);
    final matches = RegExp(r'[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 ._\-:]{4,60}')
        .allMatches(ascii)
        .toList();
    if (matches.isNotEmpty) {
      final candidate =
          matches.map((m) => m.group(0)!).where((s) => s.length > 6).toList();
      if (candidate.isNotEmpty) return candidate.last;
    }
    return 'Cascade Session';
  }

  static String _workspaceOf(String ascii) {
    final m = RegExp(r'file:///[^\x00-\x1f]+').firstMatch(ascii);
    return m?.group(0) ?? '';
  }
}
