import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_member.dart';
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
            const SizedBox(height: 12),
            if (_members.isEmpty)
              const Text('لا يوجد أعضاء مسجلون.')
            else
              for (final member in _members) _memberTile(context, member),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(BuildContext context, StoreMember member) {
    final canEditMember = _canManage && member.role != StoreRole.owner;
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
                  initialValue: member.role == StoreRole.owner
                      ? null
                      : member.role,
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
              if (canEditMember)
                OutlinedButton.icon(
                  onPressed: () => _saveMember(member),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
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

  Future<void> _saveMember(StoreMember member) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    final result = await repository.updateMember(
      context: _context,
      member: member,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
      return;
    }
    _showMessage('تم تحديث صلاحيات العضو.');
    await _load();
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
