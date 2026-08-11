import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications locales pour les demandes d'approbation (APPROVAL_REQUIRED)
/// et les fins de tâche (stream_end structuré).
///
/// Objectif : compenser l'absence de FCM (100% local, pas de dépendance
/// Firebase). Le phone peut être en arrière-plan ou verrouillé : la
/// notification le ramène à l'écran d'approbation.
///
/// `ponytail:` — pas de FCM ni de plugin d'état d'écran : on notifie toujours,
/// le host n'émet l'événement que si personne n'est actif sur le PC (l'idle
/// detection vit côté gateway Go, pas ici).
class ApprovalNotifier {
  ApprovalNotifier._();

  static final ApprovalNotifier instance = ApprovalNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Dernière demande notifiée (callId) pour éviter les doublons quand
  /// plusieurs clients reçoivent le même broadcast.
  String? _lastCallId;
  DateTime? _lastShownAt;

  /// Notification « tâche terminée » déjà montrée pour cette cascade — évite
  /// de re-sonner quand le broadcast stream_end arrive sur plusieurs surfaces.
  String? _lastTaskDoneCascade;
  DateTime? _lastTaskDoneAt;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(settings);

      // Sur les environnements sans registrant de plugin (flutter test,
      // headless), resolvePlatformSpecificImplementation renvoie null :
      // on désactive les notifications sans planter. Sur Android/iOS réel,
      // le registrant Dart est toujours présent.
      // ponytail: plafond = les tests ne vérifient pas la vraie chaîne de
      // notification ; chemin d'upgrade = fake platform dans widget_test.dart
      // (FlutterLocalNotificationsPlatform.instance = …) si besoin plus tard.
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[Notifier] notifications indisponibles: $e');
    }
  }

  /// Notifie une demande d'approbation — dédupliquée par [callId] avec un
  /// délai de grâce de 10 s (le broadcast multi-surface envoie le même
  /// événement à tous les clients connectés).
  Future<void> notifyApprovalRequired({
    required String callId,
    required String toolName,
    required String command,
  }) async {
    final now = DateTime.now();
    if (callId == _lastCallId &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastCallId = callId;
    _lastShownAt = now;

    const androidDetails = AndroidNotificationDetails(
      'approval_required',
      'Approbations',
      channelDescription: 'Demandes d\'approbation de commandes distantes',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      callId.hashCode,
      'Approbation requise — $toolName',
      command.length > 120 ? '${command.substring(0, 120)}…' : command,
      details,
    );
    debugPrint('[Notifier] approval notification -> $callId ($toolName)');
  }

  /// Notifie la fin d'une tâche (stream_end) : terminée, erreur ou action
  /// requise. Dédupliquée par cascade sur 30 s.
  Future<void> notifyTaskEnded({
    required String cascadeId,
    required String outcome, // 'done' | 'error' | 'approval'
    required String message,
  }) async {
    if (!_initialized) return;
    final now = DateTime.now();
    if (cascadeId == _lastTaskDoneCascade &&
        _lastTaskDoneAt != null &&
        now.difference(_lastTaskDoneAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastTaskDoneCascade = cascadeId;
    _lastTaskDoneAt = now;

    final (title, body, channelId) = switch (outcome) {
      'error' => (
          '⚠ Tâche interrompue',
          message.isEmpty ? 'Une erreur est survenue sur le PC hôte' : message,
          'task_errors',
        ),
      'approval' => (
          '✋ Action requise',
          message.isEmpty ? 'L\'agent attend votre approbation' : message,
          'approval_required',
        ),
      _ => (
          '✅ Tâche terminée',
          message.isEmpty ? 'L\'agent a fini de travailler' : message,
          'task_done',
        ),
    };

    const androidDetails = AndroidNotificationDetails(
      'task_done',
      'Tâches distantes',
      channelDescription: 'Fin des tâches exécutées sur le PC hôte',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const errorDetails = AndroidNotificationDetails(
      'task_errors',
      'Erreurs de tâche',
      channelDescription: 'Erreurs des tâches exécutées sur le PC hôte',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const approvalDetails = AndroidNotificationDetails(
      'approval_required',
      'Approbations',
      channelDescription: 'Demandes d\'approbation de commandes distantes',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );

    final android = switch (channelId) {
      'task_errors' => errorDetails,
      'approval_required' => approvalDetails,
      _ => androidDetails,
    };
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(android: android, iOS: iosDetails);

    await _plugin.show(
      cascadeId.hashCode,
      title,
      body.length > 120 ? '${body.substring(0, 120)}…' : body,
      details,
    );
    debugPrint('[Notifier] task notification -> $cascadeId ($outcome)');
  }

  /// Annule la notification (l'utilisateur a répondu sur une autre surface).
  Future<void> cancelApproval(String callId) async {
    await _plugin.cancel(callId.hashCode);
  }

  /// Annule la notification de fin de tâche d'une cascade.
  Future<void> cancelTask(String cascadeId) async {
    await _plugin.cancel(cascadeId.hashCode);
  }
}
