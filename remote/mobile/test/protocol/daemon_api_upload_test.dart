import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/core/protocol/messages.dart';

void main() {
  test('DaemonApi.uploadMedia sends binary attachment payload', () async {
    ClientMessage? sentMsg;
    final api = DaemonApi(sendRaw: (msg) => sentMsg = msg);

    api.uploadMedia(
      cascadeId: 's3',
      fileName: 'screenshot.png',
      mimeType: 'image/png',
      base64Data: 'iVBORw0KGgoAAAANSUhEUgAA...',
    );

    expect(sentMsg, isNotNull);
    expect(sentMsg!.type, equals('upload_media'));
    expect(sentMsg!.data?['fileName'], equals('screenshot.png'));
  });
}
