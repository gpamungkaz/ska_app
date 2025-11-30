import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minimumDisplayDuration = Duration(milliseconds: 600);
  late final DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final session = await AuthStorage.readSession();

    final elapsed = DateTime.now().difference(_startTime);
    if (elapsed < _minimumDisplayDuration) {
      await Future<void>.delayed(_minimumDisplayDuration - elapsed);
    }

    if (!mounted) return;

    if (session == null) {
      _goToLogin();
      return;
    }

    final role = _parseRole(session.role);
    if (role == null) {
      await AuthStorage.clearSession();
      if (!mounted) return;
      _goToLogin();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          role: role,
          authToken: session.token,
          userName: session.name,
        ),
      ),
    );
  }

  UserRole? _parseRole(String? role) {
    switch (role?.toLowerCase()) {
      case 'marketing':
        return UserRole.marketing;
      case 'owner':
        return UserRole.owner;
      default:
        return null;
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Image.asset(
                'assets/icons/icon.png',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Memuat SKA App',
              style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple,
                  ) ??
                  const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple,
                  ),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 5),
            ),
            const SizedBox(height: 8),
            Text(
              'Menyiapkan dashboard Anda...',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
