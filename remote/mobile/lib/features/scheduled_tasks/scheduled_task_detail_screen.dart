import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/scheduled_task_item.dart';
import 'package:mobile/theme/app_colors.dart';

/// Écran Détails et Exécution d'une tâche planifiée (Antigravity 2.0)
/// Affiche le statut en direct (Running / Paused), le prompt modifiable, la planification,
/// le bouton Save, le déclenchement immédiat (Trigger) et l'historique des événements (Events).
class ScheduledTaskDetailScreen extends StatefulWidget {
  final ScheduledTaskItem task;
  final ValueChanged<ScheduledTaskItem>? onUpdateTask;
  final ValueChanged<String>? onTriggerNow;
  final ValueChanged<String>? onDeleteTask;

  const ScheduledTaskDetailScreen({
    super.key,
    required this.task,
    this.onUpdateTask,
    this.onTriggerNow,
    this.onDeleteTask,
  });

  @override
  State<ScheduledTaskDetailScreen> createState() => _ScheduledTaskDetailScreenState();
}

class _ScheduledTaskDetailScreenState extends State<ScheduledTaskDetailScreen> {
  late ScheduledTaskItem _task;
  late TextEditingController _nameController;
  late TextEditingController _promptController;

  String _selectedFrequency = 'Daily';
  String _selectedTime = '9:00 AM';
  bool _isEditingName = false;
  bool _isSaving = false;

  final List<String> _frequencies = ['Daily', 'Hourly', 'Weekly', 'Every 15 min', 'Custom Cron'];
  final List<String> _times = ['9:00 AM', '12:00 PM', '6:00 PM', '12:00 AM', '3:00 PM', '6:00 AM'];

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _nameController = TextEditingController(text: _task.displayName);
    _promptController = TextEditingController(text: _task.prompt);

    if (_task.cronExpression != null) {
      if (_task.cronExpression == '0 9 * * *') {
        _selectedFrequency = 'Daily';
        _selectedTime = '9:00 AM';
      } else if (_task.cronExpression == '0 12 * * *') {
        _selectedFrequency = 'Daily';
        _selectedTime = '12:00 PM';
      } else if (_task.cronExpression == '0 18 * * *') {
        _selectedFrequency = 'Daily';
        _selectedTime = '6:00 PM';
      } else if (_task.cronExpression == '0 * * * *') {
        _selectedFrequency = 'Hourly';
      } else if (_task.cronExpression == '*/15 * * * *') {
        _selectedFrequency = 'Every 15 min';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  String _computeCron() {
    if (_selectedFrequency == 'Daily') {
      if (_selectedTime == '9:00 AM') return '0 9 * * *';
      if (_selectedTime == '12:00 PM') return '0 12 * * *';
      if (_selectedTime == '6:00 PM') return '0 18 * * *';
      if (_selectedTime == '12:00 AM') return '0 0 * * *';
      return '0 9 * * *';
    } else if (_selectedFrequency == 'Hourly') {
      return '0 * * * *';
    } else if (_selectedFrequency == 'Every 15 min') {
      return '*/15 * * * *';
    } else if (_selectedFrequency == 'Weekly') {
      return '0 9 * * 1';
    }
    return _task.cronExpression ?? '0 9 * * *';
  }

  void _saveChanges() {
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);

    final updated = _task.copyWith(
      name: _nameController.text.trim(),
      prompt: _promptController.text.trim(),
      cronExpression: _computeCron(),
    );

    setState(() {
      _task = updated;
      _isSaving = false;
      _isEditingName = false;
    });

    widget.onUpdateTask?.call(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scheduled task saved'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF1B1D22),
      ),
    );
  }

  void _triggerExecution() {
    HapticFeedback.mediumImpact();
    widget.onTriggerNow?.call(_task.id);

    final now = DateTime.now();
    final newEvent = ScheduledTaskEvent(
      id: 'evt_${now.millisecondsSinceEpoch}',
      timestamp: now,
      outcome: 'done',
      message: 'Triggered task: ${_task.prompt}',
      durationMs: 140,
    );

    final updated = _task.copyWith(
      iterationsRun: _task.iterationsRun + 1,
      events: [newEvent, ..._task.events],
    );

    setState(() {
      _task = updated;
    });

    widget.onUpdateTask?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final wsName = _task.workspaceName ?? 'antigravity-add-model-main';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1012),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.inkPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
        ),
        title: Text(
          'Scheduled Tasks / ${_task.displayName}',
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF8F909A),
            fontWeight: FontWeight.w400,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 22, color: AppColors.accentBlue),
            tooltip: 'Trigger Now',
            onPressed: _triggerExecution,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF8F909A)),
            color: AppColors.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.borderStrong),
            ),
            onSelected: (val) {
              if (val == 'restart') {
                _triggerExecution();
              } else if (val == 'delete') {
                widget.onDeleteTask?.call(_task.id);
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'restart',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: AppColors.inkPrimary),
                    SizedBox(width: 10),
                    Text('Restart', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('Delete', style: TextStyle(fontSize: 13, color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Title with Edit Pencil + Project Badge ───────────────
              Row(
                children: [
                  if (_isEditingName)
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accentBlue)),
                        ),
                        onSubmitted: (_) => setState(() => _isEditingName = false),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        _nameController.text.isEmpty ? _task.displayName : _nameController.text,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _isEditingName ? Icons.check_rounded : Icons.edit_outlined,
                      size: 17,
                      color: const Color(0xFF8F909A),
                    ),
                    tooltip: _isEditingName ? 'Valider le nom' : 'Modifier le nom',
                    onPressed: () => setState(() => _isEditingName = !_isEditingName),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              // Project folder badge
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 13, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Text(
                    wsName,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF8F909A)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── 1. Status Details Card ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141518),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: const Color(0xFF23252B)),
                ),
                child: Column(
                  children: [
                    _buildStatusRow(
                      label: 'Status',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _task.isEnabled ? const Color(0xFF22C55E) : const Color(0xFF8F909A),
                              shape: BoxShape.circle,
                              boxShadow: _task.isEnabled
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _task.isEnabled ? 'Running' : 'Paused',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _task.isEnabled ? const Color(0xFF22C55E) : const Color(0xFF8F909A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20, color: Color(0xFF23252B)),
                    _buildStatusRow(
                      label: 'Type',
                      child: Text(
                        _task.isDaemon ? 'Scheduled' : 'One-shot',
                        style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                      ),
                    ),
                    const Divider(height: 20, color: Color(0xFF23252B)),
                    _buildStatusRow(
                      label: 'Uptime',
                      child: Text(
                        _task.uptime,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── 2. Prompt Section ──────────────────────────────────────────
              const Text(
                'Prompt',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFD4D4D8)),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141518),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: const Color(0xFF23252B)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: TextField(
                  controller: _promptController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.inkPrimary, height: 1.4),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter a prompt for the agent to run...',
                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFF5E606A)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── 3. Schedule Section ────────────────────────────────────────
              const Text(
                'Schedule',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFD4D4D8)),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141518),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: const Color(0xFF23252B)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Frequency dropdown (Daily ⌄)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1D22),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: const Color(0xFF2C2F36)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedFrequency,
                              dropdownColor: const Color(0xFF1B1D22),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF8F909A), size: 16),
                              items: _frequencies
                                  .map((f) => DropdownMenuItem(
                                        value: f,
                                        child: Text(f, style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary)),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedFrequency = val);
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),
                        const Text(
                          'around',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8F909A)),
                        ),
                        const SizedBox(width: 8),

                        // Time dropdown (9:00 AM ⌄)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1D22),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: const Color(0xFF2C2F36)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedTime,
                              dropdownColor: const Color(0xFF1B1D22),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF8F909A), size: 16),
                              items: _times
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t, style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary)),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedTime = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Bouton Save (Bleu Antigravity 2.0)
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D64B4),
                        foregroundColor: AppColors.onAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── 4. Events Section ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Events',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkPrimary),
                  ),
                  if (_task.events.isNotEmpty)
                    Text(
                      '${_task.events.length} run${_task.events.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF8F909A)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_task.events.isEmpty)
                const Text(
                  'No events recorded.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF5E606A)),
                )
              else
                ..._task.events.map((evt) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141518),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: const Color(0xFF23252B)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            evt.outcome == 'done' ? Icons.check_circle_outline : Icons.error_outline,
                            size: 15,
                            color: evt.outcome == 'done' ? AppColors.positive : AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  evt.message.isNotEmpty ? evt.message : 'Execution completed',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${evt.timestamp.hour.toString().padLeft(2, '0')}:${evt.timestamp.minute.toString().padLeft(2, '0')}:${evt.timestamp.second.toString().padLeft(2, '0')}'
                                  '${evt.durationMs != null ? ' (${evt.durationMs}ms)' : ''}',
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow({required String label, required Widget child}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF8F909A)),
        ),
        child,
      ],
    );
  }
}
