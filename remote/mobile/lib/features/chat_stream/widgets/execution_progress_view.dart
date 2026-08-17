import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

/// Type d'étape d'exécution fidèle à Antigravity 2.0.
enum ExecutionStepType {
  header,
  command,
  fileEdit,
  fileAnalysis,
  task,
  thought,
}

class ExecutionStepItem {
  final ExecutionStepType type;
  final String action; // "Edited", "Analyzed", "Ran", "Explored", "Checked task", "Thinking"
  final String title; // "chat_stream_screen.dart", "flutter analyze", etc.
  final String? diffAdded; // "+1"
  final String? diffRemoved; // "-1"
  final String? lineRange; // "#L1180-1230"
  final String? consolePrompt; // "...\remote\mobile > flutter analyze"
  final String? consoleOutput; // stdout
  final String? rawDetail;
  final bool isExpandable;
  final bool isRunning;

  const ExecutionStepItem({
    required this.type,
    required this.action,
    required this.title,
    this.diffAdded,
    this.diffRemoved,
    this.lineRange,
    this.consolePrompt,
    this.consoleOutput,
    this.rawDetail,
    this.isExpandable = false,
    this.isRunning = false,
  });
}

/// Vue de déroulement d'exécution en direct fidèle à Antigravity 2.0 ("The Quiet Console").
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

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
  }

  List<ExecutionStepItem> _parseSteps(String raw) {
    if (raw.trim().isEmpty) {
      if (widget.isStreaming) {
        return [
          ExecutionStepItem(
            type: ExecutionStepType.thought,
            action: 'Thinking',
            title: _secondsElapsed > 0 ? 'Thinking for ${_formatDuration(_secondsElapsed)}' : 'Thinking…',
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
    bool inConsoleBlock = false;
    String currentCmdTitle = '';
    String currentCmdPrompt = '';
    final consoleBuffer = StringBuffer();

    void flushConsole() {
      if (currentCmdTitle.isNotEmpty) {
        items.add(ExecutionStepItem(
          type: ExecutionStepType.command,
          action: 'Ran',
          title: currentCmdTitle,
          consolePrompt: currentCmdPrompt,
          consoleOutput: consoleBuffer.toString().trim(),
          isExpandable: consoleBuffer.isNotEmpty,
        ));
        currentCmdTitle = '';
        currentCmdPrompt = '';
        consoleBuffer.clear();
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('```console')) {
        inConsoleBlock = true;
        continue;
      }
      if (inConsoleBlock) {
        if (line.startsWith('```')) {
          inConsoleBlock = false;
          flushConsole();
        } else if (line.contains(' > ')) {
          currentCmdPrompt = line;
        } else {
          consoleBuffer.writeln(line);
        }
        continue;
      }

      final lower = line.toLowerCase();

      // 1. Edited <file> +X -Y
      if (lower.startsWith('edited ')) {
        final rest = line.substring(7).trim();
        final match = RegExp(r'^(\S+)(?:\s+\+(\d+)\s+-(\d+))?').firstMatch(rest);
        if (match != null) {
          final fileName = match.group(1) ?? rest;
          final add = match.group(2);
          final del = match.group(3);
          items.add(ExecutionStepItem(
            type: ExecutionStepType.fileEdit,
            action: 'Edited',
            title: fileName,
            diffAdded: add != null ? '+$add' : '+1',
            diffRemoved: del != null ? '-$del' : '-0',
          ));
          continue;
        }
      }

      // 2. Analyzed / Viewed <file> #L123-456
      if (lower.startsWith('analyzed ') || lower.startsWith('viewed ')) {
        final isAnalyzed = lower.startsWith('analyzed ');
        final rest = line.substring(isAnalyzed ? 9 : 7).trim();
        final match = RegExp(r'^(\S+)(?:\s+(#L\d+(?:-\d+)?))?').firstMatch(rest);
        final fileName = match?.group(1) ?? rest;
        final lineRange = match?.group(2);
        items.add(ExecutionStepItem(
          type: ExecutionStepType.fileAnalysis,
          action: isAnalyzed ? 'Analyzed' : 'Viewed',
          title: fileName,
          lineRange: lineRange,
        ));
        continue;
      }

      // 3. Ran <command>
      if (lower.startsWith('ran ') || lower.startsWith('running command:') || lower.startsWith('executed:')) {
        final cleanTitle = line.replaceFirst(RegExp(r'^(ran|running command:|executed:)\s*', caseSensitive: false), '');
        currentCmdTitle = cleanTitle;
        currentCmdPrompt = '> $cleanTitle';
        if (i + 1 >= lines.length || !lines[i + 1].trim().startsWith('```console')) {
          flushConsole();
        }
        continue;
      }

      // 4. Explored / Checked task / Search
      if (lower.startsWith('explored ') || lower.startsWith('checked task ') || lower.startsWith('search ') || lower.startsWith('task ')) {
        final isChecked = lower.startsWith('checked task ');
        final isSearch = lower.startsWith('search ');
        final isTask = lower.startsWith('task ');
        String action = 'Explored';
        String title = line.substring(9).trim();
        if (isChecked) {
          action = 'Checked task';
          title = line.substring(13).trim();
        } else if (isSearch) {
          action = 'Search';
          title = line.substring(7).trim();
        } else if (isTask) {
          action = 'Task';
          title = line.substring(5).trim();
        }
        items.add(ExecutionStepItem(
          type: ExecutionStepType.task,
          action: action,
          title: title,
          isExpandable: true,
        ));
        continue;
      }

      // 5. Error messages in execution (Desktop Antigravity format)
      if (lower.startsWith('error')) {
        var clean = line;
        if (clean.endsWith('>')) clean = clean.substring(0, clean.length - 1).trim();
        items.add(ExecutionStepItem(
          type: ExecutionStepType.task,
          action: '',
          title: clean,
          isExpandable: true,
          rawDetail: clean,
        ));
        continue;
      }

      // 6. Worked for / Duration lines
      if (lower.startsWith('worked for ') || lower.startsWith('thinking for ')) {
        var clean = line;
        if (clean.endsWith('>')) clean = clean.substring(0, clean.length - 1).trim();
        items.add(ExecutionStepItem(
          type: ExecutionStepType.thought,
          action: '',
          title: clean,
          isExpandable: true,
        ));
        continue;
      }

      // 7. General finished commands & analysis
      if (lower.endsWith(' finished') || lower.endsWith(' finished >') || lower.contains(': command may require input') || lower.startsWith('run ') || lower.startsWith('flutter run')) {
        var clean = line;
        if (clean.endsWith('>')) clean = clean.substring(0, clean.length - 1).trim();
        items.add(ExecutionStepItem(
          type: ExecutionStepType.command,
          action: '',
          title: clean,
          isExpandable: true,
          rawDetail: clean,
        ));
        continue;
      }

      // 8. Blocs de pensée / Raisonnement pur
      currentThoughtBuffer.writeln(lines[i]);
    }

    flushConsole();

    final thoughtContent = currentThoughtBuffer.toString().trim();
    if (thoughtContent.isNotEmpty) {
      final durationStr = widget.isStreaming
          ? (_secondsElapsed > 0 ? 'for ${_formatDuration(_secondsElapsed)}' : '…')
          : (_secondsElapsed > 0 ? 'for ${_formatDuration(_secondsElapsed)}' : '');
      items.add(ExecutionStepItem(
        type: ExecutionStepType.thought,
        action: widget.isStreaming ? 'Thinking $durationStr' : (durationStr.isNotEmpty ? 'Thought $durationStr' : 'Thought'),
        title: thoughtContent,
        rawDetail: thoughtContent,
        isExpandable: true,
        isRunning: widget.isStreaming,
      ));
    }

    return items;
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
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
        color: isExpanded && item.rawDetail != null
            ? const Color(0xFF141518)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isExpanded && item.rawDetail != null
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
                    if (item.type == ExecutionStepType.thought) {
                      widget.onToggleExpand?.call();
                    }
                  }
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
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
                  else if (item.title.toLowerCase().startsWith('error'))
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 13,
                      color: AppColors.danger,
                    )
                  else if (item.type == ExecutionStepType.fileEdit || item.type == ExecutionStepType.fileAnalysis)
                    const Icon(
                      Icons.description_rounded,
                      size: 13,
                      color: AppColors.accentBlueBright,
                    )
                  else if (item.type == ExecutionStepType.command)
                    const Icon(
                      Icons.terminal_rounded,
                      size: 13,
                      color: Color(0xFF9E9FA8),
                    )
                  else if (item.type == ExecutionStepType.thought)
                    const Icon(
                      Icons.psychology_outlined,
                      size: 13,
                      color: Color(0xFF9E9FA8),
                    )
                  else
                    const Icon(
                      Icons.task_alt_rounded,
                      size: 13,
                      color: Color(0xFF9E9FA8),
                    ),
                  const SizedBox(width: 6),

                  // Action label: "Edited", "Analyzed", "Ran", "Explored", "Thinking"
                  if (item.action.isNotEmpty)
                    Text(
                      '${item.action} ',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9FA8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                  // Title
                  Flexible(
                    child: Text(
                      isExpanded && item.rawDetail != null ? item.rawDetail! : item.title,
                      key: (item.type == ExecutionStepType.thought && widget.messageId != null)
                          ? Key('thought-${widget.messageId}')
                          : null,
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: (item.type == ExecutionStepType.command || item.type == ExecutionStepType.fileEdit || item.type == ExecutionStepType.fileAnalysis)
                            ? 'monospace'
                            : null,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE4E4E7),
                      ),
                    ),
                  ),

                  // Line range badge: #L1180-1230
                  if (item.lineRange != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      item.lineRange!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],

                  // Diffs: +1 (green) -0 (red)
                  if (item.diffAdded != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      item.diffAdded!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      item.diffRemoved ?? '-0',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],

                  // Expand chevron
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

          // Console output block for Ran command
          if (isExpanded && item.consoleOutput != null && item.consoleOutput!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF090A0C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF27272A), width: 0.6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.consolePrompt != null && item.consolePrompt!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        item.consolePrompt!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF9E9FA8),
                        ),
                      ),
                    ),
                  SelectableText(
                    item.consoleOutput!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D8),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

          // Thought detail block
          if (isExpanded && item.type == ExecutionStepType.thought && item.rawDetail != null)
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
                  item.rawDetail!,
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
