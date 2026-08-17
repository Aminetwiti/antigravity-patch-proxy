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

/// Callback invoked when a markdown link pointing to a local file
/// (file:/// URI) is tapped. Absent → the link renders as a plain tooltip
/// (existing behavior for callers without a daemon handle).
typedef LocalFileTap = void Function(String filePath);

class MarkdownRenderer {
  // Pre-compiled regular expressions for high-performance timeline streaming
  static final _toolCallRe = RegExp(
    r'<function_call>|<function_results>|"tool(_name)?"\s*:|(\{|\[)\s*"name"\s*:\s*"[a-zA-Z_]+"\s*,\s*"arguments"',
  );
  static final _bulletListRe = RegExp(r'^\s*[-*+]\s+');
  static final _numberedListRe = RegExp(r'^\s*\d+[.)]\s+');
  static final _toolNameRe = RegExp(r'"(name|tool|tool_name)"\s*:\s*"([^"]+)"');
  static final _toolArgRe = RegExp(r'"(command|query|pattern|path|file_path)"\s*:\s*"([^"]+)"');
  static final _whitespaceRe = RegExp(r'\s+');

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
      // Single-line tool invocation → dedicated pill block.
      if (_toolCallRe.hasMatch(raw)) {
        final parsed = _toolCallOf(raw);
        blocks.add(MarkdownBlock.toolCall(parsed));
        return;
      }
      for (final line in raw.split('\n')) {
        if (_bulletListRe.hasMatch(line)) {
          blocks.add(MarkdownBlock.paragraph(
            line.replaceFirst(_bulletListRe, ''),
            isListItem: true,
          ));
        } else if (_numberedListRe.hasMatch(line)) {
          blocks.add(MarkdownBlock.paragraph(
            line.replaceFirst(_numberedListRe, ''),
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
    final name = _toolNameRe.firstMatch(raw)?.group(2) ?? 'tool';
    // Compact one-line summary: first quoted argument value, else first line.
    final summary = _toolArgRe.firstMatch(raw)?.group(2) ??
        raw.replaceAll(_whitespaceRe, ' ').substring(0, raw.length > 80 ? 80 : raw.length);
    return ToolCallBlock(name, summary, raw);
  }

  /// Builds inline [TextSpan]s for a paragraph, resolving bold/italic/code.
  /// [onLocalFile] (P5) est appelé quand l'utilisateur tape un lien markdown
  /// vers un fichier local (file:///...) — le caller ouvre le fichier (ex.
  /// ArtifactViewerModal). Sans callback, le lien reste un simple tooltip.
  static List<InlineSpan> inlineSpans(
    String text,
    TextStyle base, {
    required ColorScheme scheme,
    LocalFileTap? onLocalFile,
  }) {
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
            color: scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ));
        remaining = remaining.substring(codeMatch.end);
        continue;
      }

      // 2. Link with tooltip showing full target path/URL on hover.
      // P5 : un lien file:/// devient tappable (ouvre le fichier côté hôte)
      // quand onLocalFile est fourni ; sinon comportement historique.
      final linkMatch = linkRe.firstMatch(remaining);
      if (linkMatch != null && linkMatch.start == 0) {
        final label = linkMatch.group(1) ?? '';
        final url = linkMatch.group(2) ?? '';
        final isLocalFile = url.startsWith('file://');
        if (isLocalFile) {
          final filePath = _filePathOf(url);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Tooltip(
              waitDuration: const Duration(milliseconds: 100),
              message: 'Ouvrir : $filePath',
              child: GestureDetector(
                onTap: onLocalFile == null ? null : () => onLocalFile(filePath),
                child: Text(
                  label,
                  style: base.copyWith(
                    color: scheme.primary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ));
        } else {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Tooltip(
              waitDuration: const Duration(milliseconds: 100),
              message: 'Chemin complet : $url',
              child: Text(
                label,
                style: base.copyWith(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ));
        }
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

  /// Normalise une URI file:/// en chemin hôte (décode %XX, gère les
  /// variantes file:// et file:///). Best-effort : une URI mal encodée est
  /// renvoyée telle quelle plutôt que de faire planter le rendu.
  static String _filePathOf(String url) {
    var p = url;
    if (p.startsWith('file:///')) {
      p = p.substring(8);
    } else if (p.startsWith('file://')) {
      p = p.substring(7);
    }
    try {
      p = Uri.decodeComponent(p);
    } catch (_) {}
    return p;
  }
}
