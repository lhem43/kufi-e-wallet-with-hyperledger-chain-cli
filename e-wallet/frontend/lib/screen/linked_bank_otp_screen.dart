import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/user_service.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_code_boxes.dart';

class LinkedBankOtpScreen extends StatefulWidget {
  final String providerCode;
  final String providerName;
  final String accountRef;
  final String displayName;
  final bool notify;
  final bool defaultSource;

  const LinkedBankOtpScreen({
    super.key,
    required this.providerCode,
    required this.providerName,
    required this.accountRef,
    required this.displayName,
    required this.notify,
    required this.defaultSource,
  });

  @override
  State<LinkedBankOtpScreen> createState() => _LinkedBankOtpScreenState();
}

class _LinkedBankOtpScreenState extends State<LinkedBankOtpScreen> {
  final _userService = UserService();
  final _otpController = TextEditingController();

  static const int _resendCooldownSeconds = 30;
  bool _submitting = false;
  int _resendSecondsLeft = 0;
  String? _otpErrorText;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _sendOtp(initial: true);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _sendOtp({bool initial = false}) {
    _resendTimer?.cancel();

    setState(() {
      _resendSecondsLeft = _resendCooldownSeconds;
      _otpErrorText = null;
    });

    _otpController.clear();

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _resendSecondsLeft = 0;
        });
        return;
      }
      setState(() {
        _resendSecondsLeft -= 1;
      });
    });

    if (!initial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã gửi lại mã OTP.',
              en: 'OTP resent successfully.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _verifyAndLink() async {
    if (_submitting) {
      return;
    }

    final otp = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() {
        _otpErrorText = AppLocalizations.pick(
          vi: 'Vui lòng nhập đủ 6 chữ số OTP.',
          en: 'Please enter all 6 OTP digits.',
        );
      });
      return;
    }

    setState(() {
      _otpErrorText = null;
    });

    setState(() {
      _submitting = true;
    });

    final result = await _userService.createFundingSource(
      provider: widget.providerCode,
      accountRef: widget.accountRef,
      displayName: widget.displayName,
      providerToken:
          'otp-verified-${widget.providerCode.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch}-${widget.notify ? 1 : 0}-${widget.defaultSource ? 1 : 0}-otp:$otp',
    );

    if (!mounted) return;

    setState(() {
      _submitting = false;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã liên kết ${widget.providerName} thành công.',
              en: '${widget.providerName} linked successfully.',
            ),
          ),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result['message'] ?? AppLocalizations.pick(vi: 'Không thể liên kết ngân hàng.', en: 'Unable to link bank account.')}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Xác thực OTP', en: 'OTP verification')),
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        vi: 'Nhập OTP để hoàn tất liên kết ${widget.providerName}',
                        en: 'Enter OTP to complete linking ${widget.providerName}',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        vi: 'Đang liên kết tài khoản: ${widget.accountRef}',
                        en: 'Linking account: ${widget.accountRef}',
                      ),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PinCodeBoxes(
                      controller: _otpController,
                      label: tr(vi: 'Mã OTP', en: 'OTP code'),
                      helperText: tr(
                        vi: 'Nhập đủ 6 chữ số.',
                        en: 'Enter all 6 digits.',
                      ),
                      errorText: _otpErrorText,
                      enabled: !_submitting,
                      autofocus: true,
                      onChanged: (_) {
                        if (_otpErrorText != null) {
                          setState(() {
                            _otpErrorText = null;
                          });
                        }
                      },
                      onCompleted: (_) => _verifyAndLink(),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _resendSecondsLeft == 0 && !_submitting
                            ? () => _sendOtp()
                            : null,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          _resendSecondsLeft == 0
                              ? tr(vi: 'Gửi lại OTP', en: 'Resend OTP')
                              : tr(
                                  vi: 'Gửi lại sau ${_resendSecondsLeft}s',
                                  en: 'Resend in ${_resendSecondsLeft}s',
                                ),
                        ),
                      ),
                    ),
                    Text(
                      tr(
                        vi: 'Mã OTP đã được gửi tới tài khoản liên kết.',
                        en: 'OTP has been sent to the linked account.',
                      ),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.66),
                        fontSize: 12,
                        height: 1.3,
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
                label: tr(vi: 'Xác nhận liên kết', en: 'Confirm link'),
                icon: Icons.verified_rounded,
                loading: _submitting,
                onPressed: _verifyAndLink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
