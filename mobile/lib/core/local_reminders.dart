import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;
import 'api.dart';

/// Opt-in LOCAL reminders previously scheduled while this account was online.
/// A new unexpected event while the app is closed needs remote push (FCM/APNs).
class FamilyLocalReminders extends ChangeNotifier {
  FamilyLocalReminders(this.api);
  final FamilyApi api;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  bool ready = false;
  bool enabled = false;
  String? error;
  String _accountId = '';
  bool _scheduling = false;
  bool _disposed = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'familia_prado_reminders', 'Recordatorios de Familia Prado',
      channelDescription: 'Turnos y citas familiares previamente programados',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(presentSound: true),
  );

  Future<void> start() async {
    try {
      tzdb.initializeTimeZones();
      final profile = Map<String,dynamic>.from(await api.get('/api/auth/me') as Map);
      _accountId = '${profile['userId']}';
      _prefs = await SharedPreferences.getInstance();
      await _plugin.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false,
          requestBadgePermission: false, requestSoundPermission: false),
      ));
      enabled = _prefs!.getBool('prado_local_reminders_$_accountId') ?? false;
      // Always drop reminders from another account on a shared family phone.
      await _plugin.cancelAllPendingNotifications();
      ready = true;
      if (!_disposed) notifyListeners();
      if (enabled) await reschedule();
    } catch (_) {
      error = 'No se pudo preparar las notificaciones locales.';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!ready) return;
    if (value) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();
      final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      if (androidGranted == false || iosGranted == false) {
        error = 'Android/iOS no concedió permiso para mostrar notificaciones.';
        if (!_disposed) notifyListeners();
        return;
      }
    }
    enabled = value;
    await _prefs?.setBool('prado_local_reminders_$_accountId',value);
    if (!value) await _plugin.cancelAllPendingNotifications();
    else await reschedule();
    if (!_disposed) notifyListeners();
  }

  Future<void> clearForLogout() async {
    // Prevent alerts for a previous user's personal schedule on this phone.
    if (ready) await _plugin.cancelAllPendingNotifications();
    enabled = false;
  }

  Future<void> reschedule() async {
    if (!enabled || !ready || _scheduling || _disposed || api.token == null) return;
    _scheduling = true;
    try {
      final me=Map<String,dynamic>.from(await api.get('/api/auth/me') as Map);
      final member='${me['memberId']}';
      // The administrator has no personal schedule in this first implementation.
      if (me['memberId'] == null) {
        await _plugin.cancelAllPendingNotifications();
        return;
      }
      final results=await Future.wait<dynamic>([
        api.get('/api/turns?from=${isoDate(firstMonday(peruToday()))}&weeks=9'),
        api.get('/api/appointments'),
      ]);
      await _plugin.cancelAllPendingNotifications();
      final lima=tz.getLocation('America/Lima');
      final now=tz.TZDateTime.now(lima);
      var id=10000;
      Future<void> schedule(tz.TZDateTime at,String title,String body) async {
        if (id>=10050 || !at.isAfter(now)) return;
        await _plugin.zonedSchedule(
          id:id++, title:title, body:body, scheduledDate:at,
          notificationDetails:_details,
          // Avoid requesting privileged exact alarm access.
          androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      for(final value in results[0] as List) {
        final week=Map<String,dynamic>.from(value as Map);
        if ('${week['memberId']}'!=member || week['configured']!=true) continue;
        final date=DateTime.parse('${week['monday']}');
        final monday=tz.TZDateTime(lima,date.year,date.month,date.day,7);
        await schedule(monday.subtract(const Duration(hours:13)), 'Turno familiar',
          'Mañana te corresponde la comida de Papá Isidro.');
        await schedule(monday,'Tu semana de comidas',
          'Esta semana te corresponde organizar las comidas de Papá Isidro.');
      }
      for(final value in results[1] as List) {
        final appointment=Map<String,dynamic>.from(value as Map);
        if ('${appointment['responsibleMemberId']}'!=member ||
            !['PLANNED','CONFIRMED'].contains(appointment['status'])) continue;
        final at=tz.TZDateTime.from(DateTime.parse('${appointment['appointmentAt']}'),lima);
        await schedule(at.subtract(const Duration(hours:24)), 'Cita familiar mañana',
          'Tienes una cita de acompañamiento programada para Papá Isidro.');
        await schedule(at.subtract(const Duration(hours:3)), 'Cita familiar próxima',
          'Revisa la hora y el traslado de Papá Isidro en Familia Prado.');
      }
      error=null;
    } catch (_) { error='No se pudieron programar todos los avisos. Revisa la conexión.'; }
    finally { _scheduling=false; if (!_disposed) notifyListeners(); }
  }

  @override void dispose() {
    _disposed = true;
    super.dispose();
  }
}
