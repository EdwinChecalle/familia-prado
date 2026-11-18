import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;
import 'api.dart';
import 'notification_ids.dart';

/// Los avisos locales ya programados pueden sonar sin abrir Flutter.
/// Nuevos eventos cuando la app está cerrada necesitan FCM/APNs.
class FamilyLocalReminders extends ChangeNotifier {
  FamilyLocalReminders(this.api, {this.onOpenRoute});
  final FamilyApi api;
  final void Function(String route)? onOpenRoute;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  bool ready = false;
  bool enabled = false;
  bool spokenSound = false;
  String? error;
  String _accountId = '';
  bool _scheduling = false;
  bool _rerun = false;
  bool _disposed = false;
  int pendingCount = 0;
  DateTime? nextReminder;

  static const _defaultChannel = AndroidNotificationChannel(
    'prado_general_v2', 'Avisos de Familia Prado',
    description: 'Recordatorios generales con sonido estándar',
    importance: Importance.high,
  );

  static const _voiceChannels = <AndroidNotificationChannel>[
    AndroidNotificationChannel('prado_cita_voz_v2', 'Citas con voz',
      description: 'Aviso hablado breve de cita (opcional)',
      importance: Importance.high, playSound: true,
      sound: RawResourceAndroidNotificationSound('prado_cita')),
    AndroidNotificationChannel('prado_turno_voz_v2', 'Turnos con voz',
      description: 'Aviso hablado breve de comidas (opcional)',
      importance: Importance.high, playSound: true,
      sound: RawResourceAndroidNotificationSound('prado_turno')),
    AndroidNotificationChannel('prado_colecta_voz_v2', 'Colectas con voz',
      description: 'Aviso hablado breve de colectas (opcional)',
      importance: Importance.high, playSound: true,
      sound: RawResourceAndroidNotificationSound('prado_colecta')),
    AndroidNotificationChannel('prado_aviso_voz_v2', 'Avisos con voz',
      description: 'Aviso hablado breve general (opcional)',
      importance: Importance.high, playSound: true,
      sound: RawResourceAndroidNotificationSound('prado_aviso')),
  ];

  static NotificationDetails details(String kind, {required bool spoken}) =>
      NotificationDetails(
    android: AndroidNotificationDetails(
      reminderKindChannel(kind, spoken: spoken),
      spoken ? 'Recordatorios hablados' : 'Avisos familiares',
      channelDescription: 'Avisos importantes de Familia Prado',
      importance: Importance.high, priority: Priority.high,
      playSound: true,
      sound: spoken ? RawResourceAndroidNotificationSound(reminderKindSound(kind)) : null,
    ),
    iOS: DarwinNotificationDetails(
      presentSound: true,
      sound: spoken ? '${reminderKindSound(kind)}.wav' : null,
    ),
  );

  Future<void> start() async {
    try {
      tzdb.initializeTimeZones();
      final profile = Map<String, dynamic>.from(
        await api.get('/api/auth/me') as Map);
      _accountId = '${profile['userId']}';
      _prefs = await SharedPreferences.getInstance();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false,
              requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) onOpenRoute?.call(r.payload!);
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_defaultChannel);
      for (final channel in _voiceChannels) {
        await android?.createNotificationChannel(channel);
      }
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse?.payload != null) {
        onOpenRoute?.call(launch!.notificationResponse!.payload!);
      }
      enabled = _prefs!.getBool('prado_local_reminders_$_accountId') ?? false;
      spokenSound = _prefs!.getBool('prado_spoken_sound_$_accountId') ?? false;
      ready = true;
      if (!_disposed) notifyListeners();
      if (enabled) await reschedule();
    } catch (e) {
      error = 'No se pudo iniciar notificaciones locales: $e';
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _permission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final a = await android?.requestNotificationsPermission();
    final b = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return a != false && b != false;
  }

  Future<void> setEnabled(bool value) async {
    if (!ready) return;
    if (value && !await _permission()) {
      error = 'Permite notificaciones de Familia Prado en Ajustes.';
      notifyListeners(); return;
    }
    enabled = value;
    await _prefs?.setBool('prado_local_reminders_$_accountId', value);
    if (value) await reschedule();
    else await _cancelOurPending();
    if (!_disposed) notifyListeners();
  }

  Future<void> setSpokenSound(bool value) async {
    if (!ready) return;
    spokenSound = value;
    await _prefs?.setBool('prado_spoken_sound_$_accountId', value);
    // The new channel ID is intentional: Android keeps channels' first sound.
    if (enabled) await reschedule();
    if (!_disposed) notifyListeners();
  }

  Future<void> clearForLogout() async {
    if (ready) await _cancelOurPending();
    enabled = false;
  }

  Future<void> _cancelOurPending() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if ((p.id >= 100000 && p.id < 800000) ||
          (p.id >= 10000 && p.id < 10050)) {
        await _plugin.cancel(id: p.id);
      }
    }
    pendingCount = 0;
    nextReminder = null;
  }

  Future<void> testNotification() async {
    if (!ready) throw StateError('Notificaciones todavía no disponibles');
    if (!await _permission()) {
      throw StateError('Activa los permisos de notificación en Android/iOS.');
    }
    await _plugin.show(
      id: 900001,
      title: 'Prueba de Familia Prado',
      body: 'Aviso de prueba, sin información médica privada.',
      notificationDetails: details('APPOINTMENT', spoken: spokenSound),
      payload: 'avisos',
    );
  }

  Future<void> reschedule() async {
    if (!enabled || !ready || _disposed || api.token == null) return;
    if (_scheduling) { _rerun = true; return; }
    _scheduling = true;
    try {
      final me = Map<String, dynamic>.from(
        await api.get('/api/auth/me') as Map);
      if (me['memberId'] == null) {
        await _cancelOurPending();
        error = null;
        return;
      }
      final member = '${me['memberId']}';
      final results = await Future.wait<dynamic>([
        api.get('/api/turns?from=${isoDate(firstMonday(peruToday()))}&weeks=10'),
        api.get('/api/appointments'),
      ]);
      // No cancelaciones hasta tener los datos completos del servidor.
      final lima = tz.getLocation('America/Lima');
      final now = tz.TZDateTime.now(lima);
      final desired = <int, ({tz.TZDateTime at, String title, String body,
          String kind, String route})>{};

      void add(String key, tz.TZDateTime at, String title, String body,
          String kind, String route) {
        if (!at.isAfter(now)) return;
        final id = notificationId('$_accountId:$key');
        desired[id] = (at: at, title: title, body: body,
            kind: kind, route: route);
      }

      for (final raw in results[0] as List) {
        final w = Map<String, dynamic>.from(raw as Map);
        if ('${w['memberId']}' != member || w['configured'] != true) continue;
        final date = DateTime.parse('${w['monday']}');
        final monday = tz.TZDateTime(lima, date.year, date.month, date.day, 7);
        add('week:${w['monday']}:eve',
          monday.subtract(const Duration(hours: 13)), 'Turno mañana',
          'Mañana te corresponde preparar las comidas de Papá Isidro.',
          'TURN', 'comidas');
        add('week:${w['monday']}:start', monday,
          'Tu semana de comidas', 'Esta semana organizas las comidas de Papá Isidro.',
          'TURN', 'comidas');
      }
      for (final raw in results[1] as List) {
        final a = Map<String, dynamic>.from(raw as Map);
        if ('${a['responsibleMemberId']}' != member ||
            !['PLANNED','CONFIRMED'].contains(a['status'])) continue;
        final at = tz.TZDateTime.from(
          DateTime.parse('${a['appointmentAt']}'), lima);
        add('appointment:${a['id']}:24h',
          at.subtract(const Duration(hours: 24)), 'Cita familiar mañana',
          'Revisa la cita para acompañar a Papá Isidro.', 'APPOINTMENT', 'citas');
        add('appointment:${a['id']}:3h',
          at.subtract(const Duration(hours: 3)), 'Cita familiar próxima',
          'Prepara el traslado de Papá Isidro.', 'APPOINTMENT', 'citas');
      }

      // Sustituye SÓLO avisos de Familia Prado; nunca cancela apps ajenas.
      // Reprograma de forma determinista después de leer ambos recursos.
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if ((item.id >= 100000 && item.id < 800000 &&
             !desired.containsKey(item.id)) ||
            (item.id >= 10000 && item.id < 10050)) {
          await _plugin.cancel(id: item.id);
        }
      }
      final existing = pending.map((x) => x.id).toSet();
      for (final entry in desired.entries) {
        // Reemite la programación con el mismo ID para fecha/voz actualizadas.
        final v = entry.value;
        if (existing.contains(entry.key)) await _plugin.cancel(id: entry.key);
        await _plugin.zonedSchedule(
          id: entry.key, title: v.title, body: v.body,
          scheduledDate: v.at,
          notificationDetails: details(v.kind, spoken: spokenSound),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: v.route,
        );
      }
      pendingCount = desired.length;
      nextReminder = desired.values.isEmpty ? null :
        desired.values.map((x) => x.at).reduce((a,b) => a.isBefore(b) ? a : b);
      error = null;
    } catch (e) {
      error = 'No se completó la programación: $e';
    } finally {
      _scheduling = false;
      if (!_disposed) notifyListeners();
      if (_rerun && !_disposed) {
        _rerun = false;
        scheduleMicrotask(reschedule);
      }
    }
  }

  @override void dispose() { _disposed = true; super.dispose(); }
}
