import 'package:flutter/material.dart';
import 'core/api.dart';
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
    const ink = Color(0xFF172F4B);
    return MaterialApp(
      title: 'Familia Prado', debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFAF3),
        colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: const Color(0xFFFFFAF3)),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFFFFAF3), foregroundColor: ink),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5DFD5)))),
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 16), bodyLarge: TextStyle(fontSize: 17),
          titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        visualDensity: VisualDensity.standard,
      ),
      home: loading ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : loggedIn
              ? ShellScreen(api: api, onLogout: () => setState(() => loggedIn = false))
              : LoginScreen(api: api, onLogin: () => setState(() => loggedIn = true)),
    );
  }
}
