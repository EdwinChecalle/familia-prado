import 'package:flutter/material.dart';
import '../core/api.dart';
import 'home_screen.dart';
import 'turns_screen.dart';
import 'fund_screen.dart';
import 'appointments_screen.dart';
import 'members_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.api, required this.onLogout});
  final FamilyApi api;
  final VoidCallback onLogout;
  @override State<ShellScreen> createState() => _ShellScreenState();
}
class _ShellScreenState extends State<ShellScreen> {
  int tab = 0;
  final titles = ['Inicio', 'Semanas de comida', 'Aportes y gastos', 'Citas médicas', 'Familia'];
  @override Widget build(BuildContext context) {
    final screens = [HomeScreen(api: widget.api), TurnsScreen(api: widget.api),
      FundScreen(api: widget.api), AppointmentsScreen(api: widget.api), MembersScreen(api: widget.api, onLogout: widget.onLogout)];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab]), actions: [
        IconButton(tooltip: 'Salir de mi cuenta', icon: const Icon(Icons.logout), onPressed: () async {
          await widget.api.logout(); if(mounted) widget.onLogout();
        }),
      ]),
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
