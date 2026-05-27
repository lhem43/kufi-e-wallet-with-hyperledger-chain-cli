import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/pin_session_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_code_boxes.dart';
import 'otp_confirmation_screen.dart';

// ---------------------------------------------------------------------------
// Phone formatter: 0912 345 678
// ---------------------------------------------------------------------------
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length > 11) {
      return oldValue;
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ---------------------------------------------------------------------------
// Amount formatter: 1,000,000
// ---------------------------------------------------------------------------
class _AmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final number = int.tryParse(digits) ?? 0;
    final formatted = _formatWithCommas(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _formatWithCommas(int value) {
    final s = value.toString();
    final result = StringBuffer();
    var count = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) result.write(',');
      result.write(s[i]);
      count++;
    }
    return result.toString().split('').reversed.join();
  }
}

class SendMoneyScreen extends StatefulWidget {
  final String? initialRecipientPhone;

  const SendMoneyScreen({super.key, this.initialRecipientPhone});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  static const int _stepUpFallbackHardAmount = 50 * 1000 * 1000;

  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();

  double _balance = 0;
  bool _loadingBalance = true;
  bool _balanceVisible = false;
  bool _hasPinProtection = false;
  bool _searchingRecipient = false;
  bool _navigatingToConfirmation = false;
  Map<String, dynamic>? _resolvedRecipient;
  String _verifiedRecipientPhone = '';
  String _recipientLookupMessage = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadBalance();
    final initialPhone = (widget.initialRecipientPhone ?? '').trim();
    if (initialPhone.isNotEmpty) {
      _recipientController.text = initialPhone;
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchRecipient());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _recipientController.dispose();
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    if (mounted) setState(() => _loadingBalance = true);
    try {
      final balance = await _userService.getCurrentUserBalance();
      final hasPin = await _authService.hasDevicePinForCurrentUser();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _hasPinProtection = hasPin;
        // Sync with session: only show if explicitly unlocked
        _balanceVisible = !hasPin || PinSessionService().isBalanceUnlocked;
      });
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _toggleBalanceVisibility() async {
    if (_balanceVisible) {
      setState(() => _balanceVisible = false);
      return;
    }
    if (!_hasPinProtection) {
      setState(() => _balanceVisible = true);
      return;
    }
    if (PinSessionService().isBalanceUnlocked) {
      setState(() => _balanceVisible = true);
      return;
    }
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinUnlockDialog(authService: _authService),
    );
    if (unlocked == true && mounted) {
      PinSessionService().markBalanceUnlocked();
      setState(() => _balanceVisible = true);
    }
  }

  String _formatMoney(num value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _normalizePhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.startsWith('84') && digitsOnly.length == 11) {
      return '0${digitsOnly.substring(2)}';
    }
    return digitsOnly;
  }

  bool _isExactPhone(String phone) {
    return RegExp(r'^0\d{9}$').hasMatch(phone) ||
        RegExp(r'^0\d{10}$').hasMatch(phone) ||
        RegExp(r'^84\d{8,10}$').hasMatch(phone);
  }

  bool _isRecipientVerified() {
    final normalizedInput = _normalizePhone(_recipientController.text.trim());
    return _verifiedRecipientPhone.isNotEmpty &&
        _verifiedRecipientPhone == normalizedInput &&
        _resolvedRecipient != null;
  }

  int _parseAmount() {
    final digits = _amountController.text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 0;
  }

  void _onRecipientChanged(String value) {
    final normalized = _normalizePhone(value);

    // Clear previous if input changed
    if (_verifiedRecipientPhone.isNotEmpty &&
        normalized != _verifiedRecipientPhone) {
      setState(() {
        _resolvedRecipient = null;
        _verifiedRecipientPhone = '';
        _recipientLookupMessage = '';
      });
    }

    // Auto-search: only when exact phone number (all digits typed)
    _searchDebounce?.cancel();
    if (_isExactPhone(normalized) && normalized != _verifiedRecipientPhone) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _searchRecipient();
      });
    }
  }

  Future<void> _searchRecipient() async {
    final normalizedPhone = _normalizePhone(_recipientController.text.trim());
    if (!_isExactPhone(normalizedPhone)) {
      setState(() {
        _resolvedRecipient = null;
        _verifiedRecipientPhone = '';
        _recipientLookupMessage = AppLocalizations.pick(
          vi: 'Nhập đủ số điện thoại để tra cứu.',
          en: 'Enter full phone number to search.',
        );
      });
      return;
    }

    final currentUser = await _authService.getCurrentUser();
    final myPhone = _normalizePhone('${currentUser?['phone'] ?? ''}');
    if (myPhone.isNotEmpty && myPhone == normalizedPhone) {
      setState(() {
        _resolvedRecipient = null;
        _verifiedRecipientPhone = '';
        _recipientLookupMessage = AppLocalizations.pick(
          vi: 'Không thể chuyển tiền cho chính mình.',
          en: 'You cannot transfer money to yourself.',
        );
      });
      return;
    }

    setState(() {
      _searchingRecipient = true;
      _resolvedRecipient = null;
      _verifiedRecipientPhone = '';
      _recipientLookupMessage = '';
    });

    try {
      final result = await _userService.getUserByPhone(normalizedPhone);
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() {
          _recipientLookupMessage =
              '${result['message'] ?? AppLocalizations.pick(vi: 'Không thể tra cứu.', en: 'Unable to look up recipient.')}';
        });
        return;
      }

      if (result['found'] != true) {
        setState(() {
          _recipientLookupMessage = AppLocalizations.pick(
            vi: 'Không tìm thấy tài khoản với số điện thoại này.',
            en: 'No account found for this phone number.',
          );
        });
        return;
      }

      final recipient = Map<String, dynamic>.from(
        (result['recipient'] as Map?) ?? {},
      );
      final resolvedPhone = _normalizePhone(
        '${recipient['phone'] ?? normalizedPhone}',
      );

      setState(() {
        _resolvedRecipient = recipient;
        _verifiedRecipientPhone = resolvedPhone.isEmpty
            ? normalizedPhone
            : resolvedPhone;
        _recipientLookupMessage = '';
      });
    } finally {
      if (mounted) setState(() => _searchingRecipient = false);
    }
  }

  Future<void> _handleContinue() async {
    if (_navigatingToConfirmation) {
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (!_isRecipientVerified()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Vui lòng nhập đúng số điện thoại người nhận.',
              en: 'Please enter a valid recipient phone number.',
            ),
          ),
        ),
      );
      return;
    }

    final amount = _parseAmount();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Số tiền không hợp lệ.',
              en: 'Invalid amount.',
            ),
          ),
        ),
      );
      return;
    }

    if (_balance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Số dư không đủ. Hiện có: ${_formatMoney(_balance)}đ',
              en: 'Insufficient balance. Available: ${_formatMoney(_balance)}đ',
            ),
          ),
        ),
      );
      return;
    }

    final recipientUserId = '${_resolvedRecipient?['userId'] ?? ''}'.trim();
    if (recipientUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Không xác định được người nhận.',
              en: 'Unable to resolve recipient.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _navigatingToConfirmation = true;
    });

    bool? initialStepUpRequired;
    var initialRiskReasons = const <String>[];
    var initialRiskProbability = '';

    try {
      final riskResult = await _userService.assessTransferRisk(
        recipientUserId: recipientUserId,
        recipientIdentifier: _verifiedRecipientPhone,
        amount: amount,
        currency: 'VND',
      );

      if (riskResult['success'] == true) {
        initialStepUpRequired = riskResult['requiresStepUp'] == true;
        final reasonsRaw = riskResult['reasons'];
        initialRiskReasons = reasonsRaw is List
            ? reasonsRaw
                  .map((e) => '$e')
                  .where((e) => e.trim().isNotEmpty)
                  .toList()
            : const <String>[];
        initialRiskProbability = '${riskResult['probability'] ?? ''}';
      } else if (amount >= _stepUpFallbackHardAmount) {
        // Match backend fallback policy for large transfers when risk preview fails.
        initialStepUpRequired = true;
        initialRiskReasons = const <String>[
          'amount_over_fallback_threshold',
          'ato_model_unavailable',
        ];
      }

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OTPConfirmationScreen(
            recipientIdentifier: _verifiedRecipientPhone,
            recipientUserId: recipientUserId,
            amount: amount,
            message: _messageController.text.trim(),
            preAssessedRequiresStepUp: initialStepUpRequired,
            preAssessedRiskReasons: initialRiskReasons,
            preAssessedRiskProbability: initialRiskProbability,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _navigatingToConfirmation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final iconBg = isDark ? const Color(0xFF2E3440) : AppColors.violet100;
    final iconColor = isDark ? const Color(0xFF9FB4D3) : AppColors.violet600;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Chuyển tiền', en: 'Transfer money')),
      ),
      body: AppBackground(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Balance card
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 12 : 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _loadingBalance
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      tr(vi: 'Đang tải...', en: 'Loading...'),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr(
                                        vi: 'Số dư khả dụng',
                                        en: 'Available balance',
                                      ),
                                      style: TextStyle(
                                        color: subColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _balanceVisible
                                          ? '${_formatMoney(_balance)}đ'
                                          : '••••••đ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        color: titleColor,
                                        fontFamily: 'BeVietnamPro',
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (!_loadingBalance)
                          IconButton(
                            onPressed: _toggleBalanceVisibility,
                            icon: Icon(
                              _balanceVisible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: subColor,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Recipient card
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 14 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(vi: 'Người nhận', en: 'Recipient'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            vi: 'Nhập chính xác số điện thoại để tra cứu tự động.',
                            en: 'Enter an exact phone number for auto lookup.',
                          ),
                          style: TextStyle(color: subColor, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _recipientController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [_PhoneFormatter()],
                          onChanged: _onRecipientChanged,
                          decoration: InputDecoration(
                            hintText: '0912 345 678',
                            prefixIcon: const Icon(Icons.phone_iphone),
                            suffixIcon: _searchingRecipient
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : _isRecipientVerified()
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.success,
                                  )
                                : null,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return tr(
                                vi: 'Vui lòng nhập số điện thoại.',
                                en: 'Please enter phone number.',
                              );
                            }
                            final normalized = _normalizePhone(value.trim());
                            if (!_isExactPhone(normalized)) {
                              return tr(
                                vi: 'Số điện thoại phải đủ 10-11 số.',
                                en: 'Phone number must be 10-11 digits.',
                              );
                            }
                            if (!_isRecipientVerified()) {
                              return tr(
                                vi: 'Chưa tìm thấy người nhận.',
                                en: 'Recipient not found yet.',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        if (_resolvedRecipient != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_rounded,
                                  color: AppColors.success,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_resolvedRecipient!['displayName'] ?? tr(vi: 'Người dùng', en: 'User')}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: titleColor,
                                        ),
                                      ),
                                      Text(
                                        _verifiedRecipientPhone,
                                        style: TextStyle(
                                          color: subColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_recipientLookupMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              _recipientLookupMessage,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Amount + Message card
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 14 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(vi: 'Số tiền (VNĐ)', en: 'Amount (VND)'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_AmountFormatter()],
                          decoration: const InputDecoration(
                            hintText: '0',
                            prefixIcon: Icon(Icons.payments_outlined),
                            suffixText: 'đ',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return tr(
                                vi: 'Vui lòng nhập số tiền.',
                                en: 'Please enter amount.',
                              );
                            }
                            final amount =
                                int.tryParse(
                                  value.replaceAll(RegExp(r'[^\d]'), ''),
                                ) ??
                                0;
                            if (amount <= 0) {
                              return tr(
                                vi: 'Số tiền không hợp lệ.',
                                en: 'Invalid amount.',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            _QuickAmountChip(
                              label: '50K',
                              onTap: () => _amountController.text = '50,000',
                            ),
                            _QuickAmountChip(
                              label: '100K',
                              onTap: () => _amountController.text = '100,000',
                            ),
                            _QuickAmountChip(
                              label: '200K',
                              onTap: () => _amountController.text = '200,000',
                            ),
                            _QuickAmountChip(
                              label: '500K',
                              onTap: () => _amountController.text = '500,000',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          tr(
                            vi: 'Ghi chú (tuỳ chọn)',
                            en: 'Message (optional)',
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _messageController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: tr(
                              vi: 'Nội dung chuyển tiền',
                              en: 'Transfer note',
                            ),
                            prefixIcon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: _navigatingToConfirmation
                        ? tr(
                            vi: 'Đang chuẩn bị xác thực...',
                            en: 'Preparing verification...',
                          )
                        : tr(
                            vi: 'Tiếp tục xác thực',
                            en: 'Continue verification',
                          ),
                    icon: Icons.arrow_forward_rounded,
                    loading: _navigatingToConfirmation,
                    onPressed: _searchingRecipient || _navigatingToConfirmation
                        ? null
                        : _handleContinue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAmountChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: onTap,
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          fontSize: 13,
        ),
      ),
      side: BorderSide(
        color: isDark ? const Color(0xFF3A4A62) : AppColors.vanilla300,
      ),
      backgroundColor: isDark ? const Color(0xFF242D3D) : AppColors.vanilla50,
    );
  }
}

class _PinUnlockDialog extends StatefulWidget {
  final AuthService authService;

  const _PinUnlockDialog({required this.authService});

  @override
  State<_PinUnlockDialog> createState() => _PinUnlockDialogState();
}

class _PinUnlockDialogState extends State<_PinUnlockDialog> {
  final _pinController = TextEditingController();
  bool _verifying = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(
        () => _errorText = AppLocalizations.pick(
          vi: 'PIN gồm đúng 6 chữ số.',
          en: 'PIN must be exactly 6 digits.',
        ),
      );
      return;
    }
    setState(() {
      _verifying = true;
      _errorText = null;
    });
    final valid = await widget.authService.verifyServerPin(pin);
    if (!mounted) return;
    if (!valid) {
      setState(() {
        _verifying = false;
        _errorText = AppLocalizations.pick(
          vi: 'PIN không chính xác.',
          en: 'Incorrect PIN.',
        );
      });
      return;
    }
    Navigator.of(context).pop(true);
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
                tr(vi: 'Xác thực PIN', en: 'Verify PIN'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'BeVietnamPro',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  vi: 'Nhập PIN để xem số dư khả dụng.',
                  en: 'Enter PIN to view available balance.',
                ),
              ),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _pinController,
                enabled: !_verifying,
                autofocus: true,
                label: tr(vi: 'PIN bảo mật', en: 'Security PIN'),
                helperText: tr(
                  vi: 'Nhập đủ 6 chữ số.',
                  en: 'Enter all 6 digits.',
                ),
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _verifying
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(tr(vi: 'Hủy', en: 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _verifying ? null : _verify,
                      child: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(tr(vi: 'Mở số dư', en: 'Show balance')),
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
