import 'package:flutter/material.dart';
import '../core/family_alerts.dart';
import '../core/local_reminders.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.alerts, required this.reminders});
  final FamilyAlerts alerts;
  final FamilyLocalReminders reminders;

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
              if (reminders.enabled) TextButton.icon(
                onPressed:reminders.reschedule,
                icon:const Icon(Icons.sync),label:const Text('Actualizar recordatorios del sistema')),
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
          const Text('Los avisos locales programados pueden aparecer con la app cerrada, según permisos del sistema. Avisos NUEVOS cuando la app está cerrada requieren FCM/APNs y todavía no están habilitados.'),
        ],
      ));
    }),
  );
}
