import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

/// Type d'étape d'exécution fidèle à Antigravity 2.0 Desktop.
enum ExecutionStepType {
  header,
  command,
  fileEdit,
  fileAnalysis,
  exploredGroup,
  task,
  thought,
}

class ExecutionStepItem {
  final ExecutionStepType type;
  final String action; // "Edited", "Analyzed", "Ran", "Run", "Explored", "Thinking", "Thought"
  final String title; // "chat_stream_screen.dart", "1 file", "flutter test ...", etc.
  final String? diffAdded; // "+12"
  final String? diffRemoved; // "-3"
  final String? lineRange; // "#L680-710"
  final String? thoughtTitle; // "Examining Conditional Logic"
  final String? consolePrompt; // "...\remote\mobile > flutter test --exclude-tags=live"
  final String? consoleOutput; // "Working." or stdout
  final String? rawDetail;
  final List<ExecutionStepItem>? subItems; // Indented child items (e.g. Analyzed under Explored)
  final bool isExpandable;
  final bool isRunning;

  const ExecutionStepItem({
    required this.type,
    required this.action,
    required this.title,
    this.diffAdded,
    this.diffRemoved,
    this.lineRange,
    this.thoughtTitle,
    this.consolePrompt,
    this.consoleOutput,
    this.rawDetail,
    this.subItems,
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
    if (seconds <= 0) return '1s';
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
            title: _secondsElapsed > 0 ? 'for ${_formatDuration(_secondsElapsed)}' : '…',
            isRunning: true,
            isExpandable: false,
          )
        ];
      }
      return [];
    }

    final rawItems = <ExecutionStepItem>[];
    final lines = raw.split('\n');
    final currentThoughtBuffer = StringBuffer();
    bool inConsoleBlock = false;
    String currentCmdTitle = '';
    String currentCmdPrompt = '';
    final consoleBuffer = StringBuffer();

    void flushConsole() {
      if (currentCmdTitle.isNotEmpty) {
        final out = consoleBuffer.toString().trim();
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.command,
          action: 'Run',
          title: currentCmdTitle,
          consolePrompt: currentCmdPrompt.isNotEmpty
              ? currentCmdPrompt
              : '> $currentCmdTitle',
          consoleOutput: out.isNotEmpty ? out : 'Working.',
          isExpandable: true,
          isRunning: widget.isStreaming,
        ));
        currentCmdTitle = '';
        currentCmdPrompt = '';
        consoleBuffer.clear();
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('```console') || line.startsWith('```terminal') || line.startsWith('```shell')) {
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
          rawItems.add(ExecutionStepItem(
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
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.fileAnalysis,
          action: isAnalyzed ? 'Analyzed' : 'Viewed',
          title: fileName,
          lineRange: lineRange,
        ));
        continue;
      }

      // 3. Explored <N> file(s)
      if (lower.startsWith('explored ')) {
        var title = line.substring(9).trim();
        if (title.endsWith('>')) title = title.substring(0, title.length - 1).trim();
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.exploredGroup,
          action: 'Explored',
          title: title.isNotEmpty ? title : '1 file',
          isExpandable: true,
        ));
        continue;
      }

      // 4. Ran / Run <command>
      if (lower.startsWith('ran ') || lower.startsWith('run ') || lower.startsWith('running command:') || lower.startsWith('executed:')) {
        final cleanTitle = line.replaceFirst(
            RegExp(r'^(ran|run|running command:|executed:)\s*', caseSensitive: false), '');
        currentCmdTitle = cleanTitle;
        currentCmdPrompt = '> $cleanTitle';
        if (i + 1 >= lines.length || !lines[i + 1].trim().startsWith('```')) {
          flushConsole();
        }
        continue;
      }

      // 5. Checked task / Search / Task
      if (lower.startsWith('checked task ') || lower.startsWith('search ') || lower.startsWith('task ')) {
        final isChecked = lower.startsWith('checked task ');
        final isSearch = lower.startsWith('search ');
        String action = 'Task';
        String title = line.substring(5).trim();
        if (isChecked) {
          action = 'Checked task';
          title = line.substring(13).trim();
        } else if (isSearch) {
          action = 'Search';
          title = line.substring(7).trim();
        }
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.task,
          action: action,
          title: title,
          isExpandable: true,
        ));
        continue;
      }

      // 6. Error messages
      if (lower.startsWith('error')) {
        var clean = line;
        if (clean.endsWith('>')) clean = clean.substring(0, clean.length - 1).trim();
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.task,
          action: '',
          title: clean,
          isExpandable: true,
          rawDetail: clean,
        ));
        continue;
      }

      // 7. Duration headers
      if (lower.startsWith('worked for ') || lower.startsWith('thinking for ') || lower.startsWith('thought for ')) {
        var clean = line;
        if (clean.endsWith('>')) clean = clean.substring(0, clean.length - 1).trim();
        rawItems.add(ExecutionStepItem(
          type: ExecutionStepType.thought,
          action: '',
          title: clean,
          isExpandable: true,
        ));
        continue;
      }

      // 8. Output / thought text
      currentThoughtBuffer.writeln(lines[i]);
    }

    flushConsole();

    // Grouping: Si on a un exploredGroup suivi d'analyses ou des analyses isolées,
    // on regroupe les analyses sous le groupe Explored comme sur Desktop.
    final items = <ExecutionStepItem>[];
    for (int i = 0; i < rawItems.length; i++) {
      final current = rawItems[i];
      if (current.type == ExecutionStepType.exploredGroup) {
        // Look ahead for subsequent fileAnalysis items
        final sub = <ExecutionStepItem>[];
        int j = i + 1;
        while (j < rawItems.length && rawItems[j].type == ExecutionStepType.fileAnalysis) {
          sub.add(rawItems[j]);
          j++;
        }
        if (sub.isNotEmpty) {
          items.add(ExecutionStepItem(
            type: ExecutionStepType.exploredGroup,
            action: current.action,
            title: sub.length == 1 ? '1 file' : '${sub.length} files',
            subItems: sub,
            isExpandable: true,
          ));
          i = j - 1; // Skip absorbed children
          continue;
        }
      } else if (current.type == ExecutionStepType.fileAnalysis) {
        // Standalone file analysis: encapsulate in an Explored 1 file row
        items.add(ExecutionStepItem(
          type: ExecutionStepType.exploredGroup,
          action: 'Explored',
          title: '1 file',
          subItems: [current],
          isExpandable: true,
        ));
        continue;
      }
      items.add(current);
    }

    // Process Thought Buffer
    final thoughtContent = currentThoughtBuffer.toString().trim();
    if (thoughtContent.isNotEmpty) {
      // Extract optional thought title (first bold line or short first paragraph)
      String? thoughtTitle;
      String body = thoughtContent;
      final thoughtLines = thoughtContent.split('\n');
      if (thoughtLines.isNotEmpty) {
        final first = thoughtLines.first.trim();
        if (first.startsWith('**') && first.endsWith('**') && first.length > 4) {
          thoughtTitle = first.substring(2, first.length - 2).trim();
          body = thoughtLines.skip(1).join('\n').trim();
        } else if (first.length < 50 && !first.endsWith('.') && thoughtLines.length > 1) {
          thoughtTitle = first;
          body = thoughtLines.skip(1).join('\n').trim();
        }
      }

      final durationStr = widget.isStreaming
          ? (_secondsElapsed > 0 ? 'for ${_formatDuration(_secondsElapsed)}' : '')
          : (_secondsElapsed > 0 ? 'for ${_formatDuration(_secondsElapsed)}' : 'for 1s');

      items.add(ExecutionStepItem(
        type: ExecutionStepType.thought,
        action: widget.isStreaming ? 'Thinking' : 'Thought',
        title: durationStr.isNotEmpty ? durationStr : 'for 1s',
        thoughtTitle: thoughtTitle ?? 'Reasoning',
        rawDetail: body.isNotEmpty ? body : thoughtContent,
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
    final isExpanded = _expandedIndices.contains(index) ||
        (widget.initiallyExpanded && item.type == ExecutionStepType.thought);

    return Container(
      margin: const EdgeInsets.only(bottom: 2.5),
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
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Action verb: "Explored", "Edited", "Run", "Thought", "Thinking"
                  if (item.action.isNotEmpty) ...[
                    Text(
                      item.action,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9FA8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],

                  // File Icon Badge (Desktop 🔵 icon) for file actions
                  if (item.type == ExecutionStepType.fileEdit ||
                      item.type == ExecutionStepType.fileAnalysis) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 5),
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0284C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.description_rounded,
                          size: 8.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],

                  // Step title (Filename / Duration / Command)
                  Flexible(
                    child: Text(
                      isExpanded && item.rawDetail != null && item.type != ExecutionStepType.thought
                          ? item.rawDetail!
                          : item.title,
                      key: (item.type == ExecutionStepType.thought && widget.messageId != null)
                          ? Key('thought-${widget.messageId}')
                          : null,
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: (item.type == ExecutionStepType.command ||
                                item.type == ExecutionStepType.fileEdit ||
                                item.type == ExecutionStepType.fileAnalysis)
                            ? 'monospace'
                            : null,
                        fontWeight: item.type == ExecutionStepType.thought
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: item.type == ExecutionStepType.thought
                            ? const Color(0xFF9E9FA8)
                            : const Color(0xFFF4F4F5),
                      ),
                    ),
                  ),

                  // Line range badge: #L680-710
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

                  // Diffs: +12 -3
                  if (item.diffAdded != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      item.diffAdded!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4ADE80),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.diffRemoved ?? '-0',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF87171),
                      ),
                    ),
                  ],

                  // Running Spinner or Expand Chevron
                  if (item.isRunning) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBlueBright),
                      ),
                    ),
                  ],

                  if (item.isExpandable) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 14,
                      color: const Color(0xFF71717A),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Sub-items for Explored Group (Indented Children)
          if (isExpanded && item.subItems != null && item.subItems!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sub in item.subItems!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sub.action,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9FA8),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            margin: const EdgeInsets.only(right: 5),
                            width: 13,
                            height: 13,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0284C7),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.description_rounded,
                                size: 8.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              sub.title,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFF4F4F5),
                              ),
                            ),
                          ),
                          if (sub.lineRange != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              sub.lineRange!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Console Terminal Box for Run command
          if (isExpanded && item.type == ExecutionStepType.command)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0F12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF27272A), width: 0.8),
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
                          color: Color(0xFF71717A),
                        ),
                      ),
                    ),
                  if (item.consoleOutput != null && item.consoleOutput!.isNotEmpty)
                    SelectableText(
                      item.consoleOutput!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: Color(0xFFD4D4D8),
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),

          // Thought Reasoned Detail Block (with Header & Token Highlights)
          if (isExpanded && item.type == ExecutionStepType.thought && item.rawDetail != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.thoughtTitle != null && item.thoughtTitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        item.thoughtTitle!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF4F4F5),
                        ),
                      ),
                    ),
                  _buildFormattedThoughtText(item.rawDetail!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Builds thought text with subtle syntax highlighting on code tokens (gold/amber)
  Widget _buildFormattedThoughtText(String text) {
    final spans = <InlineSpan>[];
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isCodeToken = (word.contains('_') ||
              RegExp(r'^[a-zA-Z]+[A-Z][a-zA-Z0-9]*').hasMatch(word) ||
              word.startsWith('`') ||
              word.endsWith('`') ||
              word.startsWith('#L')) &&
          word.length > 2;

      if (isCodeToken) {
        final clean = word.replaceAll('`', '');
        spans.add(TextSpan(
          text: '$clean ',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFFFCD34D), // Antigravity 2.0 Gold token
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: '$word ',
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: Color(0xFFD4D4D8),
          ),
        ));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }
}
