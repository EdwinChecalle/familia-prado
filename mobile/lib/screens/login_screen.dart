import 'package:flutter/material.dart';
import '../core/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onLogin});
  final FamilyApi api;
  final VoidCallback onLogin;
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool saving = false;
  @override void dispose() { email.dispose();password.dispose();super.dispose(); }
  Future<void> submit() async {
    if (saving) return;
    setState(() { saving = true; error = null; });
    try { await widget.api.login(email.text.trim(), password.text); if(mounted) widget.onLogin(); }
    catch (e) { if(mounted) setState(() => error = e.toString()); }
    finally { if(mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(padding: const EdgeInsets.all(26), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.family_restroom, size: 70, color: Color(0xFF2F5678)),
          const SizedBox(height: 18),
          Text('Familia Prado', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
          const Text('Siempre juntos', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 30),
          const Text('Ingresa con tu cuenta familiar', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Correo electrónico')),
          const SizedBox(height: 14),
          TextField(controller: password, obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'), onSubmitted: (_) => submit()),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          FilledButton(onPressed: saving ? null : submit, child: Padding(padding: const EdgeInsets.all(12),
            child: Text(saving ? 'Ingresando...' : 'Entrar', style: const TextStyle(fontSize: 18)))),
          const SizedBox(height: 14),
          const Text('Si no tienes cuenta, solicita acceso al familiar administrador.',
            textAlign: TextAlign.center),
        ],
      )),
    ))),
  );
}
