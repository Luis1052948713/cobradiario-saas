import 'package:flutter/material.dart';

import '../../dashboard/pages/dashboard_page.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = const AuthService();
  late Future<bool> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _restoreSession();
  }

  Future<bool> _restoreSession() async {
    final profile = await _authService.restoreSession();
    return profile != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AuthSplash();
        }

        if (snapshot.hasError) {
          return LoginPage(initialError: snapshot.error.toString());
        }

        return snapshot.data == true ? const DashboardPage() : const LoginPage();
      },
    );
  }
}

class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 72,
                color: Colors.green,
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Validando sesion...'),
            ],
          ),
        ),
      ),
    );
  }
}
