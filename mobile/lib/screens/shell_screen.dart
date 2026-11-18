import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/family_alerts.dart';
import '../core/local_reminders.dart';
import 'alerts_screen.dart';
import 'home_screen.dart';
import 'turns_screen.dart';
import 'fund_screen.dart';
import 'appointments_screen.dart';
import 'members_screen.dart';
import 'care_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.api, required this.onLogout});
  final FamilyApi api;
  final VoidCallback onLogout;
  @override State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int tab = 0;
  String displayName = 'Familiar';
  String role = '';
  late final LiveUpdates live;
  late final FamilyAlerts alerts;
  late final FamilyLocalReminders reminders;
  final titles = const ['Inicio', 'Semanas de comida', 'Aportes y gastos', 'Citas médicas', 'Familia'];

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    live = LiveUpdates(widget.api);
    alerts = FamilyAlerts(widget.api);
    reminders = FamilyLocalReminders(widget.api);
    live.addListener(_onLive);
    live.start();
    alerts.start();
    reminders.start();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.api.get('/api/profile') as Map<String, dynamic>;
      if (mounted) setState(() {
        displayName = profile['displayName'] as String? ?? 'Familiar';
        role = profile['role'] as String? ?? '';
      });
    } catch (_) { /* Navigation remains usable if profile cannot load. */ }
  }

  void _onLive() {
    alerts.refresh();
    if (const {'turns','appointments','all'}.contains(live.lastTopic)) {
      reminders.reschedule();
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      live.start();
      alerts.foreground(true);
      reminders.reschedule();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      live.pause();
      alerts.foreground(false);
    }
  }

  void _openCare() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => CareScreen(api: widget.api),
  ));

  void _openAlerts() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => AlertsScreen(alerts: alerts, reminders: reminders),
  ));

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    live.removeListener(_onLive);
    live.dispose();
    alerts.dispose();
    reminders.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    final screens = [
      HomeScreen(api: widget.api, displayName: displayName, role: role,
        onNavigate: (index) => setState(() => tab = index),
        onAlerts: _openAlerts, onCare: _openCare, alerts: alerts, updates: live),
      TurnsScreen(api: widget.api, updates: live),
      FundScreen(api: widget.api, updates: live),
      AppointmentsScreen(api: widget.api, updates: live),
      MembersScreen(api: widget.api, onLogout: widget.onLogout),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Text(titles[tab], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Cuenta: $displayName', style: const TextStyle(fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        actions: [
          IconButton(tooltip: 'Cuidado de Papá Isidro',icon: const Icon(Icons.medical_services_outlined),
              onPressed: _openCare),
          AnimatedBuilder(animation: alerts, builder: (context, _) => Badge(
            isLabelVisible: alerts.unreadCount > 0,
            label: Text('${alerts.unreadCount}'),
            child: IconButton(tooltip: 'Mis avisos', icon: const Icon(Icons.notifications_outlined),
              onPressed: _openAlerts),
          )),
          IconButton(tooltip: 'Salir de mi cuenta', icon: const Icon(Icons.logout), onPressed: () async {
            await reminders.clearForLogout();
            // App-private temporary document copies must not survive account switch.
            try {
              final dir = await getTemporaryDirectory();
              for (final file in dir.listSync()) {
                if (file is File && file.uri.pathSegments.last.startsWith('prado-')) {
                  await file.delete();
                }
              }
            } catch (_) { /* OS may own cache; don't block logout. */ }
            await widget.api.logout();
            if (mounted) widget.onLogout();
          }),
        ],
      ),
      body: screens[tab],
      bottomNavigationBar: NavigationBar(
        height: 78, selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.restaurant_outlined), label: 'Comidas'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Caja'),
          NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Citas'),
          NavigationDestination(icon: Icon(Icons.family_restroom_outlined), label: 'Familia'),
        ],
      ),
    );
  }
}
