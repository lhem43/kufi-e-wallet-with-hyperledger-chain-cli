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
import 'linked_banks_screen.dart';
import 'otp_confirmation_screen.dart';

class ExternalCashFlowScreen extends StatefulWidget {
  final bool isTopup;

  const ExternalCashFlowScreen({super.key, required this.isTopup});

  @override
  State<ExternalCashFlowScreen> createState() => _ExternalCashFlowScreenState();
}

class _ExternalCashFlowScreenState extends State<ExternalCashFlowScreen> {
  final _userService = UserService();
  final _authService = AuthService();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _isFormattingAmount = false;
  bool _revealed = false;
  bool _hasPinProtection = false;
  int _selectedSourceIndex = 0;
  List<Map<String, dynamic>> _activeSources = [];
  Map<String, String> _revealedAccounts = {};

  @override
  void initState() {
    super.initState();
    _initRevealState();
    _loadSources();
  }

  Future<void> _initRevealState() async {
    final hasPin = await _authService.hasDevicePinForCurrentUser();
    if (!mounted) return;
    setState(() {
      _hasPinProtection = hasPin;
      _revealed = !hasPin || PinSessionService().isBalanceUnlocked;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
    });

    final sources = await _userService.getFundingSources();
    if (!mounted) return;

    final active = sources.where((item) {
      final status = '${item['status'] ?? ''}'.trim().toUpperCase();
      return status.isEmpty || status == 'ACTIVE';
    }).toList();

    final revealedMap = <String, String>{};
    for (final source in active) {
      final sourceId = '${source['fundingSourceId'] ?? source['id'] ?? ''}'
          .trim();
      if (sourceId.isEmpty) {
        continue;
      }
      final secret = await _userService.getFundingSourceSecret(sourceId);
      if (secret != null && secret.trim().isNotEmpty) {
        revealedMap[sourceId] = secret.trim();
      }
    }

    setState(() {
      _activeSources = active;
      _revealedAccounts = revealedMap;
      _selectedSourceIndex = 0;
      _loading = false;
    });
  }

  int _parseAmount() {
    final digits = _amountController.text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 0;
  }

  String _formatWithCommas(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  void _onAmountChanged(String raw) {
    if (_isFormattingAmount) {
      return;
    }
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    final formatted = digits.isEmpty
        ? ''
        : _formatWithCommas(int.tryParse(digits) ?? 0);
    if (formatted == raw) {
      return;
    }
    _isFormattingAmount = true;
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingAmount = false;
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
          vi: 'Mở thông tin nguồn tiền',
          en: 'Reveal funding source info',
        ),
        subtitle: AppLocalizations.pick(
          vi: 'Nhập PIN để xem thông tin ngân hàng liên kết',
          en: 'Enter PIN to view linked bank info',
        ),
      ),
    );
    if (unlocked == true && mounted) {
      PinSessionService().markBalanceUnlocked();
      setState(() => _revealed = true);
    }
  }

  String _displayedAccount(Map<String, dynamic> source) {
    final sourceId = '${source['fundingSourceId'] ?? source['id'] ?? ''}'
        .trim();
    final masked = '${source['accountRefMasked'] ?? ''}'.trim();
    if (!_revealed) {
      return masked.isEmpty ? '****' : masked;
    }
    final local = _revealedAccounts[sourceId]?.trim() ?? '';
    if (local.isNotEmpty) {
      return local;
    }
    return masked.isEmpty ? '****' : masked;
  }

  Future<void> _submit() async {
    if (_submitting || _activeSources.isEmpty) {
      return;
    }

    final amount = _parseAmount();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Vui lòng nhập số tiền hợp lệ.',
              en: 'Please enter a valid amount.',
            ),
          ),
        ),
      );
      return;
    }

    final selected =
        _activeSources[_selectedSourceIndex.clamp(
          0,
          _activeSources.length - 1,
        )];
    final fundingSourceId = '${selected['fundingSourceId'] ?? ''}'.trim();
    if (fundingSourceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Không tìm thấy nguồn tiền liên kết.',
              en: 'Linked funding source not found.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    final memo = _memoController.text.trim();
    final branding = providerBrandingFromCode('${selected['provider'] ?? ''}');
    final providerName = branding.displayName;
    final providerCode = '${selected['provider'] ?? ''}'.trim().toUpperCase();
    final accountMasked = '${selected['accountRefMasked'] ?? '****'}';
    final riskResult = await _userService.assessTransferRisk(
      recipientUserId: fundingSourceId,
      recipientIdentifier: '$providerName • $accountMasked',
      amount: amount,
      currency: 'VND',
      isExternal: true,
      externalPartner: providerCode,
      externalAccountNo: fundingSourceId,
    );
    final initialStepUpRequired = riskResult['success'] == true
        ? riskResult['requiresStepUp'] == true
        : amount >= 50 * 1000 * 1000;
    final initialRiskReasons =
        riskResult['success'] == true && riskResult['reasons'] is List
        ? List<String>.from(
            (riskResult['reasons'] as List)
                .map((e) => '$e')
                .where((e) => e.isNotEmpty),
          )
        : const <String>[];
    final initialRiskProbability = '${riskResult['probability'] ?? ''}'.trim();

    if (mounted) {
      setState(() {
        _submitting = false;
      });
    }
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OTPConfirmationScreen.externalCashFlow(
          isTopup: widget.isTopup,
          fundingSourceId: fundingSourceId,
          externalPartner: providerCode,
          counterpartyLabel: '$providerName • $accountMasked',
          amount: amount,
          message: memo,
          preAssessedRequiresStepUp: initialStepUpRequired,
          preAssessedRiskReasons: initialRiskReasons,
          preAssessedRiskProbability: initialRiskProbability,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final title = widget.isTopup
        ? tr(vi: 'Nạp tiền', en: 'Top up')
        : tr(vi: 'Rút tiền', en: 'Withdraw');
    final buttonLabel = widget.isTopup
        ? tr(vi: 'Xác nhận nạp tiền', en: 'Confirm top-up')
        : tr(vi: 'Xác nhận rút tiền', en: 'Confirm withdrawal');
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final mutedColor = scheme.onSurface.withValues(alpha: 0.62);
    final selectedBg = isDark
        ? const Color(0xFF2A3140)
        : AppColors.violet50.withValues(alpha: 0.6);
    final unselectedBg = isDark ? const Color(0xFF1F2735) : Colors.white;
    final selectedBorder = isDark ? scheme.primary : AppColors.momoPink;
    final unselectedBorder = isDark
        ? const Color(0xFF3A4A62)
        : AppColors.violet200;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _loadSources,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isTopup
                            ? tr(
                                vi: 'Chọn nguồn tiền liên kết để nạp vào ví',
                                en: 'Choose linked source to top up wallet',
                              )
                            : tr(
                                vi: 'Chọn nguồn tiền liên kết để rút từ ví',
                                en: 'Choose linked source to withdraw from wallet',
                              ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          vi: 'Giao dịch được xử lý theo trạng thái nghiệp vụ của ví. Thông tin xác thực chuỗi sẽ tự động cập nhật.',
                          en: 'Transaction is processed by wallet workflow status. On-chain verification updates automatically.',
                        ),
                        style: TextStyle(color: subColor, height: 1.35),
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
                                ? tr(vi: 'Ẩn thông tin', en: 'Hide details')
                                : tr(vi: 'Hiện thông tin', en: 'Show details'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_activeSources.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 42,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            vi: 'Bạn chưa có nguồn tiền liên kết.',
                            en: 'You have no linked funding source.',
                          ),
                          style: TextStyle(
                            color: subColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LinkedBanksScreen(),
                              ),
                            );
                            await _loadSources();
                          },
                          icon: const Icon(Icons.add_link_rounded),
                          label: Text(
                            tr(
                              vi: 'Thiết lập ngân hàng liên kết',
                              en: 'Set up linked bank',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(vi: 'Nguồn tiền', en: 'Funding source'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(_activeSources.length, (index) {
                          final source = _activeSources[index];
                          final branding = providerBrandingFromCode(
                            '${source['provider'] ?? ''}',
                          );
                          final providerName = branding.displayName;
                          final isSelected = _selectedSourceIndex == index;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                _selectedSourceIndex = index;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? selectedBorder
                                      : unselectedBorder,
                                  width: isSelected ? 1.6 : 1,
                                ),
                                color: isSelected ? selectedBg : unselectedBg,
                              ),
                              child: Row(
                                children: [
                                  ProviderLogoAvatar(
                                    branding: branding,
                                    size: 34,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${source['displayName'] ?? providerName}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: titleColor,
                                          ),
                                        ),
                                        Text(
                                          '$providerName • ${_displayedAccount(source)}',
                                          style: TextStyle(color: subColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected
                                        ? selectedBorder
                                        : mutedColor,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          onChanged: _onAmountChanged,
                          decoration: InputDecoration(
                            labelText: tr(
                              vi: 'Số tiền (VND)',
                              en: 'Amount (VND)',
                            ),
                            hintText: tr(
                              vi: 'Ví dụ: 100,000',
                              en: 'Example: 100,000',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _memoController,
                          decoration: InputDecoration(
                            labelText: tr(
                              vi: 'Ghi chú (tùy chọn)',
                              en: 'Note (optional)',
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
                    label: buttonLabel,
                    icon: widget.isTopup
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    loading: _submitting,
                    onPressed: _submit,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
