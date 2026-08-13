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

/// A raw tool invocation embedded in the agent's text stream
/// (e.g. `<function_call>{"name":"bash",...}</function_call>` or
/// `{"tool_name":"grep","arguments":{...}}`). Rendered as a pill, not text.
class ToolCallBlock {
  final String toolName;
  final String summary;
  final String raw;
  const ToolCallBlock(this.toolName, this.summary, this.raw);
}

class MarkdownBlock {
  final String? paragraph; // null when this block is a code block
  final CodeBlock? code;
  final ToolCallBlock? toolCall;
  final bool isListItem;

  const MarkdownBlock.paragraph(this.paragraph, {this.isListItem = false})
      : code = null,
        toolCall = null;
  const MarkdownBlock.codeBlock(this.code)
      : paragraph = null,
        toolCall = null,
        isListItem = false;
  const MarkdownBlock.toolCall(this.toolCall)
      : paragraph = null,
        code = null,
        isListItem = false;
}

class MarkdownRenderer {
  /// Splits raw markdown text into display blocks.
  static List<MarkdownBlock> blocksOf(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final blocks = <MarkdownBlock>[];
    final buffer = <String>[];
    var inFence = false;
    var fenceLang = '';

    // Tool-invocation markers: XML tags (function_call / function_results) or
    // JSON with a tool name + arguments — rendered as pills, not raw text.
    final toolCallRe = RegExp(
      r'<function_call>|<function_results>|"tool(_name)?"\s*:|(\{|\[)\s*"name"\s*:\s*"[a-zA-Z_]+"\s*,\s*"arguments"',
    );

    void flushParagraph() {
      if (buffer.isEmpty) return;
      final raw = buffer.join('\n').trim();
      buffer.clear();
      if (raw.isEmpty) return;
      // Single-line tool invocation → dedicated pill block.
      if (toolCallRe.hasMatch(raw)) {
        final parsed = _toolCallOf(raw);
        blocks.add(MarkdownBlock.toolCall(parsed));
        return;
      }
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
        } else if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
          // Table row: convert pipe separators to formatted columns
          final cells = line.split('|').where((c) => c.trim().isNotEmpty).map((c) => c.trim()).join('  │  ');
          blocks.add(MarkdownBlock.paragraph('│ $cells │'));
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

  /// Parses a raw tool-invocation string into a [ToolCallBlock].
  static ToolCallBlock _toolCallOf(String raw) {
    final nameRe = RegExp(r'"(name|tool|tool_name)"\s*:\s*"([^"]+)"');
    final name = nameRe.firstMatch(raw)?.group(2) ?? 'tool';
    // Compact one-line summary: first quoted argument value, else first line.
    final argRe = RegExp(r'"(command|query|pattern|path|file_path)"\s*:\s*"([^"]+)"');
    final summary = argRe.firstMatch(raw)?.group(2) ??
        raw.replaceAll(RegExp(r'\s+'), ' ').substring(0, raw.length > 80 ? 80 : raw.length);
    return ToolCallBlock(name, summary, raw);
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

      // 2. Link with tooltip showing full target path/URL on hover.
      final linkMatch = linkRe.firstMatch(remaining);
      if (linkMatch != null && linkMatch.start == 0) {
        final label = linkMatch.group(1) ?? '';
        final url = linkMatch.group(2) ?? '';
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Tooltip(
            waitDuration: const Duration(milliseconds: 100),
            message: 'Chemin complet : $url',
            child: Text(
              label,
              style: base.copyWith(
                color: const Color(0xFF3B82F6),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
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

  /// Surlignage de syntaxe pour Dart, Swift et Objective-C dans les blocs de code.
  static List<TextSpan> highlightCode(String code, String language, TextStyle baseStyle) {
    final lang = language.toLowerCase();
    final isLangSupported = lang == 'dart' || lang == 'swift' || lang == 'objc' || lang == 'objective-c';

    if (!isLangSupported) {
      return [TextSpan(text: code, style: baseStyle)];
    }

    final keywords = switch (lang) {
      'swift' => RegExp(r'\b(func|let|var|struct|class|enum|guard|if|else|import|return|self|switch)\b'),
      'objc' || 'objective-c' => RegExp(r'(@interface|@implementation|@property|@end|@synthesize|NSString|NSInteger|BOOL|id|void|return)\b'),
      _ => RegExp(r'\b(class|final|void|async|await|Widget|setState|return|import|override|const|required)\b'),
    };

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final match in keywords.allMatches(code)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: code.substring(cursor, match.start), style: baseStyle));
      }
      spans.add(TextSpan(
        text: code.substring(match.start, match.end),
        style: baseStyle.copyWith(
          color: const Color(0xFF60A5FA),
          fontWeight: FontWeight.bold,
        ),
      ));
      cursor = match.end;
    }
    if (cursor < code.length) {
      spans.add(TextSpan(text: code.substring(cursor), style: baseStyle));
    }
    return spans;
  }
}
