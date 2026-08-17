import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

/// Un élément d'étape d'exécution ou de raisonnement (style Antigravity 2.0).
enum ExecutionStepType {
  command,
  fileAnalysis,
  task,
  thought,
  generic,
}

class ExecutionStepItem {
  final ExecutionStepType type;
  final String title;
  final String? subtitle;
  final String? detail;
  final bool isExpandable;
  final bool isRunning;
  final String? durationText;

  const ExecutionStepItem({
    required this.type,
    required this.title,
    this.subtitle,
    this.detail,
    this.isExpandable = false,
    this.isRunning = false,
    this.durationText,
  });
}

/// Vue de déroulement d'exécution en direct fidèle à Antigravity 2.0 ("The Quiet Console").
/// Affiche les commandes exécutées, fichiers analysés, tâches et réflexions (Thinking).
class ExecutionProgressView extends StatefulWidget {
  final String? messageId;
  final String? thoughtText;
  final bool isStreaming;
  final String? modelLabel;
  final VoidCallback? onToggleExpand;
  final bool initiallyExpanded;

  const ExecutionProgressView({
    super.key,
    this.messageId,
    this.thoughtText,
    this.isStreaming = false,
    this.modelLabel,
    this.onToggleExpand,
    this.initiallyExpanded = false,
  });

  @override
  State<ExecutionProgressView> createState() => _ExecutionProgressViewState();
}

class _ExecutionProgressViewState extends State<ExecutionProgressView>
    with SingleTickerProviderStateMixin {
  final Set<int> _expandedIndices = {};
  int _secondsElapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.isStreaming) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(ExecutionProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !oldWidget.isStreaming) {
      _secondsElapsed = 0;
      _startTimer();
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _secondsElapsed++);
      }
    });
  }

  List<ExecutionStepItem> _parseSteps(String raw) {
    if (raw.trim().isEmpty) {
      if (widget.isStreaming) {
        return [
          ExecutionStepItem(
            type: ExecutionStepType.thought,
            title: _secondsElapsed > 0 ? 'Thinking for ${_secondsElapsed}s' : 'Thinking…',
            isRunning: true,
            isExpandable: false,
          )
        ];
      }
      return [];
    }

    final items = <ExecutionStepItem>[];
    final lines = raw.split('\n');
    final currentThoughtBuffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        if (currentThoughtBuffer.isNotEmpty) {
          currentThoughtBuffer.writeln();
        }
        continue;
      }

      // 1. Détection de commandes exécutées
      final lower = line.toLowerCase();
      if (lower.startsWith('ran ') || lower.startsWith('running command:') || lower.startsWith('executed:')) {
        final cleanTitle = line.replaceFirst(RegExp(r'^(ran|running command:|executed:)\s*', caseSensitive: false), '');
        items.add(ExecutionStepItem(
          type: ExecutionStepType.command,
          title: 'Ran $cleanTitle',
          isExpandable: false,
        ));
      } else if (lower.startsWith('analyzed ') || lower.startsWith('viewed ') || lower.startsWith('explored file')) {
        items.add(ExecutionStepItem(
          type: ExecutionStepType.fileAnalysis,
          title: line,
          isExpandable: false,
        ));
      } else if (lower.startsWith('explored ') || lower.startsWith('netstat check') || lower.startsWith('task ')) {
        items.add(ExecutionStepItem(
          type: ExecutionStepType.task,
          title: line,
          isExpandable: false,
        ));
      } else {
        // Blocs de pensée / Raisonnement pur
        currentThoughtBuffer.writeln(lines[i]);
      }
    }

    final thoughtContent = currentThoughtBuffer.toString().trim();
    if (thoughtContent.isNotEmpty) {
      final durationStr = widget.isStreaming
          ? (_secondsElapsed > 0 ? 'for ${_secondsElapsed}s' : '…')
          : '';
      items.add(ExecutionStepItem(
        type: ExecutionStepType.thought,
        title: widget.isStreaming ? 'Thinking $durationStr' : 'Thought',
        detail: thoughtContent,
        isExpandable: true,
        isRunning: widget.isStreaming,
      ));
    }

    return items;
  }

  IconData _iconForType(ExecutionStepType type) {
    switch (type) {
      case ExecutionStepType.command:
        return Icons.terminal_rounded;
      case ExecutionStepType.fileAnalysis:
        return Icons.code_rounded;
      case ExecutionStepType.task:
        return Icons.task_alt_rounded;
      case ExecutionStepType.thought:
        return Icons.psychology_outlined;
      case ExecutionStepType.generic:
        return Icons.lens_blur_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.thoughtText ?? '';
    final steps = _parseSteps(raw);
    if (steps.isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++)
              _buildStepRow(steps[i], i),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(ExecutionStepItem item, int index) {
    final isExpanded = _expandedIndices.contains(index) || (widget.initiallyExpanded && item.type == ExecutionStepType.thought);

    return Container(
      margin: const EdgeInsets.only(bottom: 3.5),
      decoration: BoxDecoration(
        color: isExpanded && item.detail != null
            ? const Color(0xFF141518)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isExpanded && item.detail != null
            ? Border.all(color: const Color(0xFF27272A), width: 0.8)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: (item.type == ExecutionStepType.thought && widget.messageId != null)
                ? Key('thought-toggle-${widget.messageId}')
                : null,
            onTap: item.isExpandable
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_expandedIndices.contains(index)) {
                        _expandedIndices.remove(index);
                      } else {
                        _expandedIndices.add(index);
                      }
                    });
                    widget.onToggleExpand?.call();
                  }
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.isRunning)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBlueBright),
                      ),
                    )
                  else
                    Icon(
                      _iconForType(item.type),
                      size: 13,
                      color: const Color(0xFF9E9FA8),
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isExpanded && item.detail != null ? item.detail! : item.title,
                      key: (item.type == ExecutionStepType.thought && widget.messageId != null)
                          ? Key('thought-${widget.messageId}')
                          : null,
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: item.type == ExecutionStepType.command ? 'monospace' : null,
                        color: item.isRunning
                            ? AppColors.inkPrimary
                            : const Color(0xFFB4B4BC),
                        fontWeight: item.type == ExecutionStepType.thought
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (item.isExpandable) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                      size: 14,
                      color: const Color(0xFF71717A),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isExpanded && item.detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 10, bottom: 8, top: 4),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF27272A), width: 0.6),
                ),
                child: SelectableText(
                  item.detail!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFD4D4D8),
                    height: 1.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
