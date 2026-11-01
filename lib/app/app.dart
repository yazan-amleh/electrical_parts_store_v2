import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/auth/presentation/auth_gate.dart';
import 'app_dependencies.dart';
import 'theme/app_appearance_controller.dart';
import 'theme/app_theme.dart';

class V2App extends StatefulWidget {
  const V2App({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<V2App> createState() => _V2AppState();
}

class _V2AppState extends State<V2App> {
  final AppAppearanceController _appearance = AppAppearanceController();

  @override
  void initState() {
    super.initState();
    widget.dependencies.authSession?.addListener(_onSessionChange);
    _onSessionChange();
  }

  void _onSessionChange() {
    _appearance.loadForUser(widget.dependencies.authSession?.user?.id);
  }

  @override
  void didUpdateWidget(covariant V2App oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies.authSession != widget.dependencies.authSession) {
      oldWidget.dependencies.authSession?.removeListener(_onSessionChange);
      widget.dependencies.authSession?.addListener(_onSessionChange);
      _onSessionChange();
    }
  }

  @override
  void dispose() {
    widget.dependencies.authSession?.removeListener(_onSessionChange);
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppAppearanceScope(
      controller: _appearance,
      child: AnimatedBuilder(
        animation: _appearance,
        builder: (context, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'متجر القطع الكهربائية V2',
          theme: AppTheme.light(seed: _appearance.accent.seed),
          darkTheme: AppTheme.dark(seed: _appearance.accent.seed),
          themeMode: _appearance.themeMode,
          locale: _appearance.language.locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: child,
        ),
        child: AuthGate(dependencies: widget.dependencies),
      ),
    );
  }
}
