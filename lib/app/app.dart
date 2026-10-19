import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_gate.dart';
import 'app_dependencies.dart';
import 'theme/app_theme.dart';

class V2App extends StatelessWidget {
  const V2App({
    required this.dependencies,
    super.key,
  });

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'متجر القطع الكهربائية V2',
      theme: AppTheme.light(),
      home: AuthGate(dependencies: dependencies),
    );
  }
}
