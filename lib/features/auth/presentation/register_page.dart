import 'package:flutter/material.dart';

import '../application/auth_session_controller.dart';
import 'v1_auth_visuals.dart';

/// V1 registration visuals; V2 alone owns Firebase Auth and store provisioning.
class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.controller, super.key});
  final AuthSessionController controller;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  Future<void> _register() async {
    if (widget.controller.isBusy ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.controller.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
    );
    if (!mounted) return;
    // Hand off to the AuthGate's actual store setup, without granting V1
    // superAdmin role or writing to legacy users/collections.
    if (widget.controller.user != null &&
        (widget.controller.status == AuthSessionStatus.storeSetupRequired ||
            widget.controller.status == AuthSessionStatus.ready)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.isBusy;
        return V1AuthLayout(
          variant: AuthDecorationVariant.register,
          title: 'إنشاء حساب جديد',
          subtitle: 'أدخل بياناتك لإنشاء حساب جديد في نظام المتجر',
          onBack: () => Navigator.of(context).pop(),
          content: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                  decoration: V1AuthControls.decoration(
                    label: 'الاسم',
                    hint: 'الاسم الكامل',
                    icon: Icons.person,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'الرجاء إدخال الاسم';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
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
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
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
                        size: 22,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة المرور';
                    }
                    if (value.length < 6) {
                      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmation,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                  decoration: V1AuthControls.decoration(
                    label: 'تأكيد كلمة المرور',
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      tooltip: _obscureConfirmation
                          ? 'إظهار كلمة المرور'
                          : 'إخفاء كلمة المرور',
                      onPressed: () => setState(
                        () => _obscureConfirmation = !_obscureConfirmation,
                      ),
                      icon: Icon(
                        _obscureConfirmation
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 22,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء تأكيد كلمة المرور';
                    }
                    if (value != _passwordController.text) {
                      return 'كلمتا المرور غير متطابقتين';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _register(),
                ),
                const SizedBox(height: 24),
                V1AuthControls.primaryButton(
                  label: 'إنشاء حساب',
                  loading: busy,
                  onPressed: _register,
                ),
                V1AuthControls.errorBanner(widget.controller.errorMessage),
              ],
            ),
          ),
          footer: TextButton.icon(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.login,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            label: Text(
              'لديك حساب بالفعل؟ تسجيل الدخول',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
