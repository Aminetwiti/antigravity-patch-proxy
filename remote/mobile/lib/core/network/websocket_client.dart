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
  bool _connecting = false;
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

  /// Timer de timeout 15 s pour `WebSocket.connect` en vol : annulé dans
  /// dispose/disconnect pour ne pas laisser de timer pendant après la
  /// destruction (tests « A Timer is still pending »). Le dispose ferme
  /// directement le socket via le garde `_disposed` dans connect().
  Timer? _connectTimeout;

  /// Keep-alive applicatif : le daemon ferme les connexions sans frame après
  /// pongWait (60 s). En arrière-plan, l'OS Android gèle le réseau → le ping
  /// WS natif 30 s du serveur est perdu. On envoie donc un ping JSON toutes
  /// les 20 s quand connecté : toute frame reçue reset le read deadline du
  /// daemon → la connexion survit. ponytail: intervalle fixe 20 s, pas de
  /// jitter — suffisant pour traverser Cloudflare/4G.
  static const keepAliveInterval = Duration(seconds: 20);
  Timer? _keepAliveTimer;

  /// Callback appelé après chaque connexion réussie : permet au consumer de
  /// persister la session (URL + token) pour la reconnexion directe.
  void Function(String url, String token)? onSessionEstablished;

  /// Callback appelé quand le serveur rejette notre token (HTTP 401) : le
  /// consumer doit effacer la session persistée (token obsolète après un
  /// redémarrage du daemon avec un nouveau --auth-token) et re-tenter sans
  /// l'ancien token au lieu de marteler un 401 en boucle.
  void Function()? onAuthRejected;

  /// URL complète actuellement ciblée (réutilisée pour re-sauvegarde).
  String get targetUrl => _targetUrl;

  /// Token d'auth en vigueur (peut être vide).
  String? get authToken => _authToken;

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
    // Garde anti-boucle : si un connect() est déjà en vol (par ex. le
    // onAuthRejected qui relance pendant que _handleDisconnect a déjà
    // planifié un backoff), on ne lance pas un second connect() concurrent.
    if (_connecting) {
      return;
    }
    _connecting = true;
    statusNotifier.value = ConnectionStatus.connecting;
    _messageController ??= StreamController<dynamic>.broadcast();

    try {
      var finalUrl = _targetUrl;
      if (_authToken != null && _authToken!.isNotEmpty) {
        finalUrl += '${finalUrl.contains('?') ? '&' : '?'}token=$_authToken';
      }
      final uri = Uri.parse(finalUrl);

      WebSocket? socket;
      final connectFuture = WebSocket.connect(uri.toString());

      _connectTimeout?.cancel();
      _connectTimeout = Timer(const Duration(seconds: 15), () {
        connectFuture.then((s) => s.close());
      });

      try {
        socket = await connectFuture;
      } finally {
        _connectTimeout?.cancel();
        _connectTimeout = null;
      }

      if (_disposed) {
        socket.close();
        return;
      }

      // Si le socket a été fermé par le timeout (qui s'est déclenché pendant l'await)
      if (socket.readyState == WebSocket.closed) {
        throw TimeoutException('WebSocket connection timed out');
      }

      _socket = socket;
      _connecting = false;
      statusNotifier.value = ConnectionStatus.connected;
      _reconnectAttempts = 0;
      _stopRetryCountdown();
      retryInfo.value = const RetryInfo();
      _startKeepAlive();
      reconnectVersion.value++; // Étape 5 : signaler la (re)connexion
      if (kDebugMode) {
        print('[DaemonWS] Connected to $_targetUrl');
      }
      onSessionEstablished?.call(_targetUrl, _authToken ?? '');

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
      _connecting = false;
      if (kDebugMode) {
        print('[DaemonWS] Connection failed: $e');
      }
      // Token obsolète (redémarrage du daemon avec un nouveau --auth-token) :
      // le serveur répond 401 au handshake WS. On prévient le consumer pour
      // qu'il efface la session persistée — sinon on martèle le 401 en boucle
      // avec l'ancien token pendant ~30 s (backoff).
      if (e.toString().contains('401')) {
        // Statut `error` (≠ `disconnected`) : le retry timer planifié par
        // _handleDisconnect ne relancera pas connect() — seul onAuthRejected
        // (via le consumer) décide de la suite. Pas de boucle 401.
        statusNotifier.value = ConnectionStatus.error;
        onAuthRejected?.call();
        _socket?.close();
        _socket = null;
        _stopKeepAlive();
        return;
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
    _stopKeepAlive();
    _reconnectAttempts++;
    retryInfo.value = retryInfo.value.copyWith(attempt: _reconnectAttempts);
    _scheduleReconnect();
  }

  /// Ping JSON toutes les 20 s : le daemon lit la frame → reset du read
  /// deadline (pongWait) → connexion maintenue même en arrière-plan.
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
      final sock = _socket;
      if (sock == null ||
          statusNotifier.value != ConnectionStatus.connected) {
        _stopKeepAlive();
        return;
      }
      try {
        sock.add('{"type":"ping"}');
      } catch (_) {
        _stopKeepAlive();
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
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
    _connecting = false;
    if (_disposed) {
      _socket?.close();
      _socket = null;
      _connectTimeout?.cancel();
      _connectTimeout = null;
      return;
    }
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _stopRetryCountdown();
    _stopKeepAlive();
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
    _stopRetryCountdown();
    _stopKeepAlive();
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
