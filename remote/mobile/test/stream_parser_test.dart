import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/stream_parser.dart';

void main() {
  group('StreamDeltaParser command extraction', () {
    ToolApproval makeApproval(String detail) {
      return ToolApproval(
        callId: 'test',
        tool: 'run_command',
        detail: detail,
        cascadeId: 'test',
      );
    }

    test('extracts command_line correctly with normal casing', () {
      final detail = '{"command_line": "npm run build", "cwd": "/app"}';
      expect(makeApproval(detail).command, 'npm run build');
    });

    test('extracts commandline correctly without underscore', () {
      final detail = '{"commandline": "flutter test", "cwd": "/app"}';
      expect(makeApproval(detail).command, 'flutter test');
    });

    test('extracts command_line correctly with mixed casing (caseSensitive: false check)', () {
      final detail = '{"CommandLine": "dart run", "cwd": "/app"}';
      expect(makeApproval(detail).command, 'dart run');
    });

    test('returns empty if no command is found and no fallback line exists', () {
      final detail = '{}';
      expect(makeApproval(detail).command, '');
    });
  });
}
