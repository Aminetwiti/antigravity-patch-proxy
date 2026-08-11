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
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Ask anything, @ to mention, / for actions',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
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
                        child: Icon(Icons.add, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Voice Mic Icon
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: Icon(Icons.mic_none, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),

                    // Send Arrow Button
                    InkWell(
                      onTap: _handleSend,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.onSurface),
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
              Icon(Icons.monitor_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Local',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const Spacer(),
              Text(
                'Main Agent',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
            ],
          ),
        ],
      ),
    );
  }
}
