import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scheduled_tasks/models/scheduled_task_item.dart';
import 'package:mobile/features/scheduled_tasks/scheduled_tasks_screen.dart';

void main() {
  group('ScheduledTaskItem Model', () {
    test('serializes and deserializes from JSON correctly', () {
      final json = {
        'id': 'task_cron_123',
        'prompt': 'Check health and report',
        'cronExpression': '*/5 * * * *',
        'durationSeconds': null,
        'isDaemon': true,
        'iterationsRun': 42,
        'nextRunAt': '2026-08-14T14:00:00.000Z',
      };

      final item = ScheduledTaskItem.fromJson(json);
      expect(item.id, equals('task_cron_123'));
      expect(item.prompt, equals('Check health and report'));
      expect(item.cronExpression, equals('*/5 * * * *'));
      expect(item.isDaemon, isTrue);
      expect(item.iterationsRun, equals(42));
      expect(item.nextRunAt, isNotNull);

      final encoded = item.toJson();
      expect(encoded['id'], equals('task_cron_123'));
      expect(encoded['cronExpression'], equals('*/5 * * * *'));
      expect(encoded['isDaemon'], isTrue);
      expect(encoded['iterationsRun'], equals(42));
    });

    test('handles one-shot timer JSON', () {
      final json = {
        'id': 'timer_1',
        'prompt': 'Remind me to push branch',
        'durationSeconds': 600,
        'isDaemon': false,
        'iterationsRun': 0,
      };

      final item = ScheduledTaskItem.fromJson(json);
      expect(item.id, equals('timer_1'));
      expect(item.durationSeconds, equals(600));
      expect(item.cronExpression, isNull);
      expect(item.isDaemon, isFalse);
    });
  });

  group('ScheduledTasksScreen Widget', () {
    testWidgets('renders active cron jobs and one-shot timers', (tester) async {
      final tasks = [
        ScheduledTaskItem(
          id: 'task_cron_1',
          prompt: 'Run server health check',
          cronExpression: '*/5 * * * *',
          isDaemon: true,
          iterationsRun: 12,
        ),
        ScheduledTaskItem(
          id: 'task_timer_2',
          prompt: 'Run memory cleanup',
          durationSeconds: 300,
          isDaemon: false,
          iterationsRun: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduledTasksScreen(
            tasks: tasks,
            onCancelTask: (_) {},
            onTriggerNow: (_) {},
          ),
        ),
      );

      expect(find.text('Scheduled Tasks (2)'), findsOneWidget);
      expect(find.text('Run server health check'), findsOneWidget);
      expect(find.text('*/5 * * * *'), findsOneWidget);
      expect(find.text('Run memory cleanup'), findsOneWidget);
    });

    testWidgets('renders empty state when no tasks exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduledTasksScreen(
            tasks: const [],
            onCancelTask: (_) {},
            onTriggerNow: (_) {},
          ),
        ),
      );

      expect(find.text('Scheduled Tasks (0)'), findsOneWidget);
      expect(find.text('Aucune tâche planifiée'), findsOneWidget);
    });

    testWidgets('calls onTriggerNow when trigger button is tapped', (tester) async {
      String? triggeredId;
      final tasks = [
        ScheduledTaskItem(
          id: 'task_trigger_me',
          prompt: 'Execute data sync',
          cronExpression: '0 * * * *',
          isDaemon: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduledTasksScreen(
            tasks: tasks,
            onTriggerNow: (id) => triggeredId = id,
            onCancelTask: (_) {},
          ),
        ),
      );

      final triggerBtn = find.widgetWithText(OutlinedButton, 'Trigger Now');
      expect(triggerBtn, findsOneWidget);

      await tester.tap(triggerBtn);
      await tester.pumpAndSettle();

      expect(triggeredId, equals('task_trigger_me'));
    });

    testWidgets('calls onCancelTask when cancel button is tapped', (tester) async {
      String? cancelledId;
      final tasks = [
        ScheduledTaskItem(
          id: 'task_cancel_me',
          prompt: 'Check logs every minute',
          cronExpression: '* * * * *',
          isDaemon: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduledTasksScreen(
            tasks: tasks,
            onTriggerNow: (_) {},
            onCancelTask: (id) => cancelledId = id,
          ),
        ),
      );

      final cancelBtn = find.byTooltip('Annuler la tâche');
      expect(cancelBtn, findsOneWidget);

      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      expect(cancelledId, equals('task_cancel_me'));
    });
  });
}
