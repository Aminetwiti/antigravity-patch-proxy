import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../config/env_config.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// Low-level resilient WebSocket client using native stdlib `dart:io` WebSocket.
/// ponytail: Zero external dependencies, pure Dart stdlib WebSocket stream.
class DaemonWebSocketClient {
  WebSocket? _socket;
  StreamController<dynamic>? _messageController;
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier(ConnectionStatus.disconnected);

  Timer? _reconnectTimer;
  Timer? _retryCountdownTimer;
  String _targetUrl = EnvConfig.wsUrl;
  String? _authToken;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;

  /// Backoff exponentiel : 2s → 4s → 8s → 16s → 30s (plafond).
  /// ponytail: pas de dépendance (package:async retry) — 4 lignes de calcul.
  @visibleForTesting
  static Duration backoffDelay(int attempt) {
    final capped = attempt < 4 ? attempt : 4;
    final seconds = min(30, 2 * (1 << capped));
    return Duration(seconds: seconds);
  }

  /// Numéro de la tentative de reconnexion + temps restant avant la prochaine
  /// tentative — regroupés dans UN notifier pour que l'UI (banner) écoute
  /// une seule source et se mette à jour en un setState.
  final ValueNotifier<RetryInfo> retryInfo = ValueNotifier(const RetryInfo());

  /// Alias pratique pour l'UI : l'état de connexion actuel.
  ConnectionStatus get status => statusNotifier.value;

  /// Étape 5 : incrémenté à chaque reconnexion réussie. Les consommateurs
  /// (DaemonApi → replay outbox, UI → re-sync) écoutent ce notifier pour
  /// savoir quand l'état distant doit être rejoué.
  final ValueNotifier<int> reconnectVersion = ValueNotifier(0);

  Stream<dynamic> get stream =>
      _messageController?.stream ?? const Stream.empty();

  /// Étape 6 : la connexion a été abandonnée (dispose). Les callbacks async
  /// tardifs (WebSocket.connect en vol, onDone, onError) doivent devenir no-op
  /// au lieu de notifier des ValueNotifier déjà disposés.
  bool _disposed = false;

  /// Jeton de connexion : COMPLÉTÉ par [dispose]. Le `connect` en vol fait la
  /// course avec ce jeton ; si dispose gagne, on renonce sans notifier.
  Completer<void>? _connectToken;

  /// Timer de timeout 5 s pour `WebSocket.connect` en vol : annulé dans
  /// dispose/disconnect pour ne pas laisser de timer pendant après la
  /// destruction (tests « A Timer is still pending »).
  Timer? _connectTimeout;

  Future<void> connect({String? customUrl, String? authToken}) async {
    if (customUrl != null && customUrl.isNotEmpty) {
      _targetUrl = customUrl;
    }
    if (authToken != null) {
      _authToken = authToken;
    }

    if (_disposed) return;
    if (statusNotifier.value == ConnectionStatus.connected ||
        statusNotifier.value == ConnectionStatus.connecting) {
      return;
    }

    _manualDisconnect = false;
    statusNotifier.value = ConnectionStatus.connecting;
    _messageController ??= StreamController<dynamic>.broadcast();

    try {
      var finalUrl = _targetUrl;
      if (_authToken != null && _authToken!.isNotEmpty) {
        finalUrl += '${finalUrl.contains('?') ? '&' : '?'}token=$_authToken';
      }
      final uri = Uri.parse(finalUrl);
      final token = Completer<void>();
      _connectToken = token;
      // Course à trois : socket | timeout 5 s | abandon (dispose).
      // Un `.timeout()` standard créerait un timer interne non annulable qui
      // laisserait le test sur « A Timer is still pending » ; ce Timer
      // explicite est annulé dans dispose/disconnect.
      final socketFuture = WebSocket.connect(uri.toString());
      final completer = Completer<WebSocket>();
      socketFuture.then(completer.complete, onError: completer.completeError);
      _connectTimeout?.cancel();
      _connectTimeout = Timer(const Duration(seconds: 5), () {
        socketFuture.then((s) => s.close());
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('WebSocket connect timeout'));
        }
      });
      try {
        _socket = await completer.future;
      } finally {
        _connectTimeout?.cancel();
        _connectTimeout = null;
      }
      if (_disposed || token.isCompleted) {
        _socket?.close();
        _socket = null;
        return;
      }
      _connectToken = null;

      statusNotifier.value = ConnectionStatus.connected;
      _reconnectAttempts = 0;
      _stopRetryCountdown();
      retryInfo.value = const RetryInfo();
      reconnectVersion.value++; // Étape 5 : signaler la (re)connexion
      if (kDebugMode) {
        print('[DaemonWS] Connected to $_targetUrl');
      }

      _socket!.listen(
        (data) {
          _messageController?.add(data);
        },
        onError: (error) {
          if (kDebugMode) {
            print('[DaemonWS] Error: $error');
          }
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) {
            print('[DaemonWS] Stream closed');
          }
          _handleDisconnect();
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('[DaemonWS] Connection failed: $e');
      }
      _handleDisconnect();
    }
  }

  void send(dynamic data) {
    if (statusNotifier.value == ConnectionStatus.connected && _socket != null) {
      if (data is Map || data is List) {
        _socket!.add(jsonEncode(data));
      } else {
        _socket!.add(data);
      }
    }
  }

  void _handleDisconnect() {
    if (_disposed) {
      _socket?.close();
      _socket = null;
      return;
    }
    statusNotifier.value = ConnectionStatus.disconnected;
    _socket?.close();
    _socket = null;
    _reconnectAttempts++;
    retryInfo.value = retryInfo.value.copyWith(attempt: _reconnectAttempts);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _stopRetryCountdown();
    if (_manualDisconnect) return;
    final delay = backoffDelay(_reconnectAttempts);
    // Jitter ±1 s : évite la rafale synchrone quand plusieurs appareils
    // retombent en même temps (le host redémarre).
    final jitter = Random().nextInt(2000) - 1000;
    final effective = delay + Duration(milliseconds: jitter);
    retryInfo.value =
        retryInfo.value.copyWith(nextRetryIn: effective);
    // Compte à rebours visible : 1 tick / seconde vers la prochaine tentative.
    _retryCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = retryInfo.value.nextRetryIn - const Duration(seconds: 1);
      retryInfo.value =
          retryInfo.value.copyWith(nextRetryIn: left.isNegative ? Duration.zero : left);
    });
    _reconnectTimer = Timer(
      effective,
      () {
        _stopRetryCountdown();
        if (_disposed) return;
        retryInfo.value = retryInfo.value.copyWith(nextRetryIn: Duration.zero);
        if (statusNotifier.value == ConnectionStatus.disconnected) {
          connect();
        }
      },
    );
  }

  void _stopRetryCountdown() {
    _retryCountdownTimer?.cancel();
    _retryCountdownTimer = null;
  }

  void disconnect() {
    if (_disposed) {
      _socket?.close();
      _socket = null;
      _connectToken?.complete();
      _connectTimeout?.cancel();
      _connectTimeout = null;
      return;
    }
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _connectToken?.complete();
    _connectToken = null;
    _stopRetryCountdown();
    _socket?.close();
    _socket = null;
    statusNotifier.value = ConnectionStatus.disconnected;
    retryInfo.value = const RetryInfo();
  }

  /// Vrai quand la déconnexion vient d'un choix explicite de l'utilisateur
  /// (bouton « Offline ») et non d'une perte réseau : l'UI ne doit pas
  /// notifier « Connexion perdue » dans ce cas.
  bool get isManualDisconnect => _manualDisconnect;

  /// Annule l'attente du backoff et tente immédiatement une connexion
  /// (bouton « Réessayer » du banner).
  void retryNow() {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _stopRetryCountdown();
    retryInfo.value = const RetryInfo();
    connect();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _connectToken?.complete();
    _connectToken = null;
    _stopRetryCountdown();
    disconnect();
    _messageController?.close();
    _messageController = null;
    reconnectVersion.dispose();
    retryInfo.dispose();
  }
}

/// État de reconnexion exposé à l'UI : numéro de tentative en cours et temps
/// restant avant la prochaine relance (décrémenté chaque seconde).
class RetryInfo {
  final int attempt;
  final Duration nextRetryIn;

  const RetryInfo({this.attempt = 0, this.nextRetryIn = Duration.zero});

  RetryInfo copyWith({int? attempt, Duration? nextRetryIn}) {
    return RetryInfo(
      attempt: attempt ?? this.attempt,
      nextRetryIn: nextRetryIn ?? this.nextRetryIn,
    );
  }
}
