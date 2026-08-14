import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/markdown_renderer.dart';
import '../theme/app_colors.dart';
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
    final base = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final spans = MarkdownRenderer.inlineSpans(block.paragraph ?? '', base);

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
              decoration: const BoxDecoration(
                color: AppColors.inkMuted,
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

class _CodeBlockView extends StatelessWidget {
  final CodeBlock code;

  const _CodeBlockView({required this.code});

  bool get _isDiff {
    final lang = code.language.toLowerCase();
    return lang == 'diff' || lang == 'patch';
  }

  @override
  Widget build(BuildContext context) {
    final isDiff = _isDiff;
    final lines = code.code.split('\n');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: language badge + review trigger + copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: AppColors.surfaceRaised,
            child: Row(
              children: [
                Icon(
                  isDiff ? Icons.difference_outlined : Icons.code,
                  size: 13,
                  color: isDiff ? AppColors.accentBlue : AppColors.inkMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  code.language.isEmpty ? 'code' : code.language,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: isDiff ? FontWeight.w600 : FontWeight.normal,
                    color: isDiff ? AppColors.accentBlue : AppColors.inkSecondary,
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
                            diffContent: code.code,
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
                        children: const [
                          Icon(Icons.rate_review_outlined, size: 13, color: AppColors.accentBlue),
                          SizedBox(width: 4),
                          Text('Review', style: TextStyle(fontSize: 11, color: AppColors.accentBlue, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: code.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copié dans le presse-papiers'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy_outlined, size: 14, color: AppColors.inkMuted),
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
                  for (final line in lines)
                    _DiffLineRow(line: line),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(
                code.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.inkPrimary,
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
    Color? bgColor;
    Color textColor = AppColors.inkPrimary;
    FontWeight fontWeight = FontWeight.normal;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      bgColor = AppColors.positive.withValues(alpha: 0.15);
      textColor = AppColors.positive;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bgColor = AppColors.danger.withValues(alpha: 0.15);
      textColor = AppColors.danger;
    } else if (line.startsWith('@@')) {
      bgColor = AppColors.accentBlue.withValues(alpha: 0.12);
      textColor = AppColors.accentBlue;
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

class _ToolCallPill extends StatelessWidget {
  final ToolCallBlock call;

  const _ToolCallPill({required this.call});

  bool get _isSubagent {
    final t = call.toolName.toLowerCase();
    return t.contains('subagent') || t == 'manage_task';
  }

  bool get _isBrowser {
    final t = call.toolName.toLowerCase();
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
    final t = call.toolName.toLowerCase();
    if (t.contains('command') || t.contains('run')) return 'COMMAND';
    if (t.contains('file')) return 'FILE';
    return 'TOOL';
  }

  Color get _badgeColor {
    if (_isSubagent) return AppColors.accentBlue;
    if (_isBrowser) return const Color(0xFF00B4D8);
    final t = call.toolName.toLowerCase();
    if (t.contains('command') || t.contains('run')) return const Color(0xFFE07A5F);
    if (t.contains('file')) return const Color(0xFF81B29A);
    return AppColors.inkMuted;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = _badgeColor;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isSubagent
            ? AppColors.accentBlue.withValues(alpha: 0.1)
            : _isBrowser
                ? const Color(0xFF00B4D8).withValues(alpha: 0.08)
                : scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isSubagent
              ? AppColors.accentBlue.withValues(alpha: 0.3)
              : _isBrowser
                  ? const Color(0xFF00B4D8).withValues(alpha: 0.25)
                  : scheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(_iconFor(call.toolName), size: 15, color: badgeColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              call.summary.isEmpty ? call.toolName : '${call.toolName} — ${call.summary}',
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
