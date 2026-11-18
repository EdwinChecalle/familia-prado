import 'package:flutter/material.dart';
import '../core/family_alerts.dart';
import '../core/local_reminders.dart';
import '../core/push_notifications.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.alerts, required this.reminders, required this.push});
  final FamilyAlerts alerts;
  final FamilyLocalReminders reminders;
  final FamilyPushNotifications push;

  IconData _icon(String category) => switch (category) {
    'TURN' => Icons.restaurant_outlined,
    'APPOINTMENT' => Icons.event_outlined,
    'COLLECTION' || 'FUND' => Icons.account_balance_wallet_outlined,
    _ => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos para mí')),
    body: AnimatedBuilder(animation: alerts, builder: (context, _) {
      return RefreshIndicator(onRefresh: alerts.refresh, child: ListView(
        padding: const EdgeInsets.all(16), children: [
          Card(child: SwitchListTile.adaptive(
            title: const Text('Leer avisos importantes en voz alta'),
            subtitle: const Text('Desactivado por defecto. Solo mientras la app está abierta. Puedes escuchar cada aviso manualmente.'),
            value: alerts.voiceEnabled,
            onChanged: alerts.setVoiceEnabled,
            secondary: const Icon(Icons.record_voice_over_outlined),
          )),
          const SizedBox(height: 12),
          AnimatedBuilder(animation: reminders, builder:(context, _) => Card(
            child: Column(children: [
              SwitchListTile.adaptive(
                title:const Text('Notificaciones del sistema (app cerrada)'),
                subtitle:const Text('Optativo. Programa turnos y citas ya conocidos; '
                  'sin nombres de medicamentos ni datos clínicos.'),
                secondary:const Icon(Icons.notifications_outlined),
                value:reminders.enabled,
                onChanged:reminders.ready ? (value) async {
                  await reminders.setEnabled(value);
                  if (context.mounted && reminders.error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content:Text(reminders.error!)));
                  }
                } : null,
              ),
              if (reminders.ready) SwitchListTile.adaptive(
                title: const Text('Audio hablado con la app cerrada'),
                subtitle: const Text('Opcional: frase breve grabada. Se respeta el modo silencio del celular. No lee datos clínicos.'),
                value: reminders.spokenSound,
                onChanged: (value) async {
                  await reminders.setSpokenSound(value);
                  await push.syncVoicePreference();
                },
                secondary: const Icon(Icons.volume_up_outlined),
              ),
              if (reminders.ready) ListTile(
                title: const Text('Recordatorios preparados'),
                subtitle: Text('${reminders.pendingCount} pendientes'
                  '${reminders.nextReminder == null ? '' : ' · Próximo: ${reminders.nextReminder!.toLocal()}'}'),
              ),
              if (reminders.enabled) TextButton.icon(
                onPressed: reminders.reschedule,
                icon: const Icon(Icons.sync), label: const Text('Actualizar recordatorios del sistema')),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await reminders.testNotification();
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')));
                  }
                },
                icon: const Icon(Icons.notification_add_outlined),
                label: const Text('Probar notificación del teléfono'),
              ),
              if (reminders.error != null) Padding(
                padding: const EdgeInsets.all(12), child: Text(reminders.error!)),
            ]),
          )),
          const SizedBox(height: 12),
          AnimatedBuilder(animation: push, builder: (context, _) => Card(
            child: Column(children: [
              SwitchListTile.adaptive(
                title: const Text('Avisos nuevos con la app cerrada (Firebase)'),
                subtitle: Text(push.configured
                  ? 'Recibe avisos del servidor de citas nuevas, colectas y cambios.'
                  : 'Falta vincular Firebase. Los avisos ya programados siguen disponibles.'),
                value: push.enabled,
                onChanged: push.configured && !push.working ? push.setEnabled : null,
                secondary: const Icon(Icons.cloud_outlined),
              ),
              if (push.enabled) TextButton.icon(
                onPressed: () async {
                  try { await push.testPush(); }
                  catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')));
                  }
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Enviar prueba desde Spring Boot'),
              ),
              if (push.error != null) Padding(
                padding: const EdgeInsets.all(12), child: Text(push.error!)),
            ]),
          )),
          const SizedBox(height: 12),
          if (alerts.error != null) Text(alerts.error!),
          if (alerts.items.isEmpty) const Card(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Por ahora no tienes avisos pendientes. Desliza hacia abajo para comprobarlo.'),
          )),
          for (final alert in alerts.items)
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_icon('${alert['category']}'), color: const Color(0xFF2F5678)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${alert['title']}', style: Theme.of(context).textTheme.titleMedium)),
                  if (alert['read'] != true)
                    const Icon(Icons.circle, size: 9, color: Color(0xFFA34E37)),
                ]),
                const SizedBox(height: 8),
                Text('${alert['message']}'),
                const SizedBox(height: 8),
                Wrap(spacing: 10, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try { await alerts.speak('${alert['voiceText']}'); }
                      catch (_) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No hay voz disponible en este dispositivo.')));
                      }
                    },
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Escuchar aviso'),
                  ),
                  if (alert['read'] != true)
                    TextButton.icon(
                      onPressed: () async {
                        try { await alerts.markRead('${alert['id']}'); }
                        catch (_) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No se pudo marcar el aviso como leído.')));
                        }
                      },
                      icon: const Icon(Icons.done),
                      label: const Text('Marcar como leído'),
                    ),
                ]),
              ],
            ))),
          const SizedBox(height: 12),
          const Text('Los recordatorios guardados funcionan como avisos locales. Los avisos nuevos con la app cerrada necesitan Firebase configurado, permisos y conexión a internet.'),
        ],
      ));
    }),
  );
}
