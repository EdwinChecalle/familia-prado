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
  @override void initState() {
    super.initState();
    api.restore().then((ok) { if (mounted) setState(() { loggedIn = ok; loading = false; }); });
  }
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Familia Prado', debugShowCheckedModeBanner: false,
      theme: pradoTheme(),
      home: loading ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : loggedIn
              ? ShellScreen(api: api, onLogout: () => setState(() => loggedIn = false))
              : LoginScreen(api: api, onLogin: () => setState(() => loggedIn = true)),
    );
  }
}
