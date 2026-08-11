import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/notifications/approval_notifier.dart';
import '../../core/protocol/daemon_api.dart';
import '../../core/protocol/messages.dart';
import '../../core/protocol/stream_parser.dart';
import '../../widgets/chat_input_bar.dart';
import '../../widgets/markdown_bubble.dart';
import '../../widgets/tool_approval_card.dart';

class ChatStreamScreen extends StatefulWidget {
  final DaemonApi? api;
  final String activeSessionId;
  final String activeProjectName;

  const ChatStreamScreen({
    super.key,
    required this.api,
    required this.activeSessionId,
    required this.activeProjectName,
  });

  @override
  State<ChatStreamScreen> createState() => _ChatStreamScreenState();
}

class _ChatStreamScreenState extends State<ChatStreamScreen> {
  final List<ChatMessage> _messages = [];
  ToolApprovalRequest? _pendingApproval;
  
  StreamSubscription<Map<String, dynamic>>? _streamSub;
  int _messageCounter = 0;

  static const _stillWorkingDelay = Duration(seconds: 15);
  final Set<String> _pendingApprovalCallIds = {};
  Timer? _stillWorkingTimer;
  int _activeStreamCount = 0;
  bool _showStillWorking = false;
  Map<String, dynamic>? _lastLocalStreamEnd;
  final Map<String, String> _externalThoughts = {};

  @override
  void initState() {
    super.initState();
    _watchBroadcastStreams();
  }

  @override
  void didUpdateWidget(covariant ChatStreamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSessionId != widget.activeSessionId) {
      _messages.clear();
      _pendingApproval = null;
      _pendingApprovalCallIds.clear();
    }
    if (oldWidget.api != widget.api) {
      _watchBroadcastStreams();
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _stillWorkingTimer?.cancel();
    super.dispose();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _onStreamStarted() {
    _activeStreamCount++;
    if (_activeStreamCount == 1) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = Timer(_stillWorkingDelay, () {
        if (mounted && _activeStreamCount > 0) {
          setState(() => _showStillWorking = true);
        }
      });
    }
  }

  void _onStreamEnded() {
    if (_activeStreamCount > 0) _activeStreamCount--;
    if (_activeStreamCount == 0) {
      _stillWorkingTimer?.cancel();
      _stillWorkingTimer = null;
      if (_showStillWorking && mounted) {
        setState(() => _showStillWorking = false);
      }
    }
  }

  void _handleStreamEnded(Map<String, dynamic> msg) {
    final data = msg['data'];
    if (data is! Map<String, dynamic>) return;
    if (msg['data']?['hostActive'] == true) return;
    final outcome = data['outcome'] as String? ?? 'done';
    final cascadeId = data['cascadeId'] as String? ?? widget.activeSessionId;
    final message = data['message'] as String? ?? '';
    ApprovalNotifier.instance.notifyTaskEnded(
      cascadeId: cascadeId,
      outcome: outcome,
      message: message,
    );
  }

  void _watchBroadcastStreams() {
    _streamSub?.cancel();
    _streamSub = widget.api?.events.listen((msg) {
      final isBroadcast = msg['broadcast'] == true;
      if (!isBroadcast || !mounted) return;
      final type = msg['type'] as String?;
      final requestId = msg['requestId'] as String? ?? '';
      final sessionId = msg['data']?['cascadeId'] as String?;
      if (sessionId != null && sessionId != widget.activeSessionId) return;

      if (type == 'stream_start') {
        _onStreamStarted();
        setState(() {
          _messages.add(ChatMessage(
            id: 'ext-$requestId',
            sender: 'assistant',
            text: '',
            timestamp: _timestamp(),
            isStreaming: true,
          ));
        });
      } else if (type == 'stream_delta') {
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            final current = _messages[idx];
            _externalThoughts[requestId] =
                (_externalThoughts[requestId] ?? '') + thoughtDelta;
            _messages[idx] = current.copyWith(
              text: current.text + textDelta,
              thought: _externalThoughts[requestId]!.isNotEmpty
                  ? 'Thought · ${_externalThoughts[requestId]!.trim()}'
                  : current.thought,
            );
          }
          if (approval != null) {
            _pendingApproval = ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            );
            _pendingApprovalCallIds.add(approval.callId);
            final hostActive = msg['data']?['hostActive'] == true;
            if (!hostActive) {
              ApprovalNotifier.instance.notifyApprovalRequired(
                callId: approval.callId,
                toolName: approval.tool,
                command: approval.command,
              );
            }
          }
        });
      } else if (type == 'stream_end') {
        _onStreamEnded();
        _handleStreamEnded(msg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == 'ext-$requestId');
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
          _externalThoughts.remove(requestId);
        });
      }
    });
  }

  void _handleSendMessage(String text) {
    final api = widget.api;
    setState(() {
      _messages.add(ChatMessage(
        id: 'm${++_messageCounter}',
        sender: 'user',
        text: text,
        timestamp: _timestamp(),
      ));
    });

    if (api == null) return;

    _onStreamEnded(); 
    final assistantId = 'a${++_messageCounter}';
    _lastLocalStreamEnd = null;
    setState(() {
      _messages.add(ChatMessage(
        id: assistantId,
        sender: 'assistant',
        text: '',
        timestamp: _timestamp(),
        isStreaming: true,
      ));
    });

    var thoughtBuffer = StringBuffer();
    _onStreamStarted();
    api.sendPrompt(widget.activeSessionId, text).listen(
      (msg) {
        if (msg['type'] == 'stream_end') {
          _lastLocalStreamEnd = msg;
        }
        final textDelta = StreamDeltaParser.textOf(msg);
        final thoughtDelta = StreamDeltaParser.thinkingOf(msg);
        final approval = StreamDeltaParser.approvalOf(msg);
        if (!mounted) return;
        setState(() {
          if (textDelta.isNotEmpty || thoughtDelta.isNotEmpty) {
            final idx = _messages.indexWhere((m) => m.id == assistantId);
            if (idx >= 0) {
              final current = _messages[idx];
              thoughtBuffer.write(thoughtDelta);
              _messages[idx] = current.copyWith(
                text: current.text + textDelta,
                thought: thoughtBuffer.isNotEmpty
                    ? 'Thought · ${thoughtBuffer.toString().trim()}'
                    : current.thought,
              );
            }
          }
          if (approval != null) {
            _pendingApproval = ToolApprovalRequest(
              callId: approval.callId,
              toolName: approval.tool,
              command: approval.command,
              description: 'Tool execution requires your confirmation',
              cascadeId: approval.cascadeId,
              trajectoryId: approval.trajectoryId,
              stepIndex: approval.stepIndex,
              approvalType: approval.approvalType,
            );
            _pendingApprovalCallIds.add(approval.callId);
            final hostActive = msg['data']?['hostActive'] == true;
            if (!hostActive) {
              ApprovalNotifier.instance.notifyApprovalRequired(
                callId: approval.callId,
                toolName: approval.tool,
                command: approval.command,
              );
            }
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        _onStreamEnded();
        _handleStreamEnded(_lastLocalStreamEnd ?? const {});
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        _onStreamEnded();
        ApprovalNotifier.instance.notifyTaskEnded(
          cascadeId: widget.activeSessionId,
          outcome: 'error',
          message: e.toString(),
        );
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(
              text: _messages[idx].text.isEmpty
                  ? '⚠ Erreur : $e'
                  : _messages[idx].text,
              isStreaming: false,
            );
          }
        });
      },
    );
  }

  void _handleToolDecision(ToolDecision decision) {
    final approval = _pendingApproval;
    setState(() {
      _pendingApproval = null;
    });
    if (approval == null) return;
    ApprovalNotifier.instance.cancelApproval(approval.callId);
    _pendingApprovalCallIds.remove(approval.callId);
    widget.api?.submitApproval(
      cascadeId: approval.cascadeId.isEmpty
          ? widget.activeSessionId
          : approval.cascadeId,
      callId: approval.callId,
      allow: decision == ToolDecision.allow,
      trajectoryId: approval.trajectoryId,
      stepIndex: approval.stepIndex,
      approvalType: approval.approvalType,
      command: approval.command,
    ).catchError((_) => <String, dynamic>{});
  }

  Widget _buildReminderBanners() {
    final children = <Widget>[];
    if (_showStillWorking) {
      children.add(const _ReminderBanner(
        icon: Icons.hourglass_top_outlined,
        message: 'La tâche tourne toujours — suivez la depuis le téléphone',
      ));
    }
    final pendingApprovals = _pendingApprovalCallIds.length;
    if (pendingApprovals >= 2) {
      children.add(const _ReminderBanner(
        icon: Icons.pan_tool_alt_outlined,
        message: 'Approuvez les appels d\'outils depuis le téléphone',
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final banner in children) ...[banner, const SizedBox(height: 8)],
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_messages.isEmpty && _pendingApproval == null) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      widget.activeProjectName,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 16),
                ChatInputBar(
                  onSend: _handleSendMessage,
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildReminderBanners(),
              ..._messages.map((msg) => _MessageBubble(message: msg)),
              if (_pendingApproval != null)
                ToolApprovalCard(
                  request: _pendingApproval!,
                  onDecision: _handleToolDecision,
                ),
            ],
          ),
        ),
        ChatInputBar(
          onSend: _handleSendMessage,
        ),
      ],
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ReminderBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _isThoughtExpanded = true;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.sender == 'user';

    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16, left: 40),
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Text(
            widget.message.text,
            style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.thought != null) ...[
            InkWell(
              onTap: () {
                setState(() {
                  _isThoughtExpanded = !_isThoughtExpanded;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.message.thought!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isThoughtExpanded ? Icons.chevron_right : Icons.expand_more,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          MarkdownBubble(
            text: widget.message.text,
            isStreaming: widget.message.isStreaming,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.message.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copié dans le presse-papiers'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.thumb_up_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Icon(Icons.thumb_down_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}
