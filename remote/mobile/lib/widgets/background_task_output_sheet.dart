import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';
import '../core/protocol/daemon_api.dart';

/// Modal / BottomSheet affichant la sortie d'une tâche de fond en temps réel
/// inspiré de l'interface "Background Task Output" d'Antigravity IDE.
class BackgroundTaskOutputSheet extends StatefulWidget {
  final String taskId;
  final String command;
  final String initialOutput;
  final String status;
  final Stream<String>? outputStream;
  final VoidCallback? onStop;
  final DaemonApi? api;
  final String? cascadeId;

  const BackgroundTaskOutputSheet({
    super.key,
    required this.taskId,
    required this.command,
    this.initialOutput = '',
    this.status = 'running',
    this.outputStream,
    this.onStop,
    this.api,
    this.cascadeId,
  });

  static Future<void> show(
    BuildContext context, {
    required String taskId,
    required String command,
    String initialOutput = '',
    String status = 'running',
    Stream<String>? outputStream,
    VoidCallback? onStop,
    DaemonApi? api,
    String? cascadeId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackgroundTaskOutputSheet(
        taskId: taskId,
        command: command,
        initialOutput: initialOutput,
        status: status,
        outputStream: outputStream,
        onStop: onStop,
        api: api,
        cascadeId: cascadeId,
      ),
    );
  }

  @override
  State<BackgroundTaskOutputSheet> createState() => _BackgroundTaskOutputSheetState();
}

class _BackgroundTaskOutputSheetState extends State<BackgroundTaskOutputSheet> {
  final ScrollController _scrollController = ScrollController();
  late StringBuffer _outputBuffer;
  late String _currentStatus;
  Timer? _pollTimer;
  final bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _outputBuffer = StringBuffer(widget.initialOutput);
    _fetchLog();
    if (_currentStatus == 'running') {
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _fetchLog());
    }
    widget.outputStream?.listen((delta) {
      if (mounted) {
        setState(() {
          _outputBuffer.write(delta);
        });
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });
  }

  Future<void> _fetchLog() async {
    if (widget.api != null && widget.cascadeId != null && widget.cascadeId!.isNotEmpty) {
      final res = await widget.api!.getTaskLog(widget.cascadeId!, widget.taskId);
      if (mounted && res.isNotEmpty) {
        final log = res['log']?.toString() ?? '';
        final st = res['status']?.toString() ?? _currentStatus;
        bool changed = false;
        if (log.isNotEmpty && log != _outputBuffer.toString()) {
          _outputBuffer.clear();
          _outputBuffer.write(log);
          changed = true;
        }
        if (st != _currentStatus) {
          _currentStatus = st;
          changed = true;
          if (_currentStatus != 'running') {
            _pollTimer?.cancel();
          }
        }
        if (changed) {
          setState(() {});
          if (_autoScroll) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = _currentStatus == 'running';
    final outputText = _outputBuffer.toString();
    final lines = outputText.isEmpty ? <String>['(En attente de la sortie de la commande...)'] : outputText.split('\n');

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceBase : AppColors.surfaceInput,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border(
          top: BorderSide(color: isDark ? AppColors.borderStrong : AppColors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderStrong : AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // En-tête Antigravity 2.0
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Tab pill avec icône terminal
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceRaised : AppColors.surfaceBase,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: isDark ? AppColors.borderStrong : AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.terminal_rounded, size: 14, color: AppColors.accentBlue),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          widget.command,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: isDark ? AppColors.inkPrimary : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isRunning) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.accentBlue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),

                // Copier
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Copier la sortie',
                  color: isDark ? AppColors.inkMuted : const Color(0xFF8B949E),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: outputText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sortie copiée dans le presse-papier'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),

                // Arrêter la tâche
                if (isRunning && widget.onStop != null) ...[
                  IconButton(
                    icon: const Icon(Icons.stop_circle_rounded, size: 18, color: AppColors.danger),
                    tooltip: 'Arrêter la tâche',
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onStop!();
                      Navigator.of(context).pop();
                    },
                  ),
                ],

                // Fermer
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Fermer',
                  color: isDark ? AppColors.inkMuted : const Color(0xFF8B949E),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Titre secondaire
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Background Task Output',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.inkPrimary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? AppColors.accentBlue.withValues(alpha: 0.15)
                        : AppColors.positive.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isRunning ? 'EN COURS' : 'TERMINÉ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isRunning ? AppColors.accentBlue : AppColors.positive,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 12, thickness: 1),

          // Zone de console terminal avec numéros de lignes
          Expanded(
            child: Container(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFF1E1E1E),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final lineNum = index + 1;
                  final lineContent = lines[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Numéro de ligne
                        SizedBox(
                          width: 38,
                          child: Text(
                            '$lineNum',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF6E7681),
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Contenu de la ligne
                        Expanded(
                          child: Text(
                            lineContent,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: Color(0xFFE6EDF3),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
