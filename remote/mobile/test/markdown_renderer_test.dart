import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:mobile/core/protocol/markdown_renderer.dart';

void main() {
  group('MarkdownRenderer.blocksOf', () {
    test('splits fenced code blocks from paragraphs', () {
      final blocks = MarkdownRenderer.blocksOf(
        'Before\n```dart\nvoid main() {}\n```\nAfter',
      );
      expect(blocks.length, 3);
      expect(blocks[0].paragraph, 'Before');
      expect(blocks[1].code!.language, 'dart');
      expect(blocks[1].code!.code, 'void main() {}');
      expect(blocks[2].paragraph, 'After');
    });

    test('marks bullet and numbered list items', () {
      final blocks = MarkdownRenderer.blocksOf('- item one\n2. item two');
      expect(blocks.length, 2);
      expect(blocks[0].isListItem, isTrue);
      expect(blocks[0].paragraph, 'item one');
      expect(blocks[1].isListItem, isTrue);
      expect(blocks[1].paragraph, 'item two');
    });

    test('unterminated fence still yields a code block', () {
      final blocks = MarkdownRenderer.blocksOf('```python\nprint(1)');
      expect(blocks.length, 1);
      expect(blocks[0].code!.language, 'python');
      expect(blocks[0].code!.code, 'print(1)');
    });
  });

  group('MarkdownRenderer.inlineSpans', () {
    test('resolves bold, italic and inline code', () {
      const base = TextStyle(fontSize: 14, color: Color(0xFFF4F4F5));
      final spans = MarkdownRenderer.inlineSpans(
        '**bold** and *italic* and `code` and plain',
        base,
      );
      final texts = spans.map((s) => (s as TextSpan).text).join();
      expect(texts, 'bold and italic and code and plain');

      final bold = spans[0] as TextSpan;
      expect(bold.style?.fontWeight, FontWeight.w700);
      final italic = spans[2] as TextSpan;
      expect(italic.style?.fontStyle, FontStyle.italic);
      final code = spans[4] as TextSpan;
      expect(code.style?.fontFamily, 'monospace');
    });

    test('ignores lone asterisks (no emphasis)', () {
      const base = TextStyle(fontSize: 14);
      final spans = MarkdownRenderer.inlineSpans('a * b * c', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'a * b * c');
    });
  });
}
