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

import 'dart:convert';
import 'dart:io';

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
  final int headerLevel;
  final bool isDivider;
  final bool isQuote;

  const MarkdownBlock.paragraph(
    this.paragraph, {
    this.isListItem = false,
    this.headerLevel = 0,
    this.isDivider = false,
    this.isQuote = false,
  })  : code = null,
        toolCall = null;

  const MarkdownBlock.codeBlock(this.code)
      : paragraph = null,
        toolCall = null,
        isListItem = false,
        headerLevel = 0,
        isDivider = false,
        isQuote = false;

  const MarkdownBlock.toolCall(this.toolCall)
      : paragraph = null,
        code = null,
        isListItem = false,
        headerLevel = 0,
        isDivider = false,
        isQuote = false;
}

/// Callback invoked when a markdown link pointing to a local file
/// (file:/// URI) is tapped. Absent → the link renders as a plain tooltip
/// (existing behavior for callers without a daemon handle).
typedef LocalFileTap = void Function(String filePath);

class MarkdownRenderer {
  static final Map<String, List<MarkdownBlock>> _blocksCache = {};
  static const int _maxCacheEntries = 100;
  static final _toolArgRe = RegExp(r'"(command|query|file|path|TargetFile|AbsolutePath)"\s*:\s*"([^"]+)"');
  static final _whitespaceRe = RegExp(r'\s+');

  // Pre-compiled regular expressions for high-performance timeline streaming
  static final _toolCallRe = RegExp(
    r'<function_call>|<function_results>|"tool(_name)?"\s*:|(\{|\[)\s*"name"\s*:\s*"[a-zA-Z_]+"\s*,\s*"arguments"',
  );
  static final _headingRe = RegExp(r'^(#{1,4})\s+(.+)$');
  static final _dividerRe = RegExp(r'^(---|___|\*\*\*)\s*$');
  static final _quoteRe = RegExp(r'^>\s*(.+)$');
  static final _bulletListRe = RegExp(r'^\s*[-*+]\s+');
  static final _numberedListRe = RegExp(r'^\s*\d+[.)]\s+');
  static final _toolNameRe = RegExp(r'"(name|tool|tool_name)"\s*:\s*"([^"]+)"');
  static final _systemTagsRe = RegExp(
    r'<SYSTEM_MESSAGE>[\s\S]*?</SYSTEM_MESSAGE>|<SYSTEM_PROMPT>[\s\S]*?</SYSTEM_PROMPT>|<ADDITIONAL_METADATA>[\s\S]*?</ADDITIONAL_METADATA>|<USER_SETTINGS_CHANGE>[\s\S]*?</USER_SETTINGS_CHANGE>|<system_generated>[\s\S]*?</system_generated>|<context[\s\S]*?</context>|The following is a <SYSTEM_MESSAGE> not actually sent by the user[\s\S]*?(?:pay attention to\.|$)|\<identity\>[\s\S]*?\</identity\>|\<user_information\>[\s\S]*?\</user_information\>|\<skills\>[\s\S]*?\</skills\>|\<subagents\>[\s\S]*?\</subagents\>|\<messaging\>[\s\S]*?\</messaging\>|\<artifacts\>[\s\S]*?\</artifacts\>|\<slash_commands\>[\s\S]*?\</slash_commands\>|\<planning_mode\>[\s\S]*?\</planning_mode\>|\<guidelines\>[\s\S]*?\</guidelines\>|\<communication_style\>[\s\S]*?\</communication_style\>|\<conversation_transcript\>[\s\S]*?\</conversation_transcript\>',
    caseSensitive: false,
  );
  static final _bgTaskMsgRe = RegExp(
    r'\[Message\]\s*timestamp=[^\n]+\n+sender=[^\n]+\n+priority=[^\n]+\n+content=[^\n]+',
    caseSensitive: false,
  );

  /// Nettoie les balises internes et les messages systèmes résiduels
  static String cleanContent(String text) {
    if (text.isEmpty) return text;
    var cleaned = text.replaceAll(_systemTagsRe, '').trim();
    cleaned = cleaned.replaceAll(_bgTaskMsgRe, '').trim();
    return cleaned;
  }

  /// Splits raw markdown text into display blocks.
  static List<MarkdownBlock> blocksOf(String text) {
    final cached = _blocksCache[text];
    if (cached != null) return cached;

    final cleanText = cleanContent(text);
    if (cleanText.isEmpty) return const [];

    final lines = cleanText.replaceAll('\r\n', '\n').split('\n');
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
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final headMatch = _headingRe.firstMatch(trimmed);
        if (headMatch != null) {
          final level = headMatch.group(1)!.length;
          final content = headMatch.group(2)!.trim();
          blocks.add(MarkdownBlock.paragraph(content, headerLevel: level));
          continue;
        }

        if (_dividerRe.hasMatch(trimmed)) {
          blocks.add(const MarkdownBlock.paragraph('', isDivider: true));
          continue;
        }

        final quoteMatch = _quoteRe.firstMatch(trimmed);
        if (quoteMatch != null) {
          blocks.add(MarkdownBlock.paragraph(quoteMatch.group(1)!.trim(), isQuote: true));
          continue;
        }

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
        } else if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
          // Table row: convert pipe separators to formatted columns
          final cells = trimmed.split('|').where((c) => c.trim().isNotEmpty).map((c) => c.trim()).join('  │  ');
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

    if (_blocksCache.length >= _maxCacheEntries) {
      _blocksCache.remove(_blocksCache.keys.first);
    }
    _blocksCache[text] = List<MarkdownBlock>.unmodifiable(blocks);
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
    final imageRe = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)');
    final linkRe = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');
    final boldRe = RegExp(r'\*\*([^*]+)\*\*');
    // CommonMark flanking: opening * must be followed by non-space, closing *
    // must be preceded by non-space (so `a * b * c` stays literal).
    final italicRe = RegExp(r'\*(?=\S)([^*\n]+?)(?<=\S)\*(?!\*)');

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

      // 2. Markdown Image ![alt](url)
      final imageMatch = imageRe.firstMatch(remaining);
      if (imageMatch != null && imageMatch.start == 0) {
        final alt = imageMatch.group(1) ?? '';
        final url = imageMatch.group(2) ?? '';
        final isLocalFile = url.startsWith('file://');
        final isDataUri = url.startsWith('data:image/');
        final filePath = isLocalFile ? _filePathOf(url) : '';

        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildImageWidget(
              url: url,
              alt: alt,
              filePath: filePath,
              isLocalFile: isLocalFile,
              isDataUri: isDataUri,
              scheme: scheme,
              onLocalFile: onLocalFile,
            ),
          ),
        ));
        remaining = remaining.substring(imageMatch.end);
        continue;
      }

      // 3. Link with tooltip showing full target path/URL on hover.
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

      // 4. Bold.
      final boldMatch = boldRe.firstMatch(remaining);
      if (boldMatch != null && boldMatch.start == 0) {
        spans.add(TextSpan(
          text: boldMatch.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
        remaining = remaining.substring(boldMatch.end);
        continue;
      }

      // 5. Italic.
      final italicMatch = italicRe.firstMatch(remaining);
      if (italicMatch != null && italicMatch.start == 0) {
        spans.add(TextSpan(
          text: italicMatch.group(1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
        remaining = remaining.substring(italicMatch.end);
        continue;
      }

      // 6. Plain text up to the next markdown token.
      final nextIndex = <int>[
        for (final r in [codeRe, imageRe, linkRe, boldRe, italicRe])
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

  /// Construit un aperçu soigné pour une image markdown (locale, data URI ou distante).
  static Widget _buildImageWidget({
    required String url,
    required String alt,
    required String filePath,
    required bool isLocalFile,
    required bool isDataUri,
    required ColorScheme scheme,
    LocalFileTap? onLocalFile,
  }) {
    if (isDataUri) {
      try {
        final commaIdx = url.indexOf(',');
        if (commaIdx != -1) {
          final b64 = url.substring(commaIdx + 1);
          final bytes = base64Decode(b64);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _imageErrorTile(alt.isNotEmpty ? alt : 'Image', scheme),
            ),
          );
        }
      } catch (_) {}
    }

    if (isLocalFile && filePath.isNotEmpty) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _imageErrorTile(alt.isNotEmpty ? alt : filePath, scheme),
            ),
          );
        }
      } catch (_) {}

      // Image sur l'hôte distant (PC)
      return InkWell(
        onTap: onLocalFile == null ? null : () => onLocalFile(filePath),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      alt.isNotEmpty ? alt : filePath.split(RegExp(r'[\\/]')).last,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Image enregistrée sur l\'hôte',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.open_in_new, size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _imageErrorTile(alt.isNotEmpty ? alt : url, scheme),
        ),
      );
    }

    return _imageErrorTile(alt.isNotEmpty ? alt : url, scheme);
  }

  static Widget _imageErrorTile(String label, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
