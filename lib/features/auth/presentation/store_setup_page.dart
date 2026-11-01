import 'package:flutter/material.dart';

import '../application/auth_session_controller.dart';

/// Explicit first-store/active-membership onboarding; no silent store takeover.
class StoreSetupPage extends StatefulWidget {
  const StoreSetupPage({required this.controller, super.key});

  final AuthSessionController controller;

  @override
  State<StoreSetupPage> createState() => _StoreSetupPageState();
}

class _StoreSetupPageState extends State<StoreSetupPage> {
  final _createKey = GlobalKey<FormState>();
  final _joinKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _storeIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعداد المتجر'),
          actions: [
            TextButton(
              onPressed: controller.isBusy ? null : controller.signOut,
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.storefront_outlined, size: 58),
                  const SizedBox(height: 12),
                  Text(
                    'مرحبًا بك في النظام المحاسبي',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'حسابك مسجّل، لكن لم يتم ربطه بمتجر نشط بعد. '
                    'أنشئ متجرًا خاصًا بك أو اختر متجرًا أضافك مالكه إليه.',
                    textAlign: TextAlign.center,
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _createKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('إنشاء متجر جديد',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'اسم المتجر',
                                prefixIcon: Icon(Icons.store),
                              ),
                              validator: (value) {
                                final length = (value ?? '').trim().length;
                                return length < 2 || length > 100
                                    ? 'أدخل اسمًا من 2 إلى 100 حرف'
                                    : null;
                              },
                              onFieldSubmitted: (_) => _createStore(),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed:
                                  controller.isBusy ? null : _createStore,
                              child: const Text('إنشاء المتجر والمتابعة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _joinKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('الدخول إلى متجر موجود',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            const Text(
                                'يجب أن يكون مالك المتجر قد أضاف حسابك كعضو نشط.'),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _storeIdController,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'معرّف المتجر',
                                prefixIcon: Icon(Icons.key_outlined),
                              ),
                              validator: (value) =>
                                  RegExp(r'^[a-zA-Z0-9_-]{1,128}$')
                                          .hasMatch((value ?? '').trim())
                                      ? null
                                      : 'أدخل معرّف متجر صالحًا',
                              onFieldSubmitted: (_) => _selectStore(),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton(
                              onPressed:
                                  controller.isBusy ? null : _selectStore,
                              child: const Text('التحقق من العضوية والدخول'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed:
                        controller.isBusy ? null : controller.reloadMembership,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة فحص عضويتي الحالية'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createStore() async {
    if (!(_createKey.currentState?.validate() ?? false)) return;
    await widget.controller.createStore(name: _nameController.text);
  }

  Future<void> _selectStore() async {
    if (!(_joinKey.currentState?.validate() ?? false)) return;
    await widget.controller.selectStore(
      storeId: _storeIdController.text.trim(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _storeIdController.dispose();
    super.dispose();
  }
}
