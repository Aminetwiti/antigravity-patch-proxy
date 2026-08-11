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

  /// Étape 5 : incrémenté à chaque reconnexion réussie. Les consommateurs
  /// (DaemonApi → replay outbox, UI → re-sync) écoutent ce notifier pour
  /// savoir quand l'état distant doit être rejoué.
  final ValueNotifier<int> reconnectVersion = ValueNotifier(0);

  Stream<dynamic> get stream =>
      _messageController?.stream ?? const Stream.empty();

  Future<void> connect({String? customUrl, String? authToken}) async {
    if (customUrl != null && customUrl.isNotEmpty) {
      _targetUrl = customUrl;
    }
    if (authToken != null) {
      _authToken = authToken;
    }

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
      _socket = await WebSocket.connect(uri.toString()).timeout(
        const Duration(seconds: 5),
      );

      statusNotifier.value = ConnectionStatus.connected;
      _reconnectAttempts = 0;
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
    statusNotifier.value = ConnectionStatus.disconnected;
    _socket?.close();
    _socket = null;
    _reconnectAttempts++;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_manualDisconnect) return;
    final delay = backoffDelay(_reconnectAttempts);
    // Jitter ±1 s : évite la rafale synchrone quand plusieurs appareils
    // retombent en même temps (le host redémarre).
    final jitter = Random().nextInt(2000) - 1000;
    _reconnectTimer = Timer(
      delay + Duration(milliseconds: jitter),
      () {
        if (statusNotifier.value == ConnectionStatus.disconnected) {
          connect();
        }
      },
    );
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    statusNotifier.value = ConnectionStatus.disconnected;
  }

  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
    reconnectVersion.dispose();
  }
}
