import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat_stream/widgets/session_review_view.dart';
import 'package:mobile/widgets/markdown_bubble.dart';

void main() {
  group('P5 — SessionReviewView bulk actions', () {
    const files = [
      SessionModifiedFile(path: 'lib/a.dart', additions: 2, deletions: 0),
      SessionModifiedFile(path: 'lib/b.dart', additions: 0, deletions: 1),
    ];

    testWidgets('bar hidden when callbacks are null', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SessionReviewView(
            files: files,
            onOpenFileDiff: (_) {},
          ),
        ),
      ));
      expect(find.text('Tout accepter'), findsNothing);
      expect(find.text('Tout rejeter'), findsNothing);
    });

    testWidgets('tap Tout accepter fires onAcceptAll', (tester) async {
      var accepted = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SessionReviewView(
            files: files,
            onOpenFileDiff: (_) {},
            onAcceptAll: () => accepted++,
          ),
        ),
      ));
      expect(find.text('Tout accepter'), findsOneWidget);
      await tester.tap(find.text('Tout accepter'));
      expect(accepted, 1);
    });

    testWidgets('tap Tout rejeter fires onDiscardAll', (tester) async {
      var discarded = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SessionReviewView(
            files: files,
            onOpenFileDiff: (_) {},
            onDiscardAll: () => discarded++,
          ),
        ),
      ));
      expect(find.text('Tout rejeter'), findsOneWidget);
      await tester.tap(find.text('Tout rejeter'));
      expect(discarded, 1);
    });
  });

  group('P3 — MarkdownBubble Run chip', () {
    testWidgets('bash block renders without daemon (no crash)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownBubble(
            text: '```bash\nls -la\n```',
            api: null, // not connected → Run chip hidden
          ),
        ),
      ));
      expect(find.textContaining('ls -la', findRichText: true), findsOneWidget);
    });
  });
}
