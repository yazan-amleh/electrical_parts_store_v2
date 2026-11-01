import 'package:electrical_parts_store_v2/app/theme/app_appearance_controller.dart';
import 'package:electrical_parts_store_v2/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('theme, accent and locale restore only for the same Firebase user',
      () async {
    final controller = AppAppearanceController();
    await controller.loadForUser('alice');
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.accent, AppearanceAccent.blue);
    expect(controller.language, AppLanguage.arabic);

    expect(await controller.setThemeMode(ThemeMode.dark), isTrue);
    expect(await controller.setAccent(AppearanceAccent.orange), isTrue);
    expect(await controller.setLanguage(AppLanguage.english), isTrue);

    await controller.loadForUser('bob');
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.accent, AppearanceAccent.blue);
    expect(controller.language, AppLanguage.arabic);

    await controller.loadForUser('alice');
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.accent, AppearanceAccent.orange);
    expect(controller.language, AppLanguage.english);

    await controller.loadForUser(null);
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.language, AppLanguage.arabic);
    expect(await controller.setThemeMode(ThemeMode.light), isFalse);
    controller.dispose();
  });

  test('unknown saved preference values return safe defaults', () async {
    SharedPreferences.setMockInitialValues({
      'v2:appearance:alice:mode': 'unsupported',
      'v2:appearance:alice:accent': 'missing',
      'v2:appearance:alice:language': 'unknown',
    });
    final controller = AppAppearanceController();
    await controller.loadForUser('alice');
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.accent, AppearanceAccent.blue);
    expect(controller.language, AppLanguage.arabic);
    controller.dispose();
  });

  testWidgets('theme change reaches MaterialApp and visible widgets',
      (tester) async {
    final controller = AppAppearanceController();
    await controller.loadForUser('alice');
    Widget app() => AppAppearanceScope(
          controller: controller,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => MaterialApp(
              theme: AppTheme.light(seed: controller.accent.seed),
              darkTheme: AppTheme.dark(seed: controller.accent.seed),
              themeMode: controller.themeMode,
              home: const Scaffold(body: Text('V2')),
            ),
          ),
        );
    await tester.pumpWidget(app());
    expect(
        Theme.of(tester.element(find.text('V2'))).brightness, Brightness.light);
    await controller.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.text('V2'))).brightness, Brightness.dark);
    await controller.setAccent(AppearanceAccent.teal);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('V2'))).colorScheme.primary,
      AppTheme.dark(seed: AppearanceAccent.teal.seed).colorScheme.primary,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
