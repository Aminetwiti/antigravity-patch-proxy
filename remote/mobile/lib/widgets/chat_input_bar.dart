import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String message) onSend;

  const ChatInputBar({
    super.key,
    required this.onSend,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final String _selectedModel = 'Gemini 3.6 Flash Medium';

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input TextField
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkPrimary),
            decoration: const InputDecoration(
              hintText: 'Ask anything, @ to mention, / for actions',
              hintStyle: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              fillColor: Colors.transparent,
              filled: false,
            ),
          ),
          const SizedBox(height: 8),

          // Bottom Action Bar Pills
          Row(
            children: [
              // Attachment Plus Button
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18, color: AppColors.inkSecondary),
                ),
              ),
              const SizedBox(width: 8),

              // Worktree Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.alt_route, size: 13, color: AppColors.inkSecondary),
                    SizedBox(width: 4),
                    Text(
                      'Worktree',
                      style: TextStyle(fontSize: 11, color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Model Picker Pill
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedModel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_up, size: 14, color: AppColors.inkMuted),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Voice Mic Icon
              IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                icon: const Icon(Icons.mic_none, size: 18, color: AppColors.inkMuted),
                onPressed: () {},
              ),
              const SizedBox(width: 4),

              // Send Arrow Button
              InkWell(
                onTap: _handleSend,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceInput,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward, size: 16, color: AppColors.inkPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
