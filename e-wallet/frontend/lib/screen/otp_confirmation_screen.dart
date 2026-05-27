import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_localizations.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import 'receipt_screen.dart';

class OTPConfirmationScreen extends StatefulWidget {
  final String recipientIdentifier;
  final String recipientUserId;
  final int amount;
  final String message;
  final bool? preAssessedRequiresStepUp;
  final List<String> preAssessedRiskReasons;
  final String preAssessedRiskProbability;
  final bool isExternalCashFlow;
  final bool isTopup;
  final String fundingSourceId;
  final String externalPartner;
  final String counterpartyLabel;

  const OTPConfirmationScreen({
    super.key,
    required this.recipientIdentifier,
    required this.recipientUserId,
    required this.amount,
    required this.message,
    this.preAssessedRequiresStepUp,
    this.preAssessedRiskReasons = const <String>[],
    this.preAssessedRiskProbability = '',
  }) : isExternalCashFlow = false,
       isTopup = false,
       fundingSourceId = '',
       externalPartner = '',
       counterpartyLabel = '';

  const OTPConfirmationScreen.externalCashFlow({
    super.key,
    required this.isTopup,
    required this.fundingSourceId,
    required this.externalPartner,
    required this.counterpartyLabel,
    required this.amount,
    required this.message,
    this.preAssessedRequiresStepUp,
    this.preAssessedRiskReasons = const <String>[],
    this.preAssessedRiskProbability = '',
  }) : isExternalCashFlow = true,
       recipientIdentifier = '',
       recipientUserId = '';

  @override
  State<OTPConfirmationScreen> createState() => _OTPConfirmationScreenState();
}

class _OTPConfirmationScreenState extends State<OTPConfirmationScreen> {
  static const String _stepUpBypassOtpCode = '000000';
  static const int _stepUpFallbackHardAmount = 50 * 1000 * 1000;

  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _userService = UserService();

  int _remainingSeconds = 0;
  Timer? _timer;
  bool _isLoading = false;
  bool _assessingRisk = false;
  bool _requestingOtp = false;
  bool _stepUpRequired = false;
  String _latestOtpHint = '';
  String _otpDeliveryMode = '';
  Map<String, dynamic>? _pendingStepUpChallenge;
  String _pendingStepUpOtpCode = '';

  @override
  void initState() {
    super.initState();
    _initializeFlow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _clearOtpInputs() {
    for (final controller in _otpControllers) {
      controller.clear();
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

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = seconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Future<void> _initializeFlow() async {
    if (widget.isExternalCashFlow) {
      if (widget.preAssessedRequiresStepUp == true) {
        setState(() {
          _stepUpRequired = true;
          _pendingStepUpChallenge = null;
          _pendingStepUpOtpCode = '';
          _latestOtpHint = '';
          _otpDeliveryMode = 'email';
          _remainingSeconds = 0;
        });
        await _requestStepUpOtp(showMessage: false);
        return;
      }
      if (widget.preAssessedRequiresStepUp == false) {
        await _requestOtp(showMessage: false);
        return;
      }

      setState(() {
        _assessingRisk = true;
        _stepUpRequired = false;
      });
      final riskResult = await _userService.assessTransferRisk(
        recipientUserId: widget.fundingSourceId,
        recipientIdentifier: widget.counterpartyLabel,
        amount: widget.amount,
        currency: 'VND',
        isExternal: true,
        externalPartner: widget.externalPartner,
        externalAccountNo: widget.fundingSourceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _assessingRisk = false;
      });
      if (riskResult['success'] == true &&
          riskResult['requiresStepUp'] == true) {
        setState(() {
          _stepUpRequired = true;
          _pendingStepUpChallenge = null;
          _pendingStepUpOtpCode = '';
          _latestOtpHint = '';
          _otpDeliveryMode = 'email';
          _remainingSeconds = 0;
        });
        await _requestStepUpOtp(showMessage: false);
        return;
      }
      await _requestOtp(showMessage: false);
      return;
    }

    if (widget.preAssessedRequiresStepUp != null) {
      if (widget.preAssessedRequiresStepUp == true) {
        setState(() {
          _stepUpRequired = true;
          _pendingStepUpChallenge = null;
          _pendingStepUpOtpCode = '';
          _latestOtpHint = '';
          _otpDeliveryMode = 'email';
          _remainingSeconds = 0;
        });
        await _requestStepUpOtp(showMessage: false);
        return;
      }

      await _requestOtp(showMessage: false);
      return;
    }

    setState(() {
      _assessingRisk = true;
      _stepUpRequired = false;
    });

    final riskResult = await _userService.assessTransferRisk(
      recipientUserId: widget.recipientUserId,
      recipientIdentifier: widget.recipientIdentifier,
      amount: widget.amount,
      currency: 'VND',
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _assessingRisk = false;
    });

    if (riskResult['success'] != true) {
      if (widget.amount >= _stepUpFallbackHardAmount) {
        setState(() {
          _stepUpRequired = true;
          _pendingStepUpChallenge = null;
          _pendingStepUpOtpCode = '';
          _latestOtpHint = '';
          _otpDeliveryMode = 'email';
          _remainingSeconds = 0;
        });
        await _requestStepUpOtp(showMessage: false);
        return;
      }
      await _requestOtp(showMessage: false);
      return;
    }

    final requiresStepUp = riskResult['requiresStepUp'] == true;
    if (requiresStepUp) {
      setState(() {
        _stepUpRequired = true;
        _pendingStepUpChallenge = null;
        _pendingStepUpOtpCode = '';
        _latestOtpHint = '';
        _otpDeliveryMode = 'email';
        _remainingSeconds = 0;
      });
      await _requestStepUpOtp(showMessage: false);
      return;
    }

    await _requestOtp(showMessage: false);
  }

  Future<void> _requestOtp({required bool showMessage}) async {
    setState(() {
      _requestingOtp = true;
    });
    final result = await _userService.issueTransferOtp();
    if (!mounted) {
      return;
    }
    setState(() {
      _requestingOtp = false;
    });

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['message'] ?? AppLocalizations.pick(vi: 'Không thể cấp OTP', en: 'Unable to issue OTP')}',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    final expiresInRaw = result['expiresIn'];
    final expiresIn = expiresInRaw is int
        ? expiresInRaw
        : int.tryParse('$expiresInRaw') ?? 120;
    _startTimer(expiresIn <= 0 ? 120 : expiresIn);

    _clearOtpInputs();
    _otpFocusNodes.first.requestFocus();

    final otpCode = '${result['otpCode'] ?? ''}';
    final deliveryMode = '${result['deliveryMode'] ?? ''}'.trim().toLowerCase();
    setState(() {
      _otpDeliveryMode = deliveryMode;
    });
    if (otpCode.isNotEmpty) {
      setState(() {
        _latestOtpHint = otpCode;
      });
      _showOtpDialog(otpCode);
    } else if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'OTP đã được gửi. Nhập mã để tiếp tục.',
              en: 'OTP sent. Enter the code to continue.',
            ),
          ),
          backgroundColor: AppColors.violet600,
        ),
      );
    }
  }

  Future<void> _requestStepUpOtp({required bool showMessage}) async {
    setState(() {
      _requestingOtp = true;
    });
    final result = await _userService.issueStepUpToken(method: 'otp_email');
    if (!mounted) {
      return;
    }
    setState(() {
      _requestingOtp = false;
    });

    if (result['success'] != true) {
      _showFailureSnackBar(
        '${result['message'] ?? AppLocalizations.pick(vi: 'Không thể gửi OTP xác thực bổ sung.', en: 'Unable to send step-up OTP.')}',
      );
      return;
    }
    final expiresInRaw = result['expiresIn'];
    final expiresIn = expiresInRaw is int
        ? expiresInRaw
        : int.tryParse('$expiresInRaw') ?? 180;
    _startTimer(expiresIn <= 0 ? 180 : expiresIn);
    _clearOtpInputs();
    _otpFocusNodes.first.requestFocus();
    setState(() {
      _otpDeliveryMode = 'email';
      _latestOtpHint = '';
    });
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'OTP xác thực bổ sung đã được gửi qua email của bạn.',
              en: 'Step-up OTP has been sent to your email.',
            ),
          ),
          backgroundColor: AppColors.violet600,
        ),
      );
    }
  }

  void _showOtpDialog(String otpCode) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final tr = AppLocalizations.pick;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(tr(vi: 'Mã OTP', en: 'OTP code')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  vi: 'Mã OTP hiện tại của bạn:',
                  en: 'Your current OTP code:',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? scheme.surface.withValues(alpha: 0.86)
                      : AppColors.violet50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? scheme.outline : AppColors.violet600,
                  ),
                ),
                child: Text(
                  otpCode,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: isDark
                        ? scheme.primaryContainer
                        : AppColors.violet800,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(vi: 'Đóng', en: 'Close')),
            ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> _parseReceiptJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed receipt payloads in UI layer.
    }
    return <String, dynamic>{};
  }

  void _showFailureSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _handleVerifyAndTransfer() async {
    if (_isLoading || _assessingRisk) {
      return;
    }

    if (_stepUpRequired) {
      await _handleStepUpOnlyTransfer();
      return;
    }

    final otpCode = _otpControllers.map((e) => e.text).join();
    if (otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Vui lòng nhập đủ 6 số OTP',
              en: 'Please enter all 6 OTP digits.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    var result = await _submitTransaction(otpCode: otpCode);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });

    if (result['requiresStepUp'] == true) {
      setState(() {
        _stepUpRequired = true;
        _pendingStepUpChallenge = Map<String, dynamic>.from(result);
        _pendingStepUpOtpCode = otpCode;
        _otpDeliveryMode = 'email';
        _latestOtpHint = '';
      });
      unawaited(_requestStepUpOtp(showMessage: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Giao dịch cần OTP xác thực bổ sung qua email. Vui lòng nhập OTP rồi xác thực lại.',
              en: 'This transaction requires step-up OTP by email. Enter that OTP and verify again.',
            ),
          ),
          backgroundColor: AppColors.violet600,
        ),
      );
      return;
    }

    _handleSubmissionResult(result);
  }

  Future<void> _handleStepUpOnlyTransfer() async {
    final otpCode = _otpControllers.map((e) => e.text).join();
    if (otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Vui lòng nhập đủ 6 số OTP email.',
              en: 'Please enter all 6 email OTP digits.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    final tokenResult = await _userService.issueStepUpToken(
      method: 'otp_email',
      otpCode: otpCode,
    );
    if (!mounted) {
      return;
    }
    if (tokenResult['success'] != true) {
      setState(() {
        _isLoading = false;
      });
      _showFailureSnackBar(
        '${tokenResult['message'] ?? AppLocalizations.pick(vi: 'Không thể xác thực bổ sung.', en: 'Step-up verification failed.')}',
      );
      return;
    }

    final challenge = _pendingStepUpChallenge;
    final result = await _submitTransaction(
      otpCode: challenge == null ? _stepUpBypassOtpCode : _pendingStepUpOtpCode,
      stepUpToken: '${tokenResult['stepUpToken'] ?? ''}',
      idempotencyKey: challenge == null
          ? null
          : '${challenge['idempotencyKey'] ?? ''}',
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _pendingStepUpChallenge = null;
      _pendingStepUpOtpCode = '';
    });
    _clearOtpInputs();
    _handleSubmissionResult(result);
  }

  void _handleSubmissionResult(Map<String, dynamic> result) {
    if (result['success'] != true) {
      _showFailureSnackBar(
        '${result['message'] ?? AppLocalizations.pick(vi: 'Chuyển tiền thất bại', en: 'Transfer failed')}',
      );
      return;
    }

    final data = Map<String, dynamic>.from(
      (result['data'] as Map?) ?? <String, dynamic>{},
    );
    final receipt = widget.isExternalCashFlow
        ? _parseReceiptJson('${data['receiptJson'] ?? ''}')
        : (result['receipt'] == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(
                  (result['receipt'] as Map?) ?? <String, dynamic>{},
                ));

    final receiptTransactionStatus = '${data['status'] ?? 'PENDING'}';
    final receiptSettlementStatus = '${data['settlementStatus'] ?? 'PENDING'}';
    final receiptChainStatus = '${data['chainStatus'] ?? ''}';

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          recipient: widget.isExternalCashFlow
              ? widget.counterpartyLabel
              : widget.recipientIdentifier,
          amount: widget.amount,
          transactionDate: DateTime.now(),
          transactionId: '${data['transactionId'] ?? ''}',
          transactionStatus: receiptTransactionStatus,
          settlementStatus: receiptSettlementStatus,
          chainStatus: receiptChainStatus,
          chainTxId: '${receipt['tx_id'] ?? ''}',
          blockNumber: receipt['block_number'],
          blockHash:
              '${receipt['block_hash'] ?? receipt['receipt']?['block_hash'] ?? ''}',
          merkleRoot:
              '${receipt['receipt_hash'] ?? receipt['receipt']?['receipt_hash'] ?? ''}',
          commitmentHash:
              '${receipt['commitment_hash'] ?? receipt['receipt']?['commitment_hash'] ?? ''}',
          senderNote: widget.message,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _submitTransaction({
    required String otpCode,
    String? stepUpToken,
    String? idempotencyKey,
  }) {
    if (widget.isExternalCashFlow) {
      return widget.isTopup
          ? _userService.topupFromFundingSource(
              fundingSourceId: widget.fundingSourceId,
              amount: widget.amount,
              memo: widget.message,
              stepUpToken: stepUpToken,
              idempotencyKey: idempotencyKey,
            )
          : _userService.withdrawToFundingSource(
              fundingSourceId: widget.fundingSourceId,
              amount: widget.amount,
              memo: widget.message,
              stepUpToken: stepUpToken,
              idempotencyKey: idempotencyKey,
            );
    }
    return _userService.transferMoney(
      recipientUserId: widget.recipientUserId,
      recipientIdentifier: widget.recipientIdentifier,
      amount: widget.amount,
      message: widget.message,
      otpCode: otpCode,
      stepUpToken: stepUpToken,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBtnBg = isDark
        ? scheme.surface.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.88);
    final otpIconBg = isDark
        ? scheme.primary.withValues(alpha: 0.22)
        : AppColors.violet100;
    final otpIconColor = isDark ? scheme.primaryContainer : AppColors.violet700;
    final otpBoxBg = isDark ? scheme.surface : Colors.white;
    final otpBoxBorder = isDark
        ? scheme.outline.withValues(alpha: 0.85)
        : AppColors.violet200.withValues(alpha: 0.95);
    final detailBg = isDark
        ? scheme.surface.withValues(alpha: 0.82)
        : AppColors.violet50.withValues(alpha: 0.7);
    final detailBorder = isDark
        ? scheme.outline.withValues(alpha: 0.65)
        : AppColors.violet100.withValues(alpha: 0.9);
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final showOtpControls = true;
    final busy = _isLoading || _assessingRisk;
    final isEmailOtpFlow = _stepUpRequired || _otpDeliveryMode == 'email';
    final otpTitle = isEmailOtpFlow
        ? tr(
            vi: 'Nhập mã OTP được gửi\nvề email của bạn',
            en: 'Enter the OTP\nsent to your email',
          )
        : tr(
            vi: 'Nhập mã OTP để xác nhận giao dịch',
            en: 'Enter OTP to confirm this transaction',
          );
    final otpStatusText = _assessingRisk
        ? tr(vi: 'Đang kiểm tra giao dịch...', en: 'Checking transaction...')
        : (_latestOtpHint.isNotEmpty
              ? tr(
                  vi: 'Mã OTP hiện tại: $_latestOtpHint',
                  en: 'Current OTP: $_latestOtpHint',
                )
              : (isEmailOtpFlow
                    ? tr(
                        vi: 'Mã OTP đã gửi đến email của bạn.',
                        en: 'OTP has been sent to your email.',
                      )
                    : tr(
                        vi: 'Mã Smart OTP đã sẵn sàng. Vui lòng nhập để tiếp tục.',
                        en: 'Smart OTP is ready. Enter it to continue.',
                      )));

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Material(
                      color: headerBtnBg,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(vi: 'Xác nhận OTP', en: 'OTP confirmation'),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'BeVietnamPro',
                          color: titleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: otpIconBg,
                          ),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 36,
                            color: otpIconColor,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          otpTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'BeVietnamPro',
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          otpStatusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: subColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (showOtpControls) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(6, (index) {
                              return SizedBox(
                                width: 46,
                                height: 56,
                                child: TextFormField(
                                  controller: _otpControllers[index],
                                  focusNode: _otpFocusNodes[index],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'BeVietnamPro',
                                    color: titleColor,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor: otpBoxBg,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: otpBoxBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: scheme.primary,
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty && index < 5) {
                                      _otpFocusNodes[index + 1].requestFocus();
                                    } else if (value.isEmpty && index > 0) {
                                      _otpFocusNodes[index - 1].requestFocus();
                                    }
                                  },
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 12),
                          if (_remainingSeconds > 0)
                            Text(
                              tr(
                                vi: 'Gửi lại OTP sau ${_remainingSeconds}s',
                                en: 'Resend OTP in ${_remainingSeconds}s',
                              ),
                              style: TextStyle(
                                color: subColor,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _requestingOtp
                                  ? null
                                  : () => (_stepUpRequired
                                        ? _requestStepUpOtp(showMessage: true)
                                        : _requestOtp(showMessage: true)),
                              child: _requestingOtp
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      tr(vi: 'Gửi lại OTP', en: 'Resend OTP'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: detailBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: detailBorder),
                          ),
                          child: Column(
                            children: [
                              _DetailRow(
                                labelColor: subColor,
                                valueColor: titleColor,
                                label: widget.isExternalCashFlow
                                    ? tr(vi: 'Đối tác', en: 'Partner')
                                    : tr(vi: 'Người nhận', en: 'Recipient'),
                                value: widget.isExternalCashFlow
                                    ? widget.counterpartyLabel
                                    : widget.recipientIdentifier,
                              ),
                              const SizedBox(height: 10),
                              _DetailRow(
                                labelColor: subColor,
                                valueColor: titleColor,
                                label: tr(vi: 'Số tiền', en: 'Amount'),
                                value: '${_formatMoney(widget.amount)}đ',
                              ),
                              const SizedBox(height: 10),
                              _DetailRow(
                                labelColor: subColor,
                                valueColor: titleColor,
                                label: tr(vi: 'Nội dung', en: 'Message'),
                                value: widget.message.isEmpty
                                    ? tr(vi: '(Không có)', en: '(None)')
                                    : widget.message,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: busy ? null : _handleVerifyAndTransfer,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.verified_rounded),
                            label: Text(
                              _assessingRisk
                                  ? tr(
                                      vi: 'Đang phân tích rủi ro...',
                                      en: 'Analyzing risk...',
                                    )
                                  : _isLoading
                                  ? tr(
                                      vi: 'Đang xác thực...',
                                      en: 'Verifying...',
                                    )
                                  : tr(vi: 'Xác thực', en: 'Verify'),
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: labelColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
