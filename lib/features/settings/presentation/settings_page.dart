import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../domain/entities/store_member.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/store_profile.dart';
import '../domain/repositories/settings_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final SettingsRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  StoreProfile? _profile;
  List<StoreMember> _members = const <StoreMember>[];
  late final TextEditingController _nameController;
  late final TextEditingController _currencyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  bool _isLoading = true;
  bool _isSavingProfile = false;
  bool _isAddingMember = false;
  final Set<String> _savingMemberIds = <String>{};
  String _memberSearch = '';
  bool _showInactiveMembers = true;
  String? _errorMessage;

  bool get _canManage => widget.membership.role.canManageStore;

  StoreContext get _context {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _currencyController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع الإعدادات غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null || _profile == null) {
      return _buildErrorState();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildProfileCard(context),
            const SizedBox(height: 12),
            _buildMembersCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.settings_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إعدادات المتجر والصلاحيات',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _canManage
                        ? 'إدارة معلومات المتجر وأعضاءه من صلاحية المالك أو المدير.'
                        : 'هذه الصفحة للعرض فقط حسب صلاحيتك الحالية.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'بيانات المتجر',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              enabled: _canManage && !_isSavingProfile,
              decoration: const InputDecoration(
                labelText: 'اسم المتجر',
                prefixIcon: Icon(Icons.store_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _currencyController,
              enabled: _canManage && !_isSavingProfile,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'العملة',
                hintText: 'ILS',
                prefixIcon: Icon(Icons.currency_exchange_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              enabled: _canManage && !_isSavingProfile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'الهاتف',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              enabled: _canManage && !_isSavingProfile,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'العنوان',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_canManage) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _isSavingProfile ? null : _saveProfile,
                icon: _isSavingProfile
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSavingProfile ? 'جارٍ الحفظ...' : 'حفظ بيانات المتجر',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أعضاء المتجر',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'يمكن للمالك أو المدير تعديل دور العضو وتفعيله. لا يمكن نقل '
              'ملكية المتجر من هذه الشاشة.',
            ),
            if (_canManage) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _isAddingMember ? null : _addMember,
                  icon: _isAddingMember
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _isAddingMember ? 'جارٍ الإضافة...' : 'إضافة مستخدم موجود',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'البحث عن مستخدم',
                hintText: 'الاسم أو البريد الإلكتروني أو UID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _memberSearch = value.trim().toLowerCase());
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار المستخدمين غير النشطين'),
              value: _showInactiveMembers,
              onChanged: (value) {
                setState(() => _showInactiveMembers = value);
              },
            ),
            Text(
              'إجمالي الأعضاء: ${_members.length} • '
              'النشطون: ${_members.where((member) => member.isActive).length}',
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const Text('لا يوجد أعضاء مسجلون.')
            else if (_visibleMembers.isEmpty)
              const Text('لا يوجد أعضاء مطابقون للبحث أو الفلتر.')
            else
              for (final member in _visibleMembers)
                _memberTile(context, member),
          ],
        ),
      ),
    );
  }

  List<StoreMember> get _visibleMembers {
    return _members.where((member) {
      if (!_showInactiveMembers && !member.isActive) return false;
      if (_memberSearch.isEmpty) return true;
      return member.userId.toLowerCase().contains(_memberSearch) ||
          (member.displayName ?? '').toLowerCase().contains(_memberSearch) ||
          (member.email ?? '').toLowerCase().contains(_memberSearch);
    }).toList();
  }

  Widget _memberTile(BuildContext context, StoreMember member) {
    final isSaving = _savingMemberIds.contains(member.userId);
    final canEditMember =
        _canManage && member.role != StoreRole.owner && !isSaving;
    final roleItems = StoreRole.values
        .where((role) => role != StoreRole.owner)
        .map(
          (role) => DropdownMenuItem<StoreRole>(
            value: role,
            child: Text(_roleLabel(role)),
          ),
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CircleAvatar(
                child: Text(
                  member.userId.isEmpty ? '?' : member.userId[0].toUpperCase(),
                ),
              ),
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName ?? member.userId,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (member.email != null) Text(member.email!),
                    if (member.displayName != null)
                      Text(
                        member.userId,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<StoreRole>(
                  value: member.role == StoreRole.owner ? null : member.role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: member.role == StoreRole.owner
                      ? const [
                          DropdownMenuItem<StoreRole>(
                            value: null,
                            child: Text('مالك'),
                          ),
                        ]
                      : roleItems,
                  onChanged: canEditMember
                      ? (role) {
                          if (role == null) {
                            return;
                          }
                          _replaceMember(member.copyWith(role: role));
                        }
                      : null,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('نشط'),
                  Switch(
                    value: member.isActive,
                    onChanged: canEditMember
                        ? (value) {
                            _replaceMember(
                              member.copyWith(isActive: value),
                            );
                          }
                        : null,
                  ),
                ],
              ),
              if (_canManage && member.role != StoreRole.owner)
                OutlinedButton.icon(
                  onPressed: isSaving ? null : () => _saveMember(member),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'تعذر تحميل الإعدادات.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final profileResult = await repository.getStoreProfile(context: _context);
    if (!mounted) {
      return;
    }
    if (profileResult is FailureResult<StoreProfile>) {
      setState(() {
        _isLoading = false;
        _errorMessage = profileResult.failure.message;
      });
      return;
    }

    final membersResult = await repository.getMembers(context: _context);
    if (!mounted) {
      return;
    }
    if (membersResult is FailureResult<List<StoreMember>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = membersResult.failure.message;
      });
      return;
    }

    final profile = (profileResult as Success<StoreProfile>).value;
    _nameController.text = profile.name;
    _currencyController.text = profile.currency;
    _phoneController.text = profile.phone;
    _addressController.text = profile.address;
    setState(() {
      _profile = profile;
      _members = (membersResult as Success<List<StoreMember>>).value;
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    final repository = widget.repository;
    final profile = _profile;
    if (repository == null || profile == null) {
      return;
    }

    final name = _nameController.text.trim();
    final currency = _currencyController.text.trim().toUpperCase();
    if (name.isEmpty || currency.isEmpty) {
      _showMessage('اسم المتجر والعملة مطلوبان.');
      return;
    }

    setState(() => _isSavingProfile = true);
    final result = await repository.updateStoreProfile(
      context: _context,
      profile: StoreProfile(
        id: profile.id,
        name: name,
        currency: currency,
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSavingProfile = false);
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
      return;
    }
    _showMessage('تم حفظ بيانات المتجر.');
  }

  Future<void> _addMember() async {
    final repository = widget.repository;
    if (repository == null || !_canManage || _isAddingMember) {
      return;
    }

    final draft = await showDialog<_NewMemberDraft>(
      context: context,
      builder: (context) => const _AddMemberDialog(),
    );
    if (draft == null || !mounted || _isAddingMember) {
      return;
    }

    if (_members.any((member) => member.userId == draft.userId)) {
      _showMessage('هذا المستخدم مرتبط بالفعل بالمتجر.');
      return;
    }

    setState(() => _isAddingMember = true);
    try {
      final result = await repository.addMember(
        context: _context,
        member: StoreMember(
          userId: draft.userId,
          role: draft.role,
          isActive: true,
          displayName: draft.displayName,
          email: draft.email,
        ),
      );
      if (!mounted) return;
      if (result is FailureResult<void>) {
        _showMessage(result.failure.message);
        return;
      }
      await _load();
      if (mounted) _showMessage('تمت إضافة المستخدم إلى المتجر.');
    } catch (error) {
      if (mounted) _showMessage('تعذر إضافة المستخدم: $error');
    } finally {
      if (mounted) setState(() => _isAddingMember = false);
    }
  }

  Future<void> _saveMember(StoreMember member) async {
    final repository = widget.repository;
    if (repository == null ||
        !_canManage ||
        member.role == StoreRole.owner ||
        _savingMemberIds.contains(member.userId)) {
      return;
    }

    setState(() => _savingMemberIds.add(member.userId));
    try {
      final result = await repository.updateMember(
        context: _context,
        member: member,
      );
      if (!mounted) return;
      if (result is FailureResult<void>) {
        await _load();
        if (mounted) _showMessage(result.failure.message);
        return;
      }
      await _load();
      if (mounted) _showMessage('تم تحديث صلاحيات العضو.');
    } catch (error) {
      if (mounted) {
        await _load();
        if (mounted) _showMessage('تعذر تحديث صلاحيات العضو: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _savingMemberIds.remove(member.userId));
      }
    }
  }

  void _replaceMember(StoreMember replacement) {
    setState(() {
      _members = [
        for (final member in _members)
          member.userId == replacement.userId ? replacement : member,
      ];
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _roleLabel(StoreRole role) {
    switch (role) {
      case StoreRole.owner:
        return 'مالك';
      case StoreRole.admin:
        return 'مدير';
      case StoreRole.accountant:
        return 'محاسب';
      case StoreRole.sales:
        return 'مبيعات';
      case StoreRole.warehouse:
        return 'مستودع';
      case StoreRole.viewer:
        return 'مشاهد';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}

class _NewMemberDraft {
  const _NewMemberDraft({
    required this.userId,
    required this.role,
    this.displayName,
    this.email,
  });

  final String userId;
  final StoreRole role;
  final String? displayName;
  final String? email;
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _userIdController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  StoreRole _role = StoreRole.viewer;

  @override
  void dispose() {
    _userIdController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty || userId.contains('/')) {
      return;
    }
    Navigator.of(context).pop(
      _NewMemberDraft(
        userId: userId,
        role: _role,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إضافة مستخدم للمتجر'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _userIdController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'UID المستخدم في Firebase',
                    hintText: 'مثال: FqDRlUu2gLdPuawD5A9pVd57DI23',
                    prefixIcon: Icon(Icons.fingerprint_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (اختياري)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم العرض (اختياري)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<StoreRole>(
                  value: _role,
                  decoration: const InputDecoration(
                    labelText: 'الدور داخل المتجر',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  items: StoreRole.values
                      .where((role) => role != StoreRole.owner)
                      .map(
                        (role) => DropdownMenuItem<StoreRole>(
                          value: role,
                          child: Text(_settingsRoleLabel(role)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (role) {
                    if (role != null) {
                      setState(() => _role = role);
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'يجب أن يكون المستخدم موجوداً مسبقاً في Firebase Authentication. '
                  'هذه الشاشة تربطه بالمتجر ولا تنشئ حساب تسجيل دخول جديداً.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

String _settingsRoleLabel(StoreRole role) {
  switch (role) {
    case StoreRole.owner:
      return 'مالك';
    case StoreRole.admin:
      return 'مدير';
    case StoreRole.accountant:
      return 'محاسب';
    case StoreRole.sales:
      return 'مبيعات';
    case StoreRole.warehouse:
      return 'مستودع';
    case StoreRole.viewer:
      return 'مشاهد';
  }
}
