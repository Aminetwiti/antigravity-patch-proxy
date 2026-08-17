import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/protocol/daemon_api.dart';
import '../theme/app_colors.dart';

/// Console Terminal Interactive Mobile
/// Permet d'exécuter des commandes CLI en direct sur le PC hôte via le Daemon.
class RemoteTerminalSheet extends StatefulWidget {
  final DaemonApi? api;
  final String projectName;

  /// P3 : contenu pré-rempli dans la barre de saisie (bloc shell envoyé
  /// depuis un message — l'utilisateur n'a plus qu'à valider).
  final String initialCommand;

  const RemoteTerminalSheet({
    super.key,
    required this.api,
    this.projectName = 'Workspace',
    this.initialCommand = '',
  });

  static Future<void> show(
    BuildContext context, {
    DaemonApi? api,
    String projectName = 'Workspace',
    String initialCommand = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RemoteTerminalSheet(
        api: api,
        projectName: projectName,
        initialCommand: initialCommand,
      ),
    );
  }

  @override
  State<RemoteTerminalSheet> createState() => _RemoteTerminalSheetState();
}

class _TerminalEntry {
  final String command;
  final String output;
  final bool isError;
  final DateTime timestamp;

  _TerminalEntry({
    required this.command,
    required this.output,
    this.isError = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class _RemoteTerminalSheetState extends State<RemoteTerminalSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_TerminalEntry> _entries = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  bool _isRunning = false;

  // État de session PTY (P3) : quand le daemon répond à terminal_create
  // avec un id, on bascule en mode "flux live" — la sortie streamée est
  // affichée dans _ptyBuffer au lieu des entrées commande→résultat.
  String? _ptyId;
  String _ptyBuffer = '';
  bool _ptyClosed = false;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  final List<String> _quickCommands = [
    'git status',
    'git diff --stat',
    'git branch -a',
    'npm test',
    'flutter analyze',
    'ls -la',
  ];

  @override
  void initState() {
    super.initState();
    _entries.add(
      _TerminalEntry(
        command: 'init',
        output:
            'Antigravity Remote Terminal Bridge v3.1.0\nConnecté au PC hôte — prêt pour exécution.',
      ),
    );
    // P3 : bloc shell pré-rempli — l'utilisateur valide d'une touche.
    if (widget.initialCommand.isNotEmpty) {
      _inputController.text = widget.initialCommand;
    }
    _openPty();
  }

  /// Ouvre une session PTY interactive (terminal_create).
  /// Fallback silencieux : si le daemon ne supporte pas encore le PTY
  /// (version antérieure), on garde le mode commande→résultat existant.
  Future<void> _openPty() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final res = await api.terminalCreate('.');
      final id = res['id'] as String?;
      if (!mounted || id == null || id.isEmpty) return;
      setState(() => _ptyId = id);
      _eventSub = api.events.listen(_onTerminalEvent);
    } catch (_) {
      // Daemon sans support PTY → on reste en mode legacy.
    }
  }

  void _onTerminalEvent(Map<String, dynamic> msg) {
    if (msg['type'] != 'terminal_output') return;
    if (msg['id'] != _ptyId) return;
    final data = (msg['data'] as String?) ?? '';
    final kind = (msg['kind'] as String?) ?? 'stdout';
    if (!mounted) return;
    setState(() {
      if (kind == 'exit') {
        _ptyClosed = true;
        _ptyBuffer += '\n[process exited]\n';
      } else {
        _ptyBuffer += data;
      }
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_ptyId != null && _ptyId!.isNotEmpty) {
      try {
        widget.api?.terminalKill(_ptyId!);
      } catch (_) {}
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Envoie une ligne à la session PTY (terminal_write).
  Future<void> _writePty(String input) async {
    final id = _ptyId;
    final api = widget.api;
    if (id == null || id.isEmpty || api == null || _ptyClosed) return;
    try {
      await api.terminalWrite(id, input);
    } catch (_) {}
  }

  /// Point d'entrée unique de la barre de saisie : PTY si session active,
  /// sinon mode legacy commande→résultat.
  void _submitInput(String val) {
    if (_ptyId != null) {
      final text = val.trimRight();
      if (text.isEmpty) return;
      setState(() {
        _ptyBuffer += '\$ $text\n';
        _ptyClosed = false;
      });
      _writePty('$text\n');
      _inputController.clear();
      _scrollToBottom();
      return;
    }
    _executeCommand(val);
  }

  Future<void> _executeCommand(String rawCmd) async {
    final cmd = rawCmd.trim();
    if (cmd.isEmpty) return;

    _history.remove(cmd);
    _history.add(cmd);
    _historyIndex = _history.length;

    setState(() {
      _isRunning = true;
      _inputController.clear();
    });

    _scrollToBottom();

    final api = widget.api;
    if (api == null) {
      setState(() {
        _isRunning = false;
        _entries.add(
          _TerminalEntry(
            command: cmd,
            output: 'Erreur: Daemon non connecté.',
            isError: true,
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    try {
      final res = await api.sendCommand(cmd);
      String output = '';
      bool isErr = false;

      if (res['error'] != null) {
        output = res['error'].toString();
        isErr = true;
      } else if (res['data'] != null) {
        final d = res['data'];
        if (d is Map) {
          output =
              d['output']?.toString() ??
              d['text']?.toString() ??
              d['result']?.toString() ??
              d.toString();
        } else {
          output = d.toString();
        }
      } else if (res['text'] != null) {
        output = res['text'].toString();
      } else {
        output = 'Commande exécutée (code 0).';
      }

      if (mounted) {
        setState(() {
          _isRunning = false;
          _entries.add(
            _TerminalEntry(command: cmd, output: output.trim(), isError: isErr),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _entries.add(
            _TerminalEntry(
              command: cmd,
              output: 'Échec d\'exécution : $e',
              isError: true,
            ),
          );
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Console PTY live : buffer scrollable + invite en bas de flux.
  Widget _buildPtyConsole() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _ptyBuffer.isEmpty
                  ? 'Session PTY ouverte — tapez une commande (ex: git status).\n'
                  : _ptyBuffer,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFFD4D4D8),
                height: 1.4,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(
            _ptyClosed ? '[session terminée — fermez la console]' : r'$',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: _ptyClosed ? AppColors.inkMuted : AppColors.positive,
            ),
          ),
        ),
      ],
    );
  }

  void _navigateHistory(int direction) {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + direction).clamp(0, _history.length - 1);
    final cmd = _history[_historyIndex];
    _inputController.text = cmd;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: cmd.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    final height = (mq.size.height * 0.85).clamp(360.0, 720.0);

    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: height + bottomInset,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
          left: BorderSide(color: scheme.outlineVariant, width: 1),
          right: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: AppColors.positive,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Terminal — ${widget.projectName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  tooltip: 'Effacer l\'historique',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _entries.clear());
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),

          // Quick command pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _quickCommands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final cmd = _quickCommands[idx];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _submitInput(cmd),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        cmd,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),

          // Console Output — en mode PTY, affiche le buffer live ; sinon
          // la liste commande→résultat existante.
          Expanded(
            child:
                _ptyId != null
                    ? _buildPtyConsole()
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length + (_isRunning ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _entries.length && _isRunning) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation(
                                      AppColors.positive,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Exécution en cours...',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final entry = _entries[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entry.command != 'init')
                                Row(
                                  children: [
                                    const Text(
                                      r'$ ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.positive,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Expanded(
                                      child: SelectableText(
                                        entry.command,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (entry.output.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          entry.isError
                                              ? scheme.error.withValues(
                                                alpha: 0.4,
                                              )
                                              : scheme.outlineVariant,
                                      width: 1,
                                    ),
                                  ),
                                  child: SelectableText(
                                    entry.output,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color:
                                          entry.isError
                                              ? scheme.error
                                              : scheme.onSurface,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
          ),

          // Bottom Input bar
          Container(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomInset),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: Border(
                top: BorderSide(color: scheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (_ptyId != null) ...[
                  // Ctrl-C : interrompt le processus en cours (SIGINT).
                  IconButton(
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: _ptyClosed ? null : () => _writePty('\x03'),
                    tooltip: 'Ctrl-C (SIGINT)',
                  ),
                  const SizedBox(width: 4),
                ],
                if (_history.isNotEmpty && _ptyId == null) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: AppColors.inkMuted,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => _navigateHistory(-1),
                    tooltip: 'Commande précédente',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: AppColors.inkMuted,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => _navigateHistory(1),
                    tooltip: 'Commande suivante',
                  ),
                  const SizedBox(width: 4),
                ],
                const Text(
                  r'$ ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.positive,
                    fontFamily: 'monospace',
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    autofocus: false,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Taper une commande CLI (ex: git pull, npm test)...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                    ),
                    onSubmitted: (val) => _submitInput(val),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.send_rounded,
                    size: 16,
                    color: AppColors.accentBlue,
                  ),
                  onPressed: () => _submitInput(_inputController.text),
                  tooltip: 'Exécuter',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
