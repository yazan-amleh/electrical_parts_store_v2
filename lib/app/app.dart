import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import '../features/shell/presentation/app_shell_page.dart';

class V2App extends StatelessWidget {
  const V2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'متجر القطع الكهربائية V2',
      theme: AppTheme.light(),
      home: const AppShellPage(),
    );
  }
}
