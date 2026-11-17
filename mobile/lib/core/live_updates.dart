import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api.dart';

/// SSE invalidation notices: no family content travels in this stream.
/// Each screen fetches authorized data over its existing REST endpoints.
class LiveUpdates extends ChangeNotifier {
  LiveUpdates(this.api);
  final FamilyApi api;
  bool _active = false;
  bool _disposed = false;
  http.Client? _client;
  Timer? _retry;
  String lastTopic = 'all';

  void _event(String topic) {
    if (_disposed) return;
    lastTopic = topic;
    notifyListeners();
  }

  void start() {
    if (_active || _disposed || api.token == null) return;
    // Bearer tokens must never be sent over cleartext in release builds.
    if (kReleaseMode && Uri.parse(apiBase).scheme != 'https') return;
    _active = true;
    _event('all'); // Reconcile any updates missed while the app was away.
    _connect();
  }

  Future<void> _connect() async {
    if (!_active || _disposed) return;
    final client = http.Client();
    _client = client;
    try {
      final request = http.Request('GET', Uri.parse('$apiBase/api/events'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Authorization'] = 'Bearer ${api.token}';
      final response = await client.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        pause();
        return;
      }
      if (response.statusCode != 200) throw StateError('SSE ${response.statusCode}');
      _event('all');
      String eventName = '';
      String payload = '';
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!_active || _disposed) break;
        if (line.startsWith('event:')) eventName = line.substring(6).trim();
        if (line.startsWith('data:')) payload += line.substring(5).trim();
        if (line.isEmpty) {
          if (eventName == 'changed' &&
              const {'turns', 'fund', 'appointments', 'family'}.contains(payload)) {
            _event(payload);
          }
          eventName = '';
          payload = '';
        }
      }
    } catch (_) {
      // A dropped connection is expected on network change; retry while foregrounded.
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (_active && !_disposed) _retry = Timer(const Duration(seconds: 4), _connect);
    }
  }

  void pause() {
    _active = false;
    _retry?.cancel();
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    pause();
    _disposed = true;
    super.dispose();
  }
}
