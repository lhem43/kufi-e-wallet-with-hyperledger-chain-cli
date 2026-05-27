import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../utils/provider_branding.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import 'linked_bank_otp_screen.dart';

class LinkedBankSetupScreen extends StatefulWidget {
  const LinkedBankSetupScreen({super.key});

  @override
  State<LinkedBankSetupScreen> createState() => _LinkedBankSetupScreenState();
}

class _LinkedBankSetupScreenState extends State<LinkedBankSetupScreen> {
  final _accountController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _notify = true;
  bool _defaultSource = true;
  bool _submitting = false;
  int _selectedProviderIndex = 0;

  @override
  void dispose() {
    _accountController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  _ProviderPreset get _selectedProvider =>
      _providerPresets[_selectedProviderIndex.clamp(
        0,
        _providerPresets.length - 1,
      )];

  String _providerHint(_ProviderPreset preset) {
    switch (preset.code) {
      case 'MOMO':
        return AppLocalizations.pick(
          vi: 'Ví điện tử MoMo, xác nhận OTP và cấp quyền giao dịch.',
          en: 'MoMo e-wallet with OTP verification and transaction authorization.',
        );
      case 'ZALOPAY':
        return AppLocalizations.pick(
          vi: 'Kết nối ZaloPay với bước xác thực người dùng.',
          en: 'Connect ZaloPay with user verification flow.',
        );
      case 'VNPAY':
        return AppLocalizations.pick(
          vi: 'Liên kết cổng thanh toán VNPAY theo luồng xác thực.',
          en: 'Link VNPAY payment gateway with verification flow.',
        );
      case 'TECHCOMBANK':
        return AppLocalizations.pick(
          vi: 'Liên kết tài khoản Techcombank với xác thực OTP.',
          en: 'Link Techcombank account with OTP verification.',
        );
      case 'VIETCOMBANK':
        return AppLocalizations.pick(
          vi: 'Liên kết tài khoản Vietcombank để nạp/rút nhanh.',
          en: 'Link Vietcombank account for faster top-up/withdrawal.',
        );
      default:
        return preset.hint;
    }
  }

  String _providerAccountLabel(_ProviderPreset preset) {
    switch (preset.code) {
      case 'MOMO':
        return AppLocalizations.pick(
          vi: 'Số điện thoại MoMo',
          en: 'MoMo phone number',
        );
      case 'ZALOPAY':
        return AppLocalizations.pick(
          vi: 'Số ví ZaloPay',
          en: 'ZaloPay wallet ID',
        );
      case 'VNPAY':
        return AppLocalizations.pick(
          vi: 'Mã merchant / số tài khoản',
          en: 'Merchant ID / account number',
        );
      case 'TECHCOMBANK':
        return AppLocalizations.pick(
          vi: 'Số tài khoản Techcombank',
          en: 'Techcombank account number',
        );
      case 'VIETCOMBANK':
        return AppLocalizations.pick(
          vi: 'Số tài khoản Vietcombank',
          en: 'Vietcombank account number',
        );
      default:
        return preset.accountLabel;
    }
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final accountRef = _accountController.text.trim();
    if (accountRef.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Vui lòng điền đầy đủ thông tin liên kết.',
              en: 'Please fill in all required linking information.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    final provider = _selectedProvider;
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LinkedBankOtpScreen(
          providerCode: provider.code,
          providerName: provider.name,
          accountRef: accountRef,
          displayName: _displayNameController.text.trim().isEmpty
              ? provider.name
              : _displayNameController.text.trim(),
          notify: _notify,
          defaultSource: _defaultSource,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
    });

    if (linked == true && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _selectedProvider;
    final scheme = Theme.of(context).colorScheme;
    final tr = AppLocalizations.pick;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(vi: 'Thiết lập ngân hàng liên kết', en: 'Set up linked bank'),
        ),
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(vi: 'Chọn đối tác liên kết', en: 'Choose provider'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedProviderIndex,
                      items: List.generate(_providerPresets.length, (index) {
                        final item = _providerPresets[index];
                        final branding = providerBrandingFromCode(item.code);
                        return DropdownMenuItem<int>(
                          value: index,
                          child: Row(
                            children: [
                              ProviderLogoAvatar(branding: branding, size: 22),
                              const SizedBox(width: 8),
                              Text(item.name),
                            ],
                          ),
                        );
                      }),
                      selectedItemBuilder: (context) {
                        return List.generate(_providerPresets.length, (index) {
                          final item = _providerPresets[index];
                          final branding = providerBrandingFromCode(item.code);
                          return Row(
                            children: [
                              ProviderLogoAvatar(branding: branding, size: 22),
                              const SizedBox(width: 8),
                              Text(item.name),
                            ],
                          );
                        });
                      },
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedProviderIndex = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: tr(vi: 'Đối tác', en: 'Provider'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _providerHint(provider),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _accountController,
                      decoration: InputDecoration(
                        labelText: _providerAccountLabel(provider),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _displayNameController,
                      decoration: InputDecoration(
                        labelText: tr(
                          vi: 'Tên hiển thị trong ví',
                          en: 'Display name in wallet',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: _notify,
                      onChanged: (v) => setState(() => _notify = v == true),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr(
                          vi: 'Nhận thông báo biến động',
                          en: 'Receive activity notifications',
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: _defaultSource,
                      onChanged: (v) =>
                          setState(() => _defaultSource = v == true),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr(
                          vi: 'Đặt làm nguồn ưu tiên cho nạp/rút',
                          en: 'Set as default source for top-up/withdrawal',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: tr(vi: 'Tiếp tục nhập OTP', en: 'Continue to OTP'),
                icon: Icons.arrow_forward_rounded,
                loading: _submitting,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderPreset {
  final String code;
  final String name;
  final String hint;
  final String accountLabel;
  final IconData icon;
  final Color fg;

  const _ProviderPreset({
    required this.code,
    required this.name,
    required this.hint,
    required this.accountLabel,
    required this.icon,
    required this.fg,
  });
}

const List<_ProviderPreset> _providerPresets = [
  _ProviderPreset(
    code: 'MOMO',
    name: 'MoMo',
    hint: 'Ví điện tử MoMo, xác nhận OTP và cấp quyền giao dịch.',
    accountLabel: 'Số điện thoại MoMo',
    icon: Icons.account_balance_wallet_rounded,
    fg: Color(0xFFC2185B),
  ),
  _ProviderPreset(
    code: 'ZALOPAY',
    name: 'ZaloPay',
    hint: 'Kết nối ZaloPay với bước xác thực người dùng.',
    accountLabel: 'Số ví ZaloPay',
    icon: Icons.payments_rounded,
    fg: Color(0xFF1565C0),
  ),
  _ProviderPreset(
    code: 'VNPAY',
    name: 'VNPAY',
    hint: 'Liên kết cổng thanh toán VNPAY theo luồng xác thực.',
    accountLabel: 'Mã merchant / số tài khoản',
    icon: Icons.qr_code_2_rounded,
    fg: Color(0xFF2E7D32),
  ),
  _ProviderPreset(
    code: 'TECHCOMBANK',
    name: 'Techcombank',
    hint: 'Liên kết tài khoản Techcombank với xác thực OTP.',
    accountLabel: 'Số tài khoản Techcombank',
    icon: Icons.account_balance_rounded,
    fg: Color(0xFFC62828),
  ),
  _ProviderPreset(
    code: 'VIETCOMBANK',
    name: 'Vietcombank',
    hint: 'Liên kết tài khoản Vietcombank để nạp/rút nhanh.',
    accountLabel: 'Số tài khoản Vietcombank',
    icon: Icons.account_balance_rounded,
    fg: Color(0xFF1B5E20),
  ),
];
