import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../domain/entities/authenticated_user.dart';
import '../domain/repositories/account_profile_repository.dart';

/// V1 personal-profile entry screen, deliberately separate from store settings.
/// Identity updates always act on the signed-in Firebase user, never on a UID
/// supplied by an administrator or an untrusted store member.
class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({
    required this.repository,
    required this.user,
    super.key,
  });

  final AccountProfileRepository repository;
  final AuthenticatedUser user;

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  AuthenticatedUser? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.repository != widget.repository) {
      ++_epoch;
      _profile = null;
      _name.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final expectedId = widget.user.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await widget.repository.getProfile(expectedUserId: expectedId);
    if (!mounted || epoch != _epoch || widget.user.id != expectedId) return;
    setState(() {
      _loading = false;
      if (result is Success<AuthenticatedUser>) {
        if (result.value.id == expectedId) {
          _profile = result.value;
          _name.text = result.value.displayName ?? '';
        } else {
          _error = 'تعذر التحقق من هوية الحساب الحالي.';
        }
      } else if (result is FailureResult<AuthenticatedUser>) {
        _error = result.failure.message;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final expectedId = widget.user.id;
    final epoch = _epoch;
    setState(() => _saving = true);
    try {
      final result = await widget.repository.updateDisplayName(
        expectedUserId: expectedId,
        displayName: _name.text,
      );
      if (!mounted || epoch != _epoch || expectedId != widget.user.id) return;
      if (result is Success<AuthenticatedUser> &&
          result.value.id == expectedId) {
        setState(() => _profile = result.value);
        _show('تم تحديث الاسم الشخصي.');
      } else if (result is FailureResult<AuthenticatedUser>) {
        _show(result.failure.message);
      } else {
        _show('تعذر التحقق من نتيجة تحديث الحساب.');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    ++_epoch;
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المعلومات الشخصية')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: CircleAvatar(
                                    radius: 44,
                                    child: Text(
                                      (_profile?.displayName?.isNotEmpty == true
                                              ? _profile!.displayName!
                                              : _profile?.email ?? '?')
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(fontSize: 30),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _name,
                                  maxLength: 80,
                                  enabled: !_saving,
                                  decoration: const InputDecoration(
                                    labelText: 'الاسم الشخصي',
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) =>
                                      (value ?? '').trim().isEmpty
                                          ? 'الاسم مطلوب.'
                                          : null,
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                  'البريد الإلكتروني: ${_profile?.email ?? ''}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _profile?.isEmailVerified == true
                                      ? 'البريد الإلكتروني مؤكد'
                                      : 'البريد الإلكتروني غير مؤكد',
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'البريد الإلكتروني مرتبط بتسجيل الدخول. '
                                  'لا يمكن تغييره من هذه الشاشة دون آلية تحقق '
                                  'من عنوان البريد الجديد.',
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: const Text('حفظ المعلومات الشخصية'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('تغيير كلمة المرور'),
                          subtitle: const Text(
                            'تحقق من الكلمة الحالية قبل حفظ كلمة جديدة.',
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChangeAccountPasswordPage(
                                  repository: widget.repository,
                                  expectedUserId: widget.user.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Mirrors the V1 old/new/confirm workflow without saving credentials.
class ChangeAccountPasswordPage extends StatefulWidget {
  const ChangeAccountPasswordPage({
    required this.repository,
    required this.expectedUserId,
    super.key,
  });

  final AccountProfileRepository repository;
  final String expectedUserId;

  @override
  State<ChangeAccountPasswordPage> createState() =>
      _ChangeAccountPasswordPageState();
}

class _ChangeAccountPasswordPageState extends State<ChangeAccountPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _obscured = <bool>[true, true, true];
  bool _saving = false;
  bool _success = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field({
    required int index,
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validate,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscured[index],
      enabled: !_saving && !_success,
      validator: validate,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _obscured[index] ? 'إظهار' : 'إخفاء',
          onPressed: () => setState(() {
            _obscured[index] = !_obscured[index];
          }),
          icon: Icon(
            _obscured[index] ? Icons.visibility_off : Icons.visibility,
          ),
        ),
      ),
    );
  }

  Future<void> _change() async {
    if (_saving || _success || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await widget.repository.changePassword(
        expectedUserId: widget.expectedUserId,
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      if (result is FailureResult<void>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.failure.message)),
        );
        return;
      }
      if (result is Success<void>) {
        _current.clear();
        _next.clear();
        _confirm.clear();
        setState(() => _success = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تغيير كلمة المرور')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    index: 0,
                    controller: _current,
                    label: 'كلمة المرور الحالية',
                    validate: (value) => (value ?? '').isEmpty
                        ? 'يرجى إدخال كلمة المرور الحالية.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    index: 1,
                    controller: _next,
                    label: 'كلمة المرور الجديدة',
                    validate: (value) {
                      if ((value ?? '').length < 8) {
                        return 'كلمة المرور الجديدة 8 أحرف على الأقل.';
                      }
                      if (value == _current.text) {
                        return 'اختر كلمة مختلفة عن كلمة المرور الحالية.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _field(
                    index: 2,
                    controller: _confirm,
                    label: 'تأكيد كلمة المرور الجديدة',
                    validate: (value) => value != _next.text
                        ? 'كلمتا المرور غير متطابقتين.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving || _success ? null : _change,
                    icon: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.password_outlined),
                    label: Text(_success
                        ? 'تم تغيير كلمة المرور'
                        : 'تغيير كلمة المرور'),
                  ),
                  if (_success)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('العودة إلى المعلومات الشخصية'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
