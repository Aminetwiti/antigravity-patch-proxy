import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/markdown_renderer.dart';
import '../theme/app_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: language badge + copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: AppColors.surfaceRaised,
            child: Row(
              children: [
                Icon(Icons.code, size: 13, color: AppColors.inkMuted),
                const SizedBox(width: 6),
                Text(
                  code.language.isEmpty ? 'code' : code.language,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.inkSecondary,
                  ),
                ),
                const Spacer(),
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
                    child: Icon(Icons.copy_outlined,
                        size: 14, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          // Code body
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

class _ToolCallPill extends StatelessWidget {
  final ToolCallBlock call;

  const _ToolCallPill({required this.call});

  IconData _iconFor(String tool) {
    final t = tool.toLowerCase();
    if (t.contains('bash') || t.contains('command') || t.contains('run')) {
      return Icons.terminal;
    } else if (t.contains('file') || t.contains('read') || t.contains('write')) {
      return Icons.folder_outlined;
    } else if (t.contains('browser') || t.contains('web') || t.contains('search') || t.contains('grep')) {
      return Icons.language;
    }
    return Icons.build_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_iconFor(call.toolName), size: 15, color: scheme.secondary),
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
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'TOOL',
              style: TextStyle(fontSize: 9, letterSpacing: 0.8, fontWeight: FontWeight.w700),
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
