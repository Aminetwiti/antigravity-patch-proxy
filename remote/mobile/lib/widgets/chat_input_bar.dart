import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String message) onSend;
  final bool isConnected;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isConnected = true,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final String _selectedModel = 'Gemini 3.1 Pro High';

  bool _isSendPressed = false;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      HapticFeedback.lightImpact();
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
                // Input TextField — toujours éditable : hors-ligne, le message
                // part en outbox et sera envoyé à la reconnexion (promesse du
                // banner, audit UX P1-5).
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  minLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.isConnected
                        ? 'Ask anything, @ to mention, / for actions'
                        : 'Hors ligne — le message sera envoyé à la reconnexion',
                    hintStyle: TextStyle(
                      color: widget.isConnected
                          ? Colors.grey
                          : Theme.of(context).colorScheme.error,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
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
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.add, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Model Picker Pill
                    InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    ),

                    const Spacer(),

                    // Voice Mic Icon
                    IconButton(
                      icon: Icon(Icons.mic_none, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),

                    // Send Arrow Button
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isSendPressed = true),
                      onTapUp: (_) {
                        setState(() => _isSendPressed = false);
                        _handleSend();
                      },
                      onTapCancel: () => setState(() => _isSendPressed = false),
                      child: AnimatedScale(
                        scale: _isSendPressed ? 0.85 : 1.0,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOutQuart,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: widget.isConnected 
                                  ? Theme.of(context).colorScheme.surfaceContainer
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward, 
                              size: 16, 
                              color: widget.isConnected 
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Footer (Local / Main Agent)
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monitor_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Local',
                        style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Main Agent',
                        style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
