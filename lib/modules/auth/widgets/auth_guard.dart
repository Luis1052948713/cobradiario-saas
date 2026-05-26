import 'package:flutter/material.dart';

import '../../../core/session/session_manager.dart';
import '../pages/login_page.dart';

class AuthGuard extends StatelessWidget {
  const AuthGuard({
    super.key,
    required this.child,
    this.allowedRoles,
  });

  final Widget child;
  final Set<String>? allowedRoles;

  @override
  Widget build(BuildContext context) {
    final profile = SessionManager.instance.perfilActual;
    if (profile == null) return const LoginPage();

    final roles = allowedRoles;
    if (roles != null && !roles.contains(profile.rol)) {
      return const _UnauthorizedPage();
    }

    return child;
  }
}

class _UnauthorizedPage extends StatelessWidget {
  const _UnauthorizedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso restringido')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No tienes permisos para ver esta pantalla.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
