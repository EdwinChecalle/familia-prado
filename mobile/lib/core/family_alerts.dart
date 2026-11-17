import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// In-app reminders. This does NOT replace background push notifications.
class FamilyAlerts extends ChangeNotifier {
  FamilyAlerts(this.api);
  final FamilyApi api;
  final FlutterTts _speech = FlutterTts();
  SharedPreferences? _prefs;
  String _accountId = '';
  Timer? _poll;
  bool _running = false;
  bool _foreground = true;
  bool _loading = false;
  bool _needsRefresh = false;
  bool _disposed = false;
  bool voiceEnabled = false; // Privacy-first: silent by default.
  List<Map<String, dynamic>> items = [];
  String? error;

  int get unreadCount => items.where((x) => x['read'] != true).length;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final profile = await api.get('/api/auth/me') as Map<String, dynamic>;
      _accountId = profile['userId'] as String;
      _prefs = await SharedPreferences.getInstance();
      voiceEnabled = _prefs!.getBool('familia_prado_voice_$_accountId') ?? false;
      if (!_disposed) notifyListeners();
    } catch (_) { /* Text alerts remain available even when preferences fail. */ }
    if (_disposed) return;
    await refresh();
    if (!_disposed) _poll = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  Future<void> setVoiceEnabled(bool value) async {
    voiceEnabled = value;
    if (!value) await _speech.stop();
    if (_accountId.isNotEmpty) {
      await _prefs?.setBool('familia_prado_voice_$_accountId', value);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> speak(String text) async {
    // Keep the message short. No diagnoses, specialties or numbers from receipts.
    if (text.trim().isEmpty) return;
    await _speech.stop();
    await _speech.setLanguage('es-PE');
    await _speech.setSpeechRate(0.46);
    await _speech.setVolume(0.85);
    await _speech.speak(text);
  }

  Future<void> refresh() async {
    if (_disposed || !_foreground) return;
    if (_loading) {
      _needsRefresh = true;
      return;
    }
    _loading = true;
    try {
      final response = await api.get('/api/alerts') as List;
      if (_disposed) return;
      items = response.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      error = null;
      notifyListeners();
      if (_foreground && voiceEnabled && _prefs != null && _accountId.isNotEmpty) {
        // Speak at most one NEW important reminder; never repeat on every refresh.
        for (final alert in items) {
          if (alert['read'] == true || alert['voiceRecommended'] != true) continue;
          final key = 'familia_prado_spoken_${_accountId}_${alert['id']}';
          if (_prefs!.getBool(key) == true) continue;
          await _prefs!.setBool(key, true);
          try { await speak(alert['voiceText'] as String? ?? ''); }
          catch (_) { /* A missing system voice must not break the screen. */ }
          break;
        }
      }
    } catch (_) {
      error = 'No fue posible actualizar los avisos.';
      if (!_disposed) notifyListeners();
    } finally {
      _loading = false;
      if (_needsRefresh && !_disposed && _foreground) {
        _needsRefresh = false;
        scheduleMicrotask(refresh);
      }
    }
  }

  Future<void> markRead(String id) async {
    await api.post('/api/alerts/$id/read', {});
    for (final alert in items) {
      if (alert['id'] == id) alert['read'] = true;
    }
    if (!_disposed) notifyListeners();
  }

  void foreground(bool value) {
    _foreground = value;
    if (value) { refresh(); }
    else { _speech.stop(); }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _speech.stop();
    super.dispose();
  }
}
