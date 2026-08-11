import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

    // Auto-reconnect after 3 seconds if disconnected
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (statusNotifier.value == ConnectionStatus.disconnected) {
        connect();
      }
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    statusNotifier.value = ConnectionStatus.disconnected;
  }

  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
  }
}
