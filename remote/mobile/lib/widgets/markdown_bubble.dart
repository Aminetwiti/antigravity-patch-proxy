import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/markdown_renderer.dart';
import 'unified_diff_viewer.dart';

/// Renders an assistant message with Markdown: fenced code blocks get a
/// console-style dark surface with a copy button; paragraphs get inline
/// bold/italic/code/link styling. Streaming text re-renders cheaply.
class MarkdownBubble extends StatelessWidget {
  final String text;
  final bool isStreaming;

  const MarkdownBubble({
    super.key,
    required this.text,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = MarkdownRenderer.blocksOf(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          if (block.code != null)
            _CodeBlockView(code: block.code!)
          else if (block.toolCall != null)
            _ToolCallPill(call: block.toolCall!)
          else
            _ParagraphView(block: block),
          const SizedBox(height: 10),
        ],
        if (isStreaming) const _StreamingCursor(),
      ],
    );
  }
}

class _ParagraphView extends StatelessWidget {
  final MarkdownBlock block;

  const _ParagraphView({required this.block});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: scheme.onSurface,
    );
    final spans = MarkdownRenderer.inlineSpans(block.paragraph ?? '', base, scheme: scheme);

    if (block.isListItem) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Text.rich(TextSpan(children: spans))),
        ],
      );
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _CodeBlockView extends StatefulWidget {
  final CodeBlock code;

  const _CodeBlockView({required this.code});

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _expanded = false;

  bool get _isDiff {
    final lang = widget.code.language.toLowerCase();
    return lang == 'diff' || lang == 'patch';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDiff = _isDiff;
    final lines = widget.code.code.split('\n');
    final isLong = lines.length > 15;
    final displayLines = (isLong && !_expanded) ? lines.take(12).toList() : lines;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: language badge + review trigger + copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: scheme.surfaceContainer,
            child: Row(
              children: [
                Icon(
                  isDiff ? Icons.difference_outlined : Icons.code,
                  size: 13,
                  color: isDiff ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.code.language.isEmpty ? 'code' : widget.code.language,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: isDiff ? FontWeight.w600 : FontWeight.normal,
                    color: isDiff ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${lines.length} lines)',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (isDiff) ...[
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => FractionallySizedBox(
                          heightFactor: 0.9,
                          child: UnifiedDiffViewer(
                            diffContent: widget.code.code,
                            fileName: 'Code Diff',
                            onClose: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.rate_review_outlined, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text('Review', style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: widget.code.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copié dans le presse-papiers'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy_outlined, size: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          // Code body with line-by-line diff formatting if diff
          if (isDiff)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in displayLines)
                    _DiffLineRow(line: line),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(
                (isLong && !_expanded) ? displayLines.join('\n') : widget.code.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
          if (isLong)
            InkWell(
              onTap: () {
                setState(() => _expanded = !_expanded);
                HapticFeedback.selectionClick();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer.withValues(alpha: 0.5),
                  border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 14,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? 'Réduire le code' : 'Afficher tout (+${lines.length - 12} lignes)',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final String line;

  const _DiffLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? bgColor;
    Color textColor = scheme.onSurface;
    FontWeight fontWeight = FontWeight.normal;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      bgColor = const Color(0x339BB955);
      textColor = const Color(0xFF4ADE80);
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bgColor = const Color(0x33FF0000);
      textColor = const Color(0xFFF87171);
    } else if (line.startsWith('@@')) {
      bgColor = scheme.primary.withValues(alpha: 0.12);
      textColor = scheme.primary;
      fontWeight = FontWeight.w600;
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: Text(
        line.isEmpty ? ' ' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          color: textColor,
          fontWeight: fontWeight,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ToolCallPill extends StatefulWidget {
  final ToolCallBlock call;

  const _ToolCallPill({required this.call});

  @override
  State<_ToolCallPill> createState() => _ToolCallPillState();
}

class _ToolCallPillState extends State<_ToolCallPill> {
  bool _expanded = false;

  bool get _isSubagent {
    final t = widget.call.toolName.toLowerCase();
    return t.contains('subagent') || t == 'manage_task';
  }

  bool get _isBrowser {
    final t = widget.call.toolName.toLowerCase();
    return t.contains('browser') || t.contains('read_url');
  }

  IconData _iconFor(String tool) {
    final t = tool.toLowerCase();
    if (t.contains('subagent')) return Icons.smart_toy_outlined;
    if (t.contains('browser')) return Icons.travel_explore_outlined;
    if (t.contains('bash') || t.contains('command') || t.contains('run')) {
      return Icons.terminal;
    } else if (t.contains('file') || t.contains('read') || t.contains('write')) {
      return Icons.folder_outlined;
    } else if (t.contains('search') || t.contains('grep')) {
      return Icons.search;
    }
    return Icons.build_outlined;
  }

  String get _badgeText {
    if (_isSubagent) return 'SUBAGENT';
    if (_isBrowser) return 'BROWSER';
    final t = widget.call.toolName.toLowerCase();
    if (t.contains('command') || t.contains('run')) return 'COMMAND';
    if (t.contains('file')) return 'FILE';
    return 'TOOL';
  }

  Color get _badgeColor {
    if (_isSubagent) return const Color(0xFF528BFF);
    if (_isBrowser) return const Color(0xFF00B4D8);
    final t = widget.call.toolName.toLowerCase();
    if (t.contains('command') || t.contains('run')) return const Color(0xFFE07A5F);
    if (t.contains('file')) return const Color(0xFF81B29A);
    return const Color(0xFFA1A1AA);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = _badgeColor;
    final hasDetails = widget.call.raw.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: _isSubagent
            ? const Color(0xFF528BFF).withValues(alpha: 0.1)
            : _isBrowser
                ? const Color(0xFF00B4D8).withValues(alpha: 0.08)
                : scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isSubagent
              ? const Color(0xFF528BFF).withValues(alpha: 0.3)
              : _isBrowser
                  ? const Color(0xFF00B4D8).withValues(alpha: 0.25)
                  : scheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasDetails
                ? () {
                    setState(() => _expanded = !_expanded);
                    HapticFeedback.selectionClick();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(_iconFor(widget.call.toolName), size: 15, color: badgeColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.call.summary.isEmpty ? widget.call.toolName : '${widget.call.toolName} — ${widget.call.summary}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: scheme.onSecondaryContainer,
                        fontWeight: _isSubagent || _isBrowser ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Text(
                      _badgeText,
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  if (hasDetails) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 14,
                      color: scheme.outline,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && hasDetails)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
              ),
              child: SelectableText(
                widget.call.raw,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accessibilité : ne pas animer si l'utilisateur a désactivé les
    // animations système (audit UX P2-8).
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: reduceMotion
          ? const _CursorBox()
          : FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1.0)
                  .animate(_controller),
              child: const _CursorBox(),
            ),
    );
  }
}

class _CursorBox extends StatelessWidget {
  const _CursorBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 14,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
