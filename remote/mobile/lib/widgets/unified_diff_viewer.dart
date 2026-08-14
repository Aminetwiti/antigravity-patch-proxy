import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Unifié et interactif : affiche un diff de code et permet d'annoter
/// des lignes spécifiques pour envoyer une revue de code groupée à l'agent.
/// Inspiré du Code Review de AG2R.
class UnifiedDiffViewer extends StatefulWidget {
  final String diffContent;
  final String? fileName;
  final VoidCallback? onClose;
  final Function(String reviewComments)? onSendReview;

  const UnifiedDiffViewer({
    super.key,
    required this.diffContent,
    this.fileName,
    this.onClose,
    this.onSendReview,
  });

  @override
  State<UnifiedDiffViewer> createState() => _UnifiedDiffViewerState();
}

class _UnifiedDiffViewerState extends State<UnifiedDiffViewer> {
  int _additions = 0;
  int _deletions = 0;
  List<_DiffLine> _lines = [];
  final Map<int, String> _annotations = {}; // lineIndex -> comment

  @override
  void initState() {
    super.initState();
    _parseDiff();
  }

  @override
  void didUpdateWidget(UnifiedDiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diffContent != widget.diffContent) {
      _parseDiff();
    }
  }

  void _parseDiff() {
    int adds = 0;
    int dels = 0;
    final List<_DiffLine> parsed = [];

    int oldLineNum = 0;
    int newLineNum = 0;

    final rawLines = widget.diffContent.split('\n');
    for (final raw in rawLines) {
      if (raw.startsWith('@@')) {
        parsed.add(_DiffLine(
          type: _DiffLineType.hunkHeader,
          content: raw,
        ));
        final match = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(raw);
        if (match != null) {
          oldLineNum = int.tryParse(match.group(1) ?? '1') ?? 1;
          newLineNum = int.tryParse(match.group(2) ?? '1') ?? 1;
        }
      } else if (raw.startsWith('+') && !raw.startsWith('+++')) {
        adds++;
        parsed.add(_DiffLine(
          type: _DiffLineType.addition,
          content: raw.substring(1),
          newLine: newLineNum++,
        ));
      } else if (raw.startsWith('-') && !raw.startsWith('---')) {
        dels++;
        parsed.add(_DiffLine(
          type: _DiffLineType.deletion,
          content: raw.substring(1),
          oldLine: oldLineNum++,
        ));
      } else if (raw.startsWith('---') || raw.startsWith('+++') || raw.startsWith('diff --git')) {
        parsed.add(_DiffLine(
          type: _DiffLineType.meta,
          content: raw,
        ));
      } else {
        parsed.add(_DiffLine(
          type: _DiffLineType.context,
          content: raw.startsWith(' ') ? raw.substring(1) : raw,
          oldLine: oldLineNum > 0 ? oldLineNum++ : null,
          newLine: newLineNum > 0 ? newLineNum++ : null,
        ));
      }
    }

    setState(() {
      _additions = adds;
      _deletions = dels;
      _lines = parsed;
    });
  }

  void _copyDiff() {
    Clipboard.setData(ClipboardData(text: widget.diffContent));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diff copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _addAnnotation(int lineIndex) {
    final line = _lines[lineIndex];
    final ctrl = TextEditingController(text: _annotations[lineIndex] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Annoter la ligne ${line.newLine ?? line.oldLine ?? (lineIndex + 1)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                line.content.trim(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Remarque pour l\'agent (ex: ajouter une vérification d\'erreur)...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          if (_annotations.containsKey(lineIndex))
            TextButton(
              onPressed: () {
                setState(() => _annotations.remove(lineIndex));
                Navigator.of(ctx).pop();
              },
              child: const Text('Supprimer', style: TextStyle(color: AppColors.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                setState(() => _annotations[lineIndex] = text);
              } else {
                setState(() => _annotations.remove(lineIndex));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _sendReviewQueue() {
    if (_annotations.isEmpty || widget.onSendReview == null) return;

    final buffer = StringBuffer();
    buffer.writeln('Code Review Feedback for `${widget.fileName ?? "files"}`:');
    _annotations.forEach((lineIdx, comment) {
      final line = _lines[lineIdx];
      final lineNum = line.newLine ?? line.oldLine ?? (lineIdx + 1);
      buffer.writeln('- Line $lineNum (`${line.content.trim()}`): $comment');
    });

    widget.onSendReview!(buffer.toString());
    HapticFeedback.mediumImpact();
    setState(() => _annotations.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(Icons.difference_outlined, size: 16, color: AppColors.inkSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.fileName ?? 'Code Changes',
                    style: const TextStyle(
                      color: AppColors.inkPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.positive.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+$_additions',
                    style: const TextStyle(
                      color: AppColors.positive,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '-$_deletions',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.inkMuted),
                  onPressed: _copyDiff,
                  tooltip: 'Copy Diff',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.inkMuted),
                    onPressed: widget.onClose,
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ),

          // Diff content list
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 700,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    final line = _lines[index];
                    final hasComment = _annotations.containsKey(index);
                    return InkWell(
                      onTap: () => _addAnnotation(index),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLineRow(line, hasComment),
                          if (hasComment)
                            Container(
                              margin: const EdgeInsets.only(left: 80, right: 16, bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.accentBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.comment_outlined, size: 14, color: AppColors.accentBlue),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _annotations[index]!,
                                      style: const TextStyle(
                                        color: AppColors.accentBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Bottom Review Queue bar
          if (_annotations.isNotEmpty && widget.onSendReview != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                border: const Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.rate_review_outlined, size: 16, color: AppColors.accentBlue),
                  const SizedBox(width: 8),
                  Text(
                    '${_annotations.length} note(s) de revue',
                    style: const TextStyle(
                      color: AppColors.inkPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Envoyer à l\'Agent', style: TextStyle(fontSize: 12)),
                    onPressed: _sendReviewQueue,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLineRow(_DiffLine line, bool hasComment) {
    Color bg = Colors.transparent;
    Color textColor = AppColors.inkPrimary;
    String prefix = ' ';

    switch (line.type) {
      case _DiffLineType.addition:
        bg = AppColors.positive.withValues(alpha: 0.12);
        textColor = const Color(0xFF4ADE80);
        prefix = '+';
        break;
      case _DiffLineType.deletion:
        bg = AppColors.danger.withValues(alpha: 0.12);
        textColor = const Color(0xFFF87171);
        prefix = '-';
        break;
      case _DiffLineType.hunkHeader:
        bg = AppColors.accentBlue.withValues(alpha: 0.08);
        textColor = AppColors.accentBlue;
        prefix = ' ';
        break;
      case _DiffLineType.meta:
        textColor = AppColors.inkMuted;
        prefix = ' ';
        break;
      case _DiffLineType.context:
        textColor = AppColors.inkSecondary;
        prefix = ' ';
        break;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              line.oldLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            child: Text(
              line.newLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            prefix,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              line.content,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ),
          if (hasComment)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.comment, size: 14, color: AppColors.accentBlue),
            ),
        ],
      ),
    );
  }
}

enum _DiffLineType { hunkHeader, addition, deletion, context, meta }

class _DiffLine {
  final _DiffLineType type;
  final String content;
  final int? oldLine;
  final int? newLine;

  _DiffLine({
    required this.type,
    required this.content,
    this.oldLine,
    this.newLine,
  });
}
