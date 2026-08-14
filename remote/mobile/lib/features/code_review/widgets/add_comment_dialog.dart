import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/code_comment.dart';

class AddCommentDialog extends StatefulWidget {
  final String filePath;
  final String selectedSnippet;
  final ValueChanged<CodeComment> onCommentAdded;
  final String? initialComment;
  final VoidCallback? onDelete;
  final int? lineNumber;

  const AddCommentDialog({
    super.key,
    required this.filePath,
    required this.selectedSnippet,
    required this.onCommentAdded,
    this.initialComment,
    this.onDelete,
    this.lineNumber,
  });

  @override
  State<AddCommentDialog> createState() => _AddCommentDialogState();
}

class _AddCommentDialogState extends State<AddCommentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final comment = CodeComment(
      id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
      filePath: widget.filePath,
      snippet: widget.selectedSnippet,
      commentText: text,
    );

    widget.onCommentAdded(comment);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = ModalRoute.of(context) is DialogRoute || ModalRoute.of(context) is PopupRoute;

    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.mode_comment_outlined, size: 18, color: AppColors.accentBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Add Comment',
                  style: TextStyle(
                    color: AppColors.inkPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.lineNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Line ${widget.lineNumber}',
                    style: const TextStyle(
                      color: AppColors.inkSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.filePath,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Code snippet preview
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              widget.selectedSnippet.trim(),
              style: const TextStyle(
                color: AppColors.inkPrimary,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

          // Input field
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: AppColors.inkPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add instruction or feedback for this line...',
              hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceBase,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.accentBlue),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onDelete != null || (widget.initialComment != null && widget.initialComment!.isNotEmpty))
                TextButton(
                  onPressed: () {
                    widget.onDelete?.call();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              if (isDialog || Navigator.of(context).canPop())
                TextButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Cancel', style: TextStyle(color: AppColors.inkMuted)),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text('Queue Comment'),
              ),
            ],
          ),
        ],
      ),
    );

    return isDialog
        ? Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: content,
          )
        : content;
  }
}
