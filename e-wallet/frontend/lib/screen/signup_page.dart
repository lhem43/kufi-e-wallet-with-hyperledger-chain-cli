import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import 'home_screen.dart';
import 'pin_setup_screen.dart';

enum _AvailabilityState {
  idle,
  checking,
  available,
  unavailable,
  invalid,
  error,
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  final _settings = AppSettingsService();

  Timer? _phoneDebounce;
  Timer? _emailDebounce;
  Timer? _otpCountdownTimer;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;

  _AvailabilityState _phoneState = _AvailabilityState.idle;
  _AvailabilityState _emailState = _AvailabilityState.idle;

  String _phoneMessage = '';
  String _emailMessage = '';

  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _otpInvalid = false;
  String _otpDraft = '';
  int _resendSeconds = 0;
  String _lastVerifiedOtp = '';

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(fn);
        }
      });
      return;
    }
    setState(fn);
  }

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _emailDebounce?.cancel();
    _otpCountdownTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  String _normalizePhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.startsWith('84') && digitsOnly.length == 11) {
      return '0${digitsOnly.substring(2)}';
    }
    return digitsOnly;
  }

  bool _isReadyPhone(String value) {
    return RegExp(r'^(0\d{9,10}|84\d{8,10})$').hasMatch(value);
  }

  bool _looksLikeEmail(String value) {
    return RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$",
    ).hasMatch(value.trim().toLowerCase());
  }

  void _resetOtpState({bool keepCountdown = false}) {
    _otpSent = false;
    _otpVerified = false;
    _otpInvalid = false;
    _verifyingOtp = false;
    _otpDraft = '';
    _lastVerifiedOtp = '';
    if (!keepCountdown) {
      _otpCountdownTimer?.cancel();
      _resendSeconds = 0;
    }
  }

  void _onPhoneChanged(String raw) {
    final t = AppLocalizations.text;
    final normalized = _normalizePhone(raw);

    _phoneDebounce?.cancel();

    if (normalized.isEmpty) {
      _safeSetState(() {
        _phoneState = _AvailabilityState.idle;
        _phoneMessage = '';
      });
      return;
    }

    if (!_isReadyPhone(normalized)) {
      _safeSetState(() {
        _phoneState = _AvailabilityState.invalid;
        _phoneMessage = t('phone_invalid');
      });
      return;
    }

    _safeSetState(() {
      _phoneState = _AvailabilityState.checking;
      _phoneMessage = '';
    });

    _phoneDebounce = Timer(const Duration(milliseconds: 450), () async {
      final result = await _authService.checkSignUpAvailability(
        phone: normalized,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        _safeSetState(() {
          _phoneState = _AvailabilityState.error;
          _phoneMessage = t('check_information_error');
        });
        return;
      }

      if (result['phoneValid'] != true) {
        _safeSetState(() {
          _phoneState = _AvailabilityState.invalid;
          _phoneMessage = t('phone_invalid');
        });
        return;
      }

      final available = result['phoneAvailable'] == true;
      _safeSetState(() {
        _phoneState = available
            ? _AvailabilityState.available
            : _AvailabilityState.unavailable;
        _phoneMessage = available ? '' : t('phone_in_use');
      });
    });
  }

  void _onEmailChanged(String raw) {
    final t = AppLocalizations.text;
    final normalized = raw.trim().toLowerCase();

    _emailDebounce?.cancel();
    _resetOtpState();

    if (normalized.isEmpty) {
      _safeSetState(() {
        _emailState = _AvailabilityState.idle;
        _emailMessage = '';
      });
      return;
    }

    if (!_looksLikeEmail(normalized)) {
      _safeSetState(() {
        _emailState = _AvailabilityState.invalid;
        _emailMessage = t('email_invalid');
      });
      return;
    }

    _safeSetState(() {
      _emailState = _AvailabilityState.checking;
      _emailMessage = '';
    });

    _emailDebounce = Timer(const Duration(milliseconds: 450), () async {
      final result = await _authService.checkSignUpAvailability(
        email: normalized,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        _safeSetState(() {
          _emailState = _AvailabilityState.error;
          _emailMessage = t('check_information_error');
        });
        return;
      }

      if (result['emailValid'] != true) {
        _safeSetState(() {
          _emailState = _AvailabilityState.invalid;
          _emailMessage = t('email_invalid');
        });
        return;
      }

      final available = result['emailAvailable'] == true;
      _safeSetState(() {
        _emailState = available
            ? _AvailabilityState.available
            : _AvailabilityState.unavailable;
        _emailMessage = available ? '' : t('email_in_use');
      });
    });
  }

  Widget? _availabilitySuffix(_AvailabilityState state) {
    switch (state) {
      case _AvailabilityState.checking:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _AvailabilityState.available:
        return const Icon(Icons.check_circle_rounded, color: AppColors.success);
      case _AvailabilityState.unavailable:
      case _AvailabilityState.invalid:
      case _AvailabilityState.error:
        return const Icon(Icons.cancel_rounded, color: AppColors.danger);
      case _AvailabilityState.idle:
        return null;
    }
  }

  void _startOtpCountdown(int fromSeconds) {
    _otpCountdownTimer?.cancel();
    _safeSetState(() => _resendSeconds = fromSeconds);
    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        _safeSetState(() => _resendSeconds = 0);
      } else {
        _safeSetState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (_emailState != _AvailabilityState.available ||
        !_looksLikeEmail(email)) {
      return;
    }

    _safeSetState(() {
      _sendingOtp = true;
      _otpSent = false;
      _otpInvalid = false;
    });
    _startOtpCountdown(60);
    final result = await _authService.sendSignUpEmailOtp(email);
    if (!mounted) return;
    _safeSetState(() => _sendingOtp = false);

    if (result['success'] != true) {
      _otpCountdownTimer?.cancel();
      _safeSetState(() => _resendSeconds = 0);
      _showError(
        '${result['message'] ?? AppLocalizations.text('check_information_error')}',
      );
      return;
    }

    _safeSetState(() {
      _otpSent = true;
      _otpInvalid = false;
      _otpVerified = false;
      _lastVerifiedOtp = '';
    });
  }

  Future<void> _verifyOtpIfReady() async {
    final code = _otpDraft.trim();
    if (code.length != 6 || _verifyingOtp || code == _lastVerifiedOtp) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (_emailState != _AvailabilityState.available ||
        !_looksLikeEmail(email)) {
      return;
    }

    _safeSetState(() => _verifyingOtp = true);
    final result = await _authService.verifySignUpEmailOtp(
      email: email,
      otpCode: code,
    );
    if (!mounted) return;

    final valid = result['valid'] == true;
    _safeSetState(() {
      _verifyingOtp = false;
      _otpVerified = valid;
      _otpInvalid = !valid;
      _lastVerifiedOtp = code;
    });
  }

  Future<void> _handleSignUp() async {
    final t = AppLocalizations.text;
    if (!_formKey.currentState!.validate()) return;

    if (_phoneState != _AvailabilityState.available) {
      _showError(_phoneMessage.isNotEmpty ? _phoneMessage : t('phone_in_use'));
      return;
    }
    if (_emailState != _AvailabilityState.available) {
      _showError(_emailMessage.isNotEmpty ? _emailMessage : t('email_in_use'));
      return;
    }
    if (!_otpVerified) {
      _showError(t('email_otp_required'));
      return;
    }

    if (!_agreeToTerms) {
      _showError(t('agree_terms_error'));
      return;
    }

    final finalCheck = await _authService.checkSignUpAvailability(
      email: _emailController.text.trim().toLowerCase(),
      phone: _normalizePhone(_phoneController.text),
    );
    if (finalCheck['success'] != true ||
        finalCheck['emailAvailable'] != true ||
        finalCheck['phoneAvailable'] != true) {
      _showError(t('check_information_error'));
      return;
    }

    _safeSetState(() => _isLoading = true);

    final result = await _authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      phone: _normalizePhone(_phoneController.text),
    );

    if (!mounted) return;
    _safeSetState(() => _isLoading = false);

    if (result['success'] == true) {
      final nav = Navigator.of(context);
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => PinSetupScreen(
            onComplete: () {
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
          ),
        ),
      );
      return;
    }

    _showError('${result['message'] ?? t('signup_failed')}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;

    final otpSuffix = _verifyingOtp
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : (_otpVerified
              ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
              : (_otpInvalid
                    ? const Icon(Icons.cancel_rounded, color: AppColors.danger)
                    : null));

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                    ),
                    Expanded(
                      child: Text(
                        t('signup_page_title'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.ink900,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: t('language'),
                      onSelected: (value) => _settings.setLanguage(value),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'vi',
                          child: Text('🇻🇳 ${t('vietnamese')}'),
                        ),
                        PopupMenuItem(
                          value: 'en',
                          child: Text('🇺🇸 ${t('english')}'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.violet100.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.language_rounded,
                              color: AppColors.violet700,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _settings.language == 'vi' ? 'VI' : 'EN',
                              style: const TextStyle(
                                color: AppColors.violet700,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 14 : 20,
                        vertical: 8,
                      ),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 16 : 22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.momoPink,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.person_add_alt_1_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t('signup_header'),
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              fontFamily: 'BeVietnamPro',
                                              color: AppColors.ink900,
                                            ),
                                          ),
                                          Text(
                                            t('signup_hint'),
                                            style: const TextStyle(
                                              color: AppColors.ink500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    labelText: t('full_name'),
                                    prefixIcon: const Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return t('full_name_required');
                                    }
                                    if (v.trim().length < 3) {
                                      return t('full_name_min');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  onChanged: _onEmailChanged,
                                  decoration: InputDecoration(
                                    labelText: t('email'),
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                    ),
                                    suffixIcon: _availabilitySuffix(
                                      _emailState,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return t('email_required');
                                    }
                                    if (!_looksLikeEmail(v)) {
                                      return t('email_invalid');
                                    }
                                    if (_emailState ==
                                        _AvailabilityState.unavailable) {
                                      return t('email_in_use');
                                    }
                                    return null;
                                  },
                                ),
                                if (_emailMessage.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _emailMessage,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (_emailState ==
                                    _AvailabilityState.available) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 96,
                                          maxWidth: 108,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, btnConstraints) {
                                            final idleLabel =
                                                btnConstraints.maxWidth >= 104
                                                ? t('send_otp')
                                                : 'Gửi';
                                            return SizedBox(
                                              height: 50,
                                              child: AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                opacity:
                                                    (_sendingOtp ||
                                                        _resendSeconds > 0)
                                                    ? 0.6
                                                    : 1,
                                                child: FilledButton(
                                                  onPressed:
                                                      (_sendingOtp ||
                                                          _resendSeconds > 0)
                                                      ? null
                                                      : _sendOtp,
                                                  child: Text(
                                                    _resendSeconds > 0
                                                        ? '${_resendSeconds}s'
                                                        : idleLabel,
                                                    textAlign: TextAlign.center,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          keyboardType: TextInputType.number,
                                          maxLength: 6,
                                          onChanged: (value) {
                                            _otpDraft = value;
                                            if (value.length < 6) {
                                              _safeSetState(() {
                                                _otpVerified = false;
                                                _otpInvalid = false;
                                                _lastVerifiedOtp = '';
                                              });
                                              return;
                                            }
                                            _verifyOtpIfReady();
                                          },
                                          decoration: InputDecoration(
                                            counterText: '',
                                            labelText: t('email_otp_code'),
                                            suffixIcon: otpSuffix,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_otpInvalid) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      t('email_otp_invalid'),
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ] else if (_otpSent) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      t('otp_sent_success'),
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  onChanged: _onPhoneChanged,
                                  decoration: InputDecoration(
                                    labelText: t('phone'),
                                    prefixIcon: const Icon(
                                      Icons.phone_outlined,
                                    ),
                                    suffixIcon: _availabilitySuffix(
                                      _phoneState,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return t('phone_required');
                                    }
                                    final digits = v.replaceAll(
                                      RegExp(r'[^\d]'),
                                      '',
                                    );
                                    if (!_isReadyPhone(digits)) {
                                      return t('phone_invalid');
                                    }
                                    if (_phoneState ==
                                        _AvailabilityState.unavailable) {
                                      return t('phone_in_use');
                                    }
                                    return null;
                                  },
                                ),
                                if (_phoneMessage.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _phoneMessage,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: t('password'),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return t('password_required');
                                    }
                                    if (v.length < 6) {
                                      return t('password_min');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: _obscureConfirm,
                                  decoration: InputDecoration(
                                    labelText: t('confirm_password'),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () =>
                                            _obscureConfirm = !_obscureConfirm,
                                      ),
                                      icon: Icon(
                                        _obscureConfirm
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return t('confirm_password_required');
                                    }
                                    if (v != _passwordController.text) {
                                      return t('password_mismatch');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _agreeToTerms,
                                        onChanged: (v) => setState(
                                          () => _agreeToTerms = v ?? false,
                                        ),
                                        activeColor: AppColors.violet600,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Wrap(
                                        children: [
                                          Text(
                                            t('agree_with'),
                                            style: const TextStyle(
                                              color: AppColors.ink700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {},
                                            child: Text(
                                              t('terms_of_use'),
                                              style: const TextStyle(
                                                color: AppColors.violet600,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            t('and'),
                                            style: const TextStyle(
                                              color: AppColors.ink700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {},
                                            child: Text(
                                              t('privacy_policy'),
                                              style: const TextStyle(
                                                color: AppColors.violet600,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: GradientButton(
                                    label: t('sign_up_action'),
                                    icon: Icons.how_to_reg_rounded,
                                    loading: _isLoading,
                                    onPressed: _isLoading
                                        ? null
                                        : _handleSignUp,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      t('has_account'),
                                      style: const TextStyle(
                                        color: AppColors.ink700,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text(t('login_now')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
