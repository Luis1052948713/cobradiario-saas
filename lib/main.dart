import 'package:flutter/material.dart';

import 'core/database/database_helper.dart';
import 'core/navigation/app_route_observer.dart';
import 'modules/auth/pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDatabaseConnected = await DatabaseHelper.instance.testConnection();
  debugPrint('SQLite conectado: $isDatabaseConnected');

  runApp(const CobraDiarioApp());
}

class CobraDiarioApp extends StatelessWidget {
  const CobraDiarioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Cobra Diario',

      theme: ThemeData(primarySwatch: Colors.green),

      navigatorObservers: [appRouteObserver],

      home: const LoginPage(),
    );
  }
}
