import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import 'account_info_screen.dart';
import 'help_screen.dart';
import 'linked_banks_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ProfileScreen({super.key, this.onProfileUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _userService = UserService();
  final _authService = AuthService();

  bool _loading = true;
  bool _submittingKyc = false;
  String _displayName = '';
  String _email = '';
  String _phone = '';
  String _kycStatus = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
        _displayName = '${profile?['displayName'] ?? ''}'.trim();
        _email = '${profile?['email'] ?? ''}'.trim();
        _phone = '${profile?['phone'] ?? ''}'.trim();
        _kycStatus = '${profile?['kycStatus'] ?? _kycStatus}'.trim();
      });
      await _loadKycStatus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadKycStatus() async {
    final result = await _userService.getMyKycProfile();
    if (!mounted || result['success'] != true || result['profile'] is! Map) {
      return;
    }
    final profile = Map<String, dynamic>.from(result['profile'] as Map);
    setState(() {
      _kycStatus = '${profile['status'] ?? _kycStatus}'.trim();
    });
  }

  bool get _isVerified => _kycStatus.toUpperCase() == 'VERIFIED';
  bool get _isPending =>
      _kycStatus.toUpperCase() == 'PENDING_REVIEW' ||
      _kycStatus.toUpperCase() == 'PENDING';

  String get _initials {
    if (_displayName.isEmpty) return 'U';
    final parts = _displayName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return _displayName[0].toUpperCase();
  }

  Future<void> _submitKyc() async {
    setState(() => _submittingKyc = true);
    final result = await _userService.submitKyc(
      fullName: _displayName,
      nationalId: '',
      dateOfBirth: '',
      residentialAddress: '',
    );
    if (!mounted) return;
    setState(() => _submittingKyc = false);
    if (result['success'] == true) {
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã gửi hồ sơ xác thực.',
              en: 'Verification request submitted.',
            ),
          ),
        ),
      );
      widget.onProfileUpdated?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['message'] ?? AppLocalizations.pick(vi: 'Lỗi gửi xác thực', en: 'Failed to submit verification request')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainText = scheme.onSurface;
    final secondaryText = scheme.onSurface.withValues(alpha: 0.72);

    final resolvedName = _displayName.isNotEmpty
        ? _displayName
        : (_email.isNotEmpty
              ? _email
              : tr(vi: 'Người dùng Kufi', en: 'Kufi user'));

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
        children: [
          // ── Profile header card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isDark
                              ? AppColors.darkCardGradient
                              : AppColors.cardGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.momoPink.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'BeVietnamPro',
                            ),
                          ),
                        ),
                      ),
                      if (_isVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: AppColors.success,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Name with verified tick inline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          resolvedName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: mainText,
                          ),
                        ),
                      ),
                      if (_isVerified) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                  if (_phone.isNotEmpty || _email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _phone.isNotEmpty ? _phone : _email,
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // KYC status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _isVerified
                          ? AppColors.success.withValues(alpha: 0.12)
                          : (_isPending
                                ? (isDark
                                      ? AppColors.violet300.withValues(
                                          alpha: 0.18,
                                        )
                                      : AppColors.violet100)
                                : secondaryText.withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      _isVerified
                          ? tr(vi: 'Đã xác thực', en: 'Verified')
                          : (_isPending
                                ? tr(vi: 'Đang xác thực', en: 'Verifying')
                                : tr(vi: 'Chưa xác thực', en: 'Not verified')),
                      style: TextStyle(
                        color: _isVerified
                            ? AppColors.success
                            : (_isPending
                                  ? (isDark
                                        ? AppColors.violet200
                                        : AppColors.violet700)
                                  : secondaryText),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Menu items ──
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Column(
                children: [
                  _MenuTile(
                    icon: Icons.person_outline_rounded,
                    title: tr(
                      vi: 'Thông tin tài khoản',
                      en: 'Account information',
                    ),
                    subtitle: tr(
                      vi: 'Tên, email, số điện thoại, PIN',
                      en: 'Name, email, phone number, PIN',
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AccountInfoScreen(
                            onProfileUpdated: widget.onProfileUpdated,
                          ),
                        ),
                      );
                      _loadProfile();
                    },
                  ),
                  const Divider(height: 1, indent: 60),
                  _MenuTile(
                    icon: Icons.fingerprint_rounded,
                    title: tr(
                      vi: 'Xác thực định danh',
                      en: 'Identity verification',
                    ),
                    subtitle: _isVerified
                        ? tr(
                            vi: 'Đã xác thực thành công',
                            en: 'Verification completed',
                          )
                        : (_isPending
                              ? tr(
                                  vi: 'Đang xử lý xác thực',
                                  en: 'Verification in progress',
                                )
                              : tr(
                                  vi: 'Xác thực CCCD qua NFC',
                                  en: 'Verify ID card via NFC',
                                )),
                    trailing: _isVerified
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 20,
                          )
                        : null,
                    onTap: () => _showKycBottomSheet(),
                  ),
                  const Divider(height: 1, indent: 60),
                  _MenuTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: tr(vi: 'Ngân hàng liên kết', en: 'Linked banks'),
                    subtitle: tr(
                      vi: 'Quản lý MoMo, ZaloPay, VNPAY, ngân hàng',
                      en: 'Manage MoMo, ZaloPay, VNPAY, bank accounts',
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LinkedBanksScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 60),
                  _MenuTile(
                    icon: Icons.settings_outlined,
                    title: tr(vi: 'Cài đặt', en: 'Settings'),
                    subtitle: tr(
                      vi: 'Thông báo, ngôn ngữ',
                      en: 'Notifications, language',
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 60),
                  _MenuTile(
                    icon: Icons.help_outline_rounded,
                    title: tr(vi: 'Trợ giúp', en: 'Help'),
                    subtitle: tr(
                      vi: 'Câu hỏi thường gặp, liên hệ',
                      en: 'FAQ and contact',
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HelpScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showKycBottomSheet() {
    final tr = AppLocalizations.pick;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final mainText = scheme.onSurface;
        final secondaryText = scheme.onSurface.withValues(alpha: 0.72);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: secondaryText.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isVerified
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.violet100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isVerified
                          ? Icons.verified_user_rounded
                          : Icons.fingerprint_rounded,
                      color: _isVerified
                          ? AppColors.success
                          : AppColors.violet600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(
                            vi: 'Xác thực định danh',
                            en: 'Identity verification',
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: mainText,
                          ),
                        ),
                        Text(
                          _isVerified
                              ? tr(
                                  vi: 'Đã xác thực thành công',
                                  en: 'Verification completed',
                                )
                              : (_isPending
                                    ? tr(vi: 'Đang xử lý', en: 'In progress')
                                    : tr(
                                        vi: 'Chưa xác thực',
                                        en: 'Not verified',
                                      )),
                          style: TextStyle(
                            color: _isVerified
                                ? AppColors.success
                                : (_isPending
                                      ? (isDark
                                            ? AppColors.violet200
                                            : AppColors.violet700)
                                      : secondaryText),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_isVerified)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(
                            vi: 'Tài khoản đã được xác thực thành công.',
                            en: 'This account has been successfully verified.',
                          ),
                          style: TextStyle(color: secondaryText, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_isPending)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.violet50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.violet100),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: AppColors.violet700,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(
                            vi: 'Đang xử lý xác thực. Vui lòng chờ kết quả.',
                            en: 'Verification is being processed. Please wait for the result.',
                          ),
                          style: TextStyle(color: secondaryText, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  tr(
                    vi: 'Xác minh danh tính bằng CCCD gắn chip qua NFC.',
                    en: 'Verify your identity using NFC-enabled ID card.',
                  ),
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _VerifyStep(
                  step: '1',
                  title: tr(
                    vi: 'Chuẩn bị CCCD gắn chip',
                    en: 'Prepare your ID card',
                  ),
                  subtitle: tr(
                    vi: 'Đặt thẻ lên mặt sau điện thoại',
                    en: 'Place the card on the back of your phone',
                  ),
                  icon: Icons.credit_card_rounded,
                ),
                const SizedBox(height: 10),
                _VerifyStep(
                  step: '2',
                  title: tr(vi: 'Quét NFC', en: 'Scan NFC'),
                  subtitle: tr(
                    vi: 'Giữ thẻ cho đến khi đọc xong',
                    en: 'Hold the card until scanning is complete',
                  ),
                  icon: Icons.nfc_rounded,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: tr(vi: 'Bắt đầu xác thực', en: 'Start verification'),
                    icon: Icons.verified_user_rounded,
                    loading: _submittingKyc,
                    onPressed: _submittingKyc
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _submitKyc();
                          },
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark
        ? AppColors.violet300.withValues(alpha: 0.2)
        : AppColors.violet100;
    final iconColor = isDark ? AppColors.violet200 : AppColors.violet600;
    final titleColor = scheme.onSurface;
    final subtitleColor = scheme.onSurface.withValues(alpha: 0.72);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 22),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: subtitleColor,
                  size: 22,
                ),
          ],
        ),
      ),
    );
  }
}

class _VerifyStep extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final IconData icon;

  const _VerifyStep({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = scheme.onSurface;
    final subtitleColor = scheme.onSurface.withValues(alpha: 0.72);
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.violet200
        : AppColors.violet600;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.momoPink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: subtitleColor, fontSize: 12),
              ),
            ],
          ),
        ),
        Icon(icon, color: iconColor, size: 22),
      ],
    );
  }
}
