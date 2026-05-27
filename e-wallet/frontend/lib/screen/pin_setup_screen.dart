import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_code_boxes.dart';
import 'home_screen.dart';

/// Standalone screen for setting up a 6-digit PIN after registration.
class PinSetupScreen extends StatefulWidget {
  /// Called after the user saves their PIN (or skips).
  final VoidCallback onComplete;

  const PinSetupScreen({super.key, required this.onComplete});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _authService = AuthService();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(
        () => _errorText = AppLocalizations.pick(
          vi: 'PIN phải gồm đúng 6 chữ số.',
          en: 'PIN must be exactly 6 digits.',
        ),
      );
      return;
    }
    if (confirm != pin) {
      setState(
        () => _errorText = AppLocalizations.pick(
          vi: 'PIN xác nhận không khớp.',
          en: 'PIN confirmation does not match.',
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      // Save PIN to server (primary storage)
      final result = await _authService.setServerPin(pin: pin);
      if (result['success'] != true) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _errorText =
              '${result['message'] ?? AppLocalizations.pick(vi: 'Không thể lưu PIN lúc này.', en: 'Unable to save PIN right now.')}';
        });
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = AppLocalizations.pick(
          vi: 'Không thể lưu PIN lúc này. Vui lòng thử lại.',
          en: 'Unable to save PIN right now. Please try again.',
        );
      });
      return;
    }

    // PIN saved — show feedback and navigate away.
    if (!mounted) return;
    try {
      widget.onComplete();
    } catch (_) {
      // Caller's callback may throw (e.g. stale context).
      // PIN is already saved, so just navigate to home as fallback.
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 20,
                  vertical: 24,
                ),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 18 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Icon
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.momoPink,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          tr(
                            vi: 'Thiết lập PIN bảo mật',
                            en: 'Set up security PIN',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'BeVietnamPro',
                            color: AppColors.ink900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            vi: 'Tạo PIN 6 số để đăng nhập nhanh và bảo vệ tài khoản của bạn.',
                            en: 'Create a 6-digit PIN for quick sign-in and account protection.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.ink500,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        PinCodeBoxes(
                          controller: _pinController,
                          enabled: !_saving,
                          autofocus: true,
                          label: tr(vi: 'PIN mới', en: 'New PIN'),
                          helperText: tr(
                            vi: 'Nhập PIN 6 số.',
                            en: 'Enter 6-digit PIN.',
                          ),
                          errorText: _errorText,
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        PinCodeBoxes(
                          controller: _confirmController,
                          enabled: !_saving,
                          label: tr(vi: 'Xác nhận PIN', en: 'Confirm PIN'),
                          helperText: tr(
                            vi: 'Nhập lại PIN.',
                            en: 'Re-enter PIN.',
                          ),
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                          onCompleted: (_) => _submit(),
                        ),
                        const SizedBox(height: 24),
                        GradientButton(
                          label: tr(vi: 'Xác nhận PIN', en: 'Confirm PIN'),
                          icon: Icons.check_circle_rounded,
                          loading: _saving,
                          onPressed: _saving ? null : _submit,
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
    );
  }
}
