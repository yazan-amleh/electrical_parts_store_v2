import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppearanceAccent {
  blue('الأزرق', Color(0xFF1D4ED8)),
  orange('البرتقالي', Color(0xFFEA580C)),
  teal('التركوازي', Color(0xFF0F766E)),
  purple('البنفسجي', Color(0xFF7C3AED));

  const AppearanceAccent(this.arabicName, this.seed);

  final String arabicName;
  final Color seed;
}

enum AppLanguage {
  arabic('العربية', Locale('ar')),
  english('English', Locale('en'));

  const AppLanguage(this.label, this.locale);

  final String label;
  final Locale locale;
}

/// Device preferences are isolated by Firebase UID. No theme or language
/// document is written into business/accounting Firestore collections.
class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController();

  static const _keyPrefix = 'v2:appearance:';
  String? _userId;
  int _revision = 0;
  ThemeMode _themeMode = ThemeMode.system;
  AppearanceAccent _accent = AppearanceAccent.blue;
  AppLanguage _language = AppLanguage.arabic;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  AppearanceAccent get accent => _accent;
  AppLanguage get language => _language;
  bool get isLoaded => _loaded;
  String? get userId => _userId;

  static T _orDefault<T>(Iterable<T> values, String? raw, T fallback) {
    for (final value in values) {
      if ((value as Enum).name == raw) return value;
    }
    return fallback;
  }

  Future<void> loadForUser(String? userId) async {
    final normalized = userId?.trim();
    final nextId = normalized == null || normalized.isEmpty ? null : normalized;
    if (_userId == nextId && _revision > 0) return;
    _userId = nextId;
    final revision = ++_revision;
    _themeMode = ThemeMode.system;
    _accent = AppearanceAccent.blue;
    _language = AppLanguage.arabic;
    _loaded = nextId == null;
    notifyListeners();

    if (nextId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _revision || _userId != nextId) return;
      _themeMode = _orDefault(
        ThemeMode.values,
        prefs.getString('$_keyPrefix$nextId:mode'),
        ThemeMode.system,
      );
      _accent = _orDefault(
        AppearanceAccent.values,
        prefs.getString('$_keyPrefix$nextId:accent'),
        AppearanceAccent.blue,
      );
      _language = _orDefault(
        AppLanguage.values,
        prefs.getString('$_keyPrefix$nextId:language'),
        AppLanguage.arabic,
      );
    } catch (_) {
      // The app remains usable with safe defaults if local storage is denied.
    }
    if (revision == _revision && _userId == nextId) {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<bool> setThemeMode(ThemeMode mode) async {
    if (!_loaded || _userId == null) return false;
    _themeMode = mode;
    notifyListeners();
    return _save('mode', mode.name);
  }

  Future<bool> setAccent(AppearanceAccent accent) async {
    if (!_loaded || _userId == null) return false;
    _accent = accent;
    notifyListeners();
    return _save('accent', accent.name);
  }

  Future<bool> setLanguage(AppLanguage language) async {
    if (!_loaded || _userId == null) return false;
    _language = language;
    notifyListeners();
    return _save('language', language.name);
  }

  Future<bool> _save(String field, String value) async {
    final uid = _userId;
    final revision = _revision;
    if (uid == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != _userId || revision != _revision) return false;
      return prefs.setString('$_keyPrefix$uid:$field', value);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    ++_revision;
    super.dispose();
  }
}

class AppAppearanceScope extends InheritedNotifier<AppAppearanceController> {
  const AppAppearanceScope({
    required AppAppearanceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppAppearanceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppAppearanceScope>()
      ?.notifier;
}
