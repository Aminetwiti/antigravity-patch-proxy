/// Minimal Markdown renderer for the chat timeline.
///
/// ponytail: We don't need a full CommonMark implementation for streaming
/// agent output — inline styling (bold, italic, code, inline code, links)
/// plus fenced code blocks and lists covers ~99% of what Antigravity
/// renders in the console. Rich text is built on plain [TextSpan]s, so the
/// whole timeline stays a lightweight `ListView` (no webview, no plugin).
///
/// Ceiling: nested emphasis (e.g. `**bold _italic_**`) and tables are not
/// supported; upgrade path is `flutter_markdown` if a real need appears.
library;

import 'package:flutter/material.dart';

class CodeBlock {
  final String language;
  final String code;
  const CodeBlock(this.language, this.code);
}

class MarkdownBlock {
  final String? paragraph; // null when this block is a code block
  final CodeBlock? code;
  final bool isListItem;

  const MarkdownBlock.paragraph(this.paragraph, {this.isListItem = false})
      : code = null;
  const MarkdownBlock.codeBlock(this.code) : paragraph = null, isListItem = false;
}

class MarkdownRenderer {
  /// Splits raw markdown text into display blocks.
  static List<MarkdownBlock> blocksOf(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final blocks = <MarkdownBlock>[];
    final buffer = <String>[];
    var inFence = false;
    var fenceLang = '';

    void flushParagraph() {
      if (buffer.isEmpty) return;
      final raw = buffer.join('\n').trim();
      buffer.clear();
      if (raw.isEmpty) return;
      for (final line in raw.split('\n')) {
        if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
          blocks.add(MarkdownBlock.paragraph(
            line.replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''),
            isListItem: true,
          ));
        } else if (RegExp(r'^\s*\d+[.)]\s+').hasMatch(line)) {
          blocks.add(MarkdownBlock.paragraph(
            line.replaceFirst(RegExp(r'^\s*\d+[.)]\s+'), ''),
            isListItem: true,
          ));
        } else {
          blocks.add(MarkdownBlock.paragraph(line));
        }
      }
    }

    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (inFence) {
          blocks.add(MarkdownBlock.codeBlock(CodeBlock(fenceLang, buffer.join('\n'))));
          buffer.clear();
          inFence = false;
        } else {
          flushParagraph();
          inFence = true;
          fenceLang = line.trimLeft().substring(3).trim();
        }
        continue;
      }
      if (inFence) {
        buffer.add(line);
      } else {
        buffer.add(line);
      }
    }

    if (inFence) {
      blocks.add(MarkdownBlock.codeBlock(CodeBlock(fenceLang, buffer.join('\n'))));
      buffer.clear();
    }
    flushParagraph();
    return blocks;
  }

  /// Builds inline [TextSpan]s for a paragraph, resolving bold/italic/code.
  static List<InlineSpan> inlineSpans(
    String text,
    TextStyle base,
  ) {
    final spans = <InlineSpan>[];
    final codeRe = RegExp(r'`([^`]+)`');
    final boldRe = RegExp(r'\*\*([^*]+)\*\*');
    // CommonMark flanking: opening * must be followed by non-space, closing *
    // must be preceded by non-space (so `a * b * c` stays literal).
    final italicRe = RegExp(r'\*(?=\S)([^*\n]+?)(?<=\S)\*(?!\*)');
    final linkRe = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');

    var remaining = text;
    while (remaining.isNotEmpty) {
      // 1. Inline code — highest priority, its content must not be restyled.
      final codeMatch = codeRe.firstMatch(remaining);
      if (codeMatch != null && codeMatch.start == 0) {
        spans.add(TextSpan(
          text: codeMatch.group(1),
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: base.fontSize! * 0.92,
            color: const Color(0xFFEAB308),
            backgroundColor: const Color(0xFF27272A),
          ),
        ));
        remaining = remaining.substring(codeMatch.end);
        continue;
      }

      // 2. Link.
      final linkMatch = linkRe.firstMatch(remaining);
      if (linkMatch != null && linkMatch.start == 0) {
        spans.add(TextSpan(
          text: linkMatch.group(1),
          style: base.copyWith(color: const Color(0xFF3B82F6)),
          recognizer: null,
        ));
        remaining = remaining.substring(linkMatch.end);
        continue;
      }

      // 3. Bold.
      final boldMatch = boldRe.firstMatch(remaining);
      if (boldMatch != null && boldMatch.start == 0) {
        spans.add(TextSpan(
          text: boldMatch.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
        remaining = remaining.substring(boldMatch.end);
        continue;
      }

      // 4. Italic.
      final italicMatch = italicRe.firstMatch(remaining);
      if (italicMatch != null && italicMatch.start == 0) {
        spans.add(TextSpan(
          text: italicMatch.group(1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
        remaining = remaining.substring(italicMatch.end);
        continue;
      }

      // 5. Plain text up to the next markdown token.
      final nextIndex = <int>[
        for (final r in [codeRe, linkRe, boldRe, italicRe])
          r.firstMatch(remaining)?.start ?? remaining.length,
      ].reduce((a, b) => a < b ? a : b);
      if (nextIndex == 0) {
        // Defensive: a token matched but not at position 0 (shouldn't happen).
        spans.add(TextSpan(text: remaining[0]));
        remaining = remaining.substring(1);
        continue;
      }
      spans.add(TextSpan(text: remaining.substring(0, nextIndex)));
      remaining = remaining.substring(nextIndex);
    }
    return spans;
  }
}
