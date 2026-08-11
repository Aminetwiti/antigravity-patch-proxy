import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/session_parser.dart';

void main() {
  group('SessionParser', () {
    test('extracts sessions from gateway field dump', () {
      final data = {
        'fields': [
          {
            'field': 1,
            'wireType': 2,
            'bytes': 42,
            'text':
                '{"trajectory":{"trajectoryId":"a1b2c3d4-1111-4a1a-9b2b-000000000001"}} Poème Sur La Gravité',
          },
          {
            'field': 1,
            'wireType': 2,
            'bytes': 58,
            'text':
                '{"trajectory":{"trajectoryId":"a1b2c3d4-2222-4b2b-9c3c-000000000002"}} Doctor UI Data Issue',
          },
          {'field': 2, 'wireType': 0, 'value': 3},
        ],
      };

      final sessions = SessionParser.parseListSessions(data);

      // The gateway sends only `bytes: <len>` without the payload, so the
      // heuristic falls back to the text snippet — UUIDs + titles surface.
      expect(sessions, hasLength(2));
      expect(sessions.first.id, 'a1b2c3d4-1111-4a1a-9b2b-000000000001');
      expect(sessions.first.title, 'Poème Sur La Gravité');
    });

    test('ignores non-trajectory fields', () {
      final data = {
        'fields': [
          {'field': 2, 'wireType': 0, 'value': 3},
          {'field': 3, 'wireType': 2, 'bytes': 10},
        ],
      };
      expect(SessionParser.parseListSessions(data), isEmpty);
    });

    test('returns empty on malformed payload', () {
      expect(SessionParser.parseListSessions({'nope': true}), isEmpty);
      expect(SessionParser.parseListSessions({'fields': 'x'}), isEmpty);
    });
  });
}
