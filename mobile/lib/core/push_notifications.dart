import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'api.dart';
import 'local_reminders.dart';

/// FCM funciona con la app minimizada o terminada (salvo restricciones del SO).
/// Las claves Dart define son identificadores de Firebase, NO credenciales de admin.
/// No se inicia FCM sin una configuración real del proyecto Firebase.
class FamilyPushNotifications extends ChangeNotifier {
  FamilyPushNotifications(this.api, this.localReminders,
      {this.onOpenRoute, this.onNewMessage});
  final FamilyApi api;
  final FamilyLocalReminders localReminders;
  final void Function(String route)? onOpenRoute;
  final VoidCallback? onNewMessage;

  // FlutterFire generó firebase_options.dart para las plataformas vinculadas.
  // Por ahora configuramos Android. Añadiremos iOS cuando se registre esa app.
  bool get configured => !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;
  bool enabled = false;
  bool working = false;
  String? error;
  String? _accountId;
  SharedPreferences? _prefs;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _started = false;
  bool _disposed = false;
  String? _token;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final me = Map<String,dynamic>.from(await api.get('/api/auth/me') as Map);
      _accountId = '${me['userId']}';
      _prefs = await SharedPreferences.getInstance();
      enabled = _prefs!.getBool('prado_push_$_accountId') ?? false;
      if (enabled && configured) await _activate(requestPermission: false);
      if (enabled && !configured) {
        error = 'Para los avisos nuevos con la app cerrada, configura Firebase.';
      }
    } catch (e) { error = 'No se pudo consultar la preferencia push: $e'; }
    if (!_disposed) notifyListeners();
  }

  FirebaseOptions get _options => DefaultFirebaseOptions.currentPlatform;

  Future<void> _activate({required bool requestPermission}) async {
    if (!configured) throw StateError('Firebase todavía no está configurado.');
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: _options);
    final messaging = FirebaseMessaging.instance;
    if (requestPermission) {
      final p = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (p.authorizationStatus != AuthorizationStatus.authorized &&
          p.authorizationStatus != AuthorizationStatus.provisional) {
        throw StateError('No se concedió permiso de notificaciones.');
      }
    }
    _token = await messaging.getToken();
    if (_token == null) throw StateError('Firebase no entregó token de este dispositivo.');
    await _register(_token!);
    _refreshSubscription ??= messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      if (enabled && api.token != null) _register(newToken);
    });
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(_open);
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      onNewMessage?.call();
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) _open(initial);
  }

  void _open(RemoteMessage message) {
    final route = message.data['route'];
    if (route == 'citas' || route == 'comidas' || route == 'caja' || route == 'avisos') {
      onOpenRoute?.call(route!);
    }
    onNewMessage?.call();
  }

  Future<void> _register(String token) async {
    await api.post('/api/push/devices', {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
      'spokenSound': localReminders.spokenSound,
    });
  }

  Future<void> syncVoicePreference() async {
    if (enabled && _token != null && api.token != null) {
      try { await _register(_token!); }
      catch (e) { error = 'No se actualizó el sonido push: $e'; notifyListeners(); }
    }
  }

  Future<void> setEnabled(bool value) async {
    if (working || _accountId == null) return;
    working = true;
    error = null;
    notifyListeners();
    try {
      if (value) {
        await _activate(requestPermission: true);
      } else if (_token != null) {
        await api.post('/api/push/devices/remove', {'token': _token!});
      }
      enabled = value;
      await _prefs?.setBool('prado_push_$_accountId', enabled);
    } catch (e) { error = 'No se pudieron configurar avisos push: $e'; }
    finally { working = false; if (!_disposed) notifyListeners(); }
  }

  Future<void> testPush() async {
    if (!enabled || !configured) throw StateError('Activa las notificaciones push primero.');
    await api.post('/api/push/test', {});
  }

  Future<void> clearForLogout() async {
    if (_token != null && api.token != null) {
      try { await api.post('/api/push/devices/remove', {'token': _token!}); }
      catch (_) { /* El token vence en el servidor si no hay conexión. */ }
    }
    _token = null;
    enabled = false;
    await _refreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }

  @override void dispose() {
    _disposed = true;
    _refreshSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    super.dispose();
  }
}
