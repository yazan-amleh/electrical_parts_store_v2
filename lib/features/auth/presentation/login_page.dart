import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/auth_session_controller.dart';
import 'register_page.dart';
import 'reset_password_page.dart';
import 'v1_auth_visuals.dart';

/// V1 login composition using V2 authentication; no V1 Firebase/controller code.
class LoginPage extends StatefulWidget {
  const LoginPage({required this.controller, super.key});
  final AuthSessionController controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _rememberKey = 'auth_remember_email';
  static const _emailKey = 'auth_saved_email';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = preferences.getBool(_rememberKey) ?? false;
    setState(() {
      _rememberMe = enabled;
      if (enabled) {
        _emailController.text = preferences.getString(_emailKey) ?? '';
      }
    });
  }

  Future<void> _submit() async {
    if (widget.controller.isBusy ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Unlike V1, never persist the password to SharedPreferences.
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    await preferences.setBool(_rememberKey, _rememberMe);
    if (_rememberMe) {
      await preferences.setString(_emailKey, _emailController.text.trim());
    } else {
      await preferences.remove(_emailKey);
    }
    if (!mounted) return;
    await widget.controller.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.isBusy;
        return V1AuthLayout(
          variant: AuthDecorationVariant.login,
          title: 'مرحباً بك مجدداً',
          subtitle: 'سجّل دخولك لإدارة المتجر والحسابات والمخزون',
          content: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                  decoration: V1AuthControls.decoration(
                    label: 'البريد الإلكتروني',
                    hint: 'example@example.com',
                    icon: Icons.email_rounded,
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
                    if (!email.contains('@')) {
                      return 'الرجاء إدخال بريد إلكتروني صحيح';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  textDirection: TextDirection.ltr,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                  decoration: V1AuthControls.decoration(
                    label: 'كلمة المرور',
                    hint: '••••••••',
                    icon: Icons.lock_rounded,
                    suffix: IconButton(
                      tooltip: _obscurePassword
                          ? 'إظهار كلمة المرور'
                          : 'إخفاء كلمة المرور',
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.blue.shade700,
                        size: 22,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة المرور';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                // V1's paired controls wrap on compact screens instead of
                // overflowing the right edge in Arabic RTL.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    InkWell(
                      onTap: busy
                          ? null
                          : () => setState(() {
                                _rememberMe = !_rememberMe;
                              }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: Colors.blue.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: busy
                                  ? null
                                  : (value) => setState(() {
                                        _rememberMe = value ?? false;
                                      }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'تذكرني',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ResetPasswordPage(
                                    controller: widget.controller,
                                  ),
                                ),
                              ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue.shade700,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(10, 10),
                      ),
                      child: const Text(
                        'نسيت كلمة المرور؟',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                V1AuthControls.primaryButton(
                  label: 'تسجيل الدخول',
                  loading: busy,
                  onPressed: _submit,
                ),
                V1AuthControls.errorBanner(widget.controller.errorMessage),
              ],
            ),
          ),
          footer: Column(
            children: [
              Text(
                'للمساعدة أو الاستفسار، يرجى التواصل مع مدير النظام',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RegisterPage(
                              controller: widget.controller,
                            ),
                          ),
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
