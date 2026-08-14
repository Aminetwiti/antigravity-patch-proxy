import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

/// Carte interactive de Side Question (/btw) inspirée d'AG2R
class SideQuestionCard extends StatefulWidget {
  final String question;
  final String? answer;
  final bool isLoading;
  final VoidCallback onClose;

  const SideQuestionCard({
    super.key,
    required this.question,
    this.answer,
    this.isLoading = false,
    required this.onClose,
  });

  @override
  State<SideQuestionCard> createState() => _SideQuestionCardState();
}

class _SideQuestionCardState extends State<SideQuestionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.accentBlue.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isExpanded = !_isExpanded);
            },
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 14, color: AppColors.accentBlueBright),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Side Question: ${widget.question}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isLoading) ...[
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accentBlue),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 16,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(Icons.close, size: 14, color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),

          // Answer section (when expanded)
          if (_isExpanded) ...[
            const Divider(height: 1, color: AppColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(12),
              child: widget.answer != null && widget.answer!.isNotEmpty
                  ? Text(
                      widget.answer!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSecondary,
                        height: 1.4,
                      ),
                    )
                  : const Text(
                      'En attente de la réponse à la question parallèle...',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
