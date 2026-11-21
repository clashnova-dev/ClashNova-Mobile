import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _base;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _base = TextEditingController(text: AppScope.read(context).baseUrl);
  }

  @override
  void dispose() {
    _base.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login(AppState state) async {
    setState(() => _submitting = true);
    await state.login(_base.text, _email.text, _password.text);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(28),
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.plane, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('ClashNova',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
              const SizedBox(height: 10),
              Text(t('login.subtitle'), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 28),
              TextField(controller: _base, decoration: InputDecoration(labelText: t('login.baseUrl'))),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t('login.email')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: t('login.password')),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : () => _login(state),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.brand,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(t('login.signIn')),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => state.enterLocal(_base.text),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(t('login.useLocal')),
              ),
              const SizedBox(height: 16),
              Text(state.message,
                  style: TextStyle(color: AppColors.muted, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
