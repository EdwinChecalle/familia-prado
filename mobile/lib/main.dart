import 'package:flutter/material.dart';
import 'core/api.dart';
import 'ui/prado_design.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamiliaPradoApp());
}

class FamiliaPradoApp extends StatefulWidget {
  const FamiliaPradoApp({super.key});
  @override State<FamiliaPradoApp> createState() => _FamiliaPradoAppState();
}

class _FamiliaPradoAppState extends State<FamiliaPradoApp> {
  final api = FamilyApi();
  bool loading = true;
  bool loggedIn = false;
  bool restoreFailed = false;
  @override void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (mounted) setState(() { loading = true; restoreFailed = false; });
    try {
      final ok = await api.restore();
      if (mounted) setState(() { loggedIn = ok; loading = false; });
    } catch (_) {
      if (mounted) setState(() { restoreFailed = true; loading = false; });
    }
  }

  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Familia Prado', debugShowCheckedModeBanner: false,
      theme: pradoTheme(),
      home: loading ? const Scaffold(body: Center(child: Padding(
          padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(), SizedBox(height: 20),
            Text('Conectando con Familia Prado…', textAlign: TextAlign.center),
            SizedBox(height: 8), Text('El servidor puede tardar en despertar.', textAlign: TextAlign.center),
          ]))))
          : restoreFailed ? Scaffold(body: Center(child: Padding(
            padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 52), const SizedBox(height: 16),
              const Text('No pudimos comprobar tu sesión', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Tu acceso se conserva. Comprueba Internet y vuelve a intentar.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: _restoreSession, child: const Text('Reintentar')),
            ]))))
          : loggedIn
              ? ShellScreen(api: api, onLogout: () => setState(() => loggedIn = false))
              : LoginScreen(api: api, onLogin: () => setState(() => loggedIn = true)),
    );
  }
}
