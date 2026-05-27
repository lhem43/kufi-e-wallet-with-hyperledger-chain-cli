import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_code_boxes.dart';

/// Sub-screen: Thông tin tài khoản — edit display name, view phone/email, change PIN.
class AccountInfoScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const AccountInfoScreen({super.key, this.onProfileUpdated});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();

  bool _loading = true;
  bool _saving = false;
  String _phone = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final result = await _userService.getMyProfile();
      Map<String, dynamic>? profile;
      if (result['success'] == true && result['profile'] is Map) {
        profile = Map<String, dynamic>.from(result['profile'] as Map);
      } else {
        profile = await _authService.getCurrentUser();
      }
      if (!mounted) return;
      setState(() {
        _displayNameController.text = '${profile?['displayName'] ?? ''}';
        _phone = '${profile?['phone'] ?? ''}';
        _email = '${profile?['email'] ?? ''}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await _userService.updateMyProfile(
      displayName: _displayNameController.text.trim(),
      phone: _phone,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      widget.onProfileUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã cập nhật thông tin cá nhân',
              en: 'Profile updated successfully',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['message'] ?? AppLocalizations.pick(vi: 'Lỗi cập nhật', en: 'Update failed')}',
          ),
        ),
      );
    }
  }

  Future<void> _changePIN() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangePinDialog(authService: _authService),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã thay đổi PIN thành công',
              en: 'PIN changed successfully',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Thông tin tài khoản', en: 'Account information')),
      ),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Personal info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(
                                  vi: 'Thông tin cá nhân',
                                  en: 'Personal information',
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _displayNameController,
                                decoration: InputDecoration(
                                  labelText: tr(
                                    vi: 'Tên hiển thị',
                                    en: 'Display name',
                                  ),
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  final name = (value ?? '').trim();
                                  if (name.isEmpty) {
                                    return tr(
                                      vi: 'Vui lòng nhập tên hiển thị',
                                      en: 'Please enter display name',
                                    );
                                  }
                                  if (name.length < 2) {
                                    return tr(
                                      vi: 'Tối thiểu 2 ký tự',
                                      en: 'Minimum 2 characters',
                                    );
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: _phone,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: tr(
                                    vi: 'Số điện thoại',
                                    en: 'Phone number',
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.phone_iphone_outlined,
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.lock_outline,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: _email,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: tr(vi: 'Email', en: 'Email'),
                                  prefixIcon: const Icon(Icons.alternate_email),
                                  suffixIcon: const Icon(
                                    Icons.lock_outline,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: GradientButton(
                                  label: tr(
                                    vi: 'Lưu thay đổi',
                                    en: 'Save changes',
                                  ),
                                  icon: Icons.save_rounded,
                                  loading: _saving,
                                  onPressed: _saving ? null : _saveProfile,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Security card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(vi: 'Bảo mật', en: 'Security'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _SettingTile(
                              icon: Icons.pin_outlined,
                              title: tr(vi: 'Đổi mã PIN', en: 'Change PIN'),
                              subtitle: tr(
                                vi: 'Thay đổi PIN 6 số bảo mật',
                                en: 'Update your 6-digit security PIN',
                              ),
                              titleColor: titleColor,
                              subtitleColor: subColor,
                              iconBg: isDark
                                  ? const Color(0xFF2A3344)
                                  : AppColors.violet100,
                              iconColor: isDark
                                  ? const Color(0xFFAEC0D9)
                                  : AppColors.violet600,
                              onTap: _changePIN,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;
  final Color iconBg;
  final Color iconColor;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
    required this.iconBg,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: subtitleColor, size: 22),
          ],
        ),
      ),
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  final AuthService authService;
  const _ChangePinDialog({required this.authService});

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _currentPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final current = _currentPinCtrl.text.trim();
    final newPin = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(current)) {
      setState(
        () => _error = AppLocalizations.pick(
          vi: 'PIN hiện tại phải gồm 6 chữ số.',
          en: 'Current PIN must be 6 digits.',
        ),
      );
      return;
    }
    final valid = await widget.authService.verifyServerPin(current);
    if (!mounted) return;
    if (!valid) {
      setState(
        () => _error = AppLocalizations.pick(
          vi: 'PIN hiện tại không đúng.',
          en: 'Current PIN is incorrect.',
        ),
      );
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(newPin)) {
      setState(
        () => _error = AppLocalizations.pick(
          vi: 'PIN mới phải gồm 6 chữ số.',
          en: 'New PIN must be 6 digits.',
        ),
      );
      return;
    }
    if (confirm != newPin) {
      setState(
        () => _error = AppLocalizations.pick(
          vi: 'Xác nhận PIN không khớp.',
          en: 'PIN confirmation does not match.',
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.authService.setServerPin(pin: newPin);
      if (!mounted) return;
      if (result['success'] == true) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _error =
              result['message']?.toString() ??
              AppLocalizations.pick(
                vi: 'Không thể lưu PIN.',
                en: 'Unable to save PIN.',
              );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppLocalizations.pick(
          vi: 'Không thể lưu PIN.',
          en: 'Unable to save PIN.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(vi: 'Đổi mã PIN', en: 'Change PIN'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'BeVietnamPro',
                ),
              ),
              const SizedBox(height: 14),
              PinCodeBoxes(
                controller: _currentPinCtrl,
                enabled: !_saving,
                autofocus: true,
                label: tr(vi: 'PIN hiện tại', en: 'Current PIN'),
                errorText: _error,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _newPinCtrl,
                enabled: !_saving,
                label: tr(vi: 'PIN mới', en: 'New PIN'),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _confirmPinCtrl,
                enabled: !_saving,
                label: tr(vi: 'Xác nhận PIN mới', en: 'Confirm new PIN'),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onCompleted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(tr(vi: 'Hủy', en: 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(tr(vi: 'Xác nhận', en: 'Confirm')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
