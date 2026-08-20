import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/markdown_renderer.dart';
import 'package:mobile/widgets/markdown_bubble.dart';

void main() {
  test('MarkdownRenderer inlineSpans extracts markdown images', () {
    const text = 'Here is a chart: ![Architecture Diagram](file:///C:/Users/test/scratch/upload_123.png)';
    final spans = MarkdownRenderer.inlineSpans(
      text,
      const TextStyle(fontSize: 14),
      scheme: const ColorScheme.dark(),
    );

    expect(spans.length, greaterThanOrEqualTo(2));
    final widgetSpans = spans.whereType<WidgetSpan>().toList();
    expect(widgetSpans.isNotEmpty, isTrue);
  });

  testWidgets('MarkdownBubble renders markdown image widget', (tester) async {
    String? openedFile;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBubble(
            text: '![Screenshot](file:///C:/Users/test/scratch/upload_123.png)',
            onLocalFile: (path) => openedFile = path,
          ),
        ),
      ),
    );

    expect(find.text('Screenshot'), findsOneWidget);
    expect(find.text("Image enregistrée sur l'hôte"), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    // Tap to open on host
    await tester.tap(find.text('Screenshot'));
    await tester.pump();

    expect(openedFile, contains('upload_123.png'));
  });
}
