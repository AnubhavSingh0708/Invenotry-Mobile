import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EventService {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  final StreamController<void> _reloadController = StreamController<void>.broadcast();

  /// Listen to this stream from any widget to know when data changed on the server
  Stream<void> get onServerChange => _reloadController.stream;

  http.Client? _client;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  /// Start listening to server events
  void connect({required String serverUrl, required int userId, required String authKey}) async {
    disconnect(); // Close existing connection if any

    final uri = Uri.parse('$serverUrl/api/events?user_id=$userId&auth_key=$authKey');
    _client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;

        response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
            final trimmed = line.trim();
            // Ignore empty lines and comment/heartbeat lines starting with ':'
            if (trimmed.isEmpty || trimmed.startsWith(':')) return;

            // Broadcast reload signal for any 'data:' event regardless of type
            if (trimmed.startsWith('data:')) {
              _reloadController.add(null);
            }
          },
          onError: (_) => _scheduleReconnect(serverUrl, userId, authKey),
          onDone: () => _scheduleReconnect(serverUrl, userId, authKey),
          cancelOnError: true,
        );
      } else {
        _scheduleReconnect(serverUrl, userId, authKey);
      }
    } catch (_) {
      _scheduleReconnect(serverUrl, userId, authKey);
    }
  }

  void _scheduleReconnect(String serverUrl, int userId, String authKey) {
    if (!_isConnected) return;
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect(serverUrl: serverUrl, userId: userId, authKey: authKey);
    });
  }

  void disconnect() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _client?.close();
    _client = null;
  }
}