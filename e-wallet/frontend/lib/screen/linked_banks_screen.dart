import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/pin_session_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../utils/provider_branding.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_unlock_dialog.dart';
import 'linked_bank_setup_screen.dart';

class LinkedBanksScreen extends StatefulWidget {
  const LinkedBanksScreen({super.key});

  @override
  State<LinkedBanksScreen> createState() => _LinkedBanksScreenState();
}

class _LinkedBanksScreenState extends State<LinkedBanksScreen> {
  final _userService = UserService();
  final _authService = AuthService();

  bool _loading = true;
  bool _revealed = false;
  bool _hasPinProtection = false;
  List<Map<String, dynamic>> _sources = [];
  Map<String, String> _revealedAccounts = {};

  @override
  void initState() {
    super.initState();
    _initRevealState();
    _reload();
  }

  Future<void> _initRevealState() async {
    final hasPin = await _authService.hasDevicePinForCurrentUser();
    if (!mounted) return;
    setState(() {
      _hasPinProtection = hasPin;
      _revealed = !hasPin || PinSessionService().isBalanceUnlocked;
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
    });
    final items = await _userService.getFundingSources();
    final revealedMap = <String, String>{};
    for (final item in items) {
      final sourceId = '${item['fundingSourceId'] ?? item['id'] ?? ''}'.trim();
      if (sourceId.isEmpty) {
        continue;
      }
      final secret = await _userService.getFundingSourceSecret(sourceId);
      if (secret != null && secret.trim().isNotEmpty) {
        revealedMap[sourceId] = secret.trim();
      }
    }
    if (!mounted) return;
    setState(() {
      _sources = items;
      _revealedAccounts = revealedMap;
      _loading = false;
    });
  }

  Future<void> _openSetupScreen() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LinkedBankSetupScreen()),
    );
    if (created == true) {
      await _reload();
    }
  }

  Future<void> _toggleReveal() async {
    if (_revealed) {
      setState(() => _revealed = false);
      return;
    }
    if (!_hasPinProtection) {
      setState(() => _revealed = true);
      return;
    }
    if (PinSessionService().isBalanceUnlocked) {
      setState(() => _revealed = true);
      return;
    }

    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinUnlockDialog(
        authService: _authService,
        title: AppLocalizations.pick(
          vi: 'Mở thông tin liên kết',
          en: 'Reveal linked account details',
        ),
        subtitle: AppLocalizations.pick(
          vi: 'Nhập PIN để xem chi tiết ngân hàng liên kết',
          en: 'Enter PIN to view linked bank details',
        ),
      ),
    );
    if (unlocked == true && mounted) {
      PinSessionService().markBalanceUnlocked();
      setState(() => _revealed = true);
    }
  }

  String _displayedAccount(Map<String, dynamic> item) {
    final sourceId = '${item['fundingSourceId'] ?? item['id'] ?? ''}'.trim();
    final masked = '${item['accountRefMasked'] ?? ''}'.trim();
    if (!_revealed) {
      return masked.isEmpty ? '****' : masked;
    }
    final local = _revealedAccounts[sourceId]?.trim() ?? '';
    if (local.isNotEmpty) {
      return local;
    }
    return masked.isEmpty ? '****' : masked;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 400;
    final scheme = Theme.of(context).colorScheme;
    final tr = AppLocalizations.pick;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final mutedColor = scheme.onSurface.withValues(alpha: 0.62);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Ngân hàng liên kết', en: 'Linked banks')),
      ),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          vi: 'Quản lý nguồn tiền liên kết',
                          en: 'Manage linked funding sources',
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          vi: 'Liên kết MoMo, ZaloPay, VNPAY hoặc tài khoản ngân hàng để nạp/rút tiền thuận tiện.',
                          en: 'Link MoMo, ZaloPay, VNPAY, or bank accounts for easier top-up and withdrawal.',
                        ),
                        style: TextStyle(color: subColor, height: 1.35),
                      ),
                      const SizedBox(height: 14),
                      if (compact) ...[
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            label: tr(
                              vi: 'Thiết lập liên kết mới',
                              en: 'Set up new link',
                            ),
                            icon: Icons.add_link_rounded,
                            onPressed: _openSetupScreen,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _toggleReveal,
                            icon: Icon(
                              _revealed
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            label: Text(
                              _revealed
                                  ? tr(vi: 'Ẩn', en: 'Hide')
                                  : tr(vi: 'Hiện', en: 'Show'),
                            ),
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                width: double.infinity,
                                child: GradientButton(
                                  label: tr(
                                    vi: 'Thiết lập liên kết mới',
                                    en: 'Set up new link',
                                  ),
                                  icon: Icons.add_link_rounded,
                                  onPressed: _openSetupScreen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _toggleReveal,
                              icon: Icon(
                                _revealed
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                              label: Text(
                                _revealed
                                    ? tr(vi: 'Ẩn', en: 'Hide')
                                    : tr(vi: 'Hiện', en: 'Show'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_sources.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 44,
                          color: mutedColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            vi: 'Chưa có nguồn tiền nào được liên kết.',
                            en: 'No funding source is linked yet.',
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._sources.map((item) {
                  final branding = providerBrandingFromCode(
                    '${item['provider'] ?? ''}',
                  );
                  final status = '${item['status'] ?? ''}'.toUpperCase();
                  final active = status == 'ACTIVE';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      leading: ProviderLogoAvatar(branding: branding),
                      title: Text(
                        '${item['displayName'] ?? branding.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                      subtitle: Text(
                        '${branding.displayName} • ${_displayedAccount(item)}',
                        style: TextStyle(
                          color: subColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.success.withValues(alpha: 0.14)
                              : AppColors.violet100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          active
                              ? tr(vi: 'Đang hoạt động', en: 'Active')
                              : tr(vi: 'Đang xử lý', en: 'Processing'),
                          style: TextStyle(
                            color: active
                                ? AppColors.success
                                : AppColors.violet700,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
