import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications locales pour les demandes d'approbation (APPROVAL_REQUIRED).
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

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    // Android 13+ : permission runtime POST_NOTIFICATIONS (déclarée dans le
    // manifest) — l'utilisateur doit accepter pour recevoir les alertes.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
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

  /// Annule la notification (l'utilisateur a répondu sur une autre surface).
  Future<void> cancelApproval(String callId) async {
    await _plugin.cancel(callId.hashCode);
  }
}
