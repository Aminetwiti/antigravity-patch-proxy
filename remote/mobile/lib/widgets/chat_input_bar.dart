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
  final String _selectedModel = 'Gemini 3.1 Pro High';

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Input TextField
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14, color: AppColors.inkPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Ask anything, @ to mention, / for actions',
                    hintStyle: TextStyle(color: AppColors.inkMuted, fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                ),
                const SizedBox(height: 12),

                // Bottom Action Bar Pills
                Row(
                  children: [
                    // Attachment Plus Button
                    InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.add, size: 20, color: AppColors.inkSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Model Picker Pill
                    InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          Text(
                            _selectedModel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.inkMuted),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Voice Mic Icon
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.mic_none, size: 20, color: AppColors.inkSecondary),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),

                    // Send Arrow Button
                    InkWell(
                      onTap: _handleSend,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward, size: 16, color: AppColors.inkPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Footer (Local / Main Agent)
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.monitor_outlined, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 6),
              const Text(
                'Local',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.inkMuted),
              const Spacer(),
              const Text(
                'Main Agent',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 12),
            ],
          ),
        ],
      ),
    );
  }
}
