class ScheduledTaskItem {
  final String id;
  final String prompt;
  final String? cronExpression;
  final int? durationSeconds;
  final bool isDaemon;
  final int iterationsRun;
  final DateTime? nextRunAt;

  ScheduledTaskItem({
    required this.id,
    required this.prompt,
    this.cronExpression,
    this.durationSeconds,
    this.isDaemon = false,
    this.iterationsRun = 0,
    this.nextRunAt,
  });

  factory ScheduledTaskItem.fromJson(Map<String, dynamic> json) {
    return ScheduledTaskItem(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      cronExpression: json['cronExpression'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      isDaemon: json['isDaemon'] as bool? ?? false,
      iterationsRun: json['iterationsRun'] as int? ?? 0,
      nextRunAt: json['nextRunAt'] != null
          ? DateTime.tryParse(json['nextRunAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prompt': prompt,
      if (cronExpression != null) 'cronExpression': cronExpression,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      'isDaemon': isDaemon,
      'iterationsRun': iterationsRun,
      if (nextRunAt != null) 'nextRunAt': nextRunAt!.toIso8601String(),
    };
  }
}
