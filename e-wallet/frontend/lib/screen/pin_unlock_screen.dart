import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_dropdown.dart';
import '../widgets/pin_code_boxes.dart';

class PinUnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final Future<void> Function() onUsePassword;
  final bool sessionExpired;

  const PinUnlockScreen({
    super.key,
    required this.onUnlocked,
    required this.onUsePassword,
    this.sessionExpired = false,
  });

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _settings = AppSettingsService();
  final _pinController = TextEditingController();

  bool _verifying = false;
  String _userLabel = 'Người dùng';
  String? _pinErrorText;
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _loadUserLabel();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadUserLabel() async {
    final t = AppLocalizations.text;
    final user = await _authService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _userLabel = '${user?['displayName'] ?? user?['email'] ?? t('user_generic')}'
          .trim();
      if (_userLabel.isEmpty) _userLabel = t('user_generic');
    });
  }

  Future<void> _unlockWithPin() async {
    final t = AppLocalizations.text;
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _pinErrorText = t('pin_exact_6'));
      return;
    }

    setState(() {
      _verifying = true;
      _pinErrorText = null;
    });

    // Refresh session first to ensure we have a valid token for PIN verification
    final refreshed = await _authService.refreshSession(
      triggerExpiredEventOnFailure: false,
    );
    if (!mounted) return;

    if (refreshed['success'] != true) {
      setState(() {
        _verifying = false;
        _pinErrorText = t('session_expired_login_again');
      });
      await widget.onUsePassword();
      return;
    }

    // Verify PIN against server
    final valid = await _authService.verifyServerPin(pin);
    if (!mounted) return;
    setState(() => _verifying = false);

    if (!valid) {
      _pinController.clear();
      setState(() => _pinErrorText = t('pin_incorrect'));
      return;
    }

    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A0E1F), Color(0xFF6D1128), Color(0xFF8C1E37)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: compact ? 16 : 32),
                    Align(
                      alignment: Alignment.topRight,
                      child: LanguageDropdown(
                        settings: _settings,
                        onChanged: () {
                          if (!mounted) return;
                          _loadUserLabel();
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Floating cat logo
                    Center(
                      child: AnimatedBuilder(
                        animation: _floatAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _floatAnimation.value),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(
                                      alpha:
                                          0.15 +
                                          0.06 *
                                              ((_floatAnimation.value + 5) /
                                                  10),
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/images/sleepy_cat.png',
                            width: compact ? 120 : 150,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Kufi',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 26 : 30,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'BeVietnamPro',
                        letterSpacing: 1.5,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 32),

                    // PIN card
                    Container(
                      padding: EdgeInsets.all(compact ? 20 : 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.sessionExpired) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.timer_off_rounded,
                                    size: 18,
                                    color: AppColors.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t('session_expired_unlock'),
                                      style: TextStyle(
                                        fontSize: compact ? 12 : 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            t('pin_unlock_wallet_title'),
                            style: TextStyle(
                              fontSize: compact ? 22 : 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'BeVietnamPro',
                              color: AppColors.ink900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.ink700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),

                          PinCodeBoxes(
                            controller: _pinController,
                            enabled: !_verifying,
                            autofocus: true,
                            label: t('pin_unlock_enter_pin'),
                            errorText: _pinErrorText,
                            onChanged: (_) {
                              if (_pinErrorText != null) {
                                setState(() => _pinErrorText = null);
                              }
                            },
                            onCompleted: (_) => _unlockWithPin(),
                          ),

                          const SizedBox(height: 24),

                          _AltOption(
                            icon: Icons.email_outlined,
                            label: t('relogin'),
                            onTap: widget.onUsePassword,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t('secured_by_kufi'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'BeVietnamPro',
                          ),
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
    );
  }
}

class _AltOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AltOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.vanilla50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, size: 22, color: AppColors.violet600),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
