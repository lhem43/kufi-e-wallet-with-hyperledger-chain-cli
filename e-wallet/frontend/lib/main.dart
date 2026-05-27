import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screen/home_screen.dart';
import 'screen/login_page.dart';
import 'screen/pin_setup_screen.dart';
import 'screen/pin_unlock_screen.dart';
import 'services/app_localizations.dart';
import 'services/app_settings_service.dart';
import 'services/auth_service.dart';
import 'services/idle_timeout_service.dart';
import 'services/pin_session_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Optional in local runs; runtime config can come from --dart-define.
  }
  runApp(const WalletApp());
}

enum _AppStage { loading, unauthenticated, pinSetup, pinUnlock, authenticated }

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});

  @override
  State<WalletApp> createState() => _WalletAppState();
}

class _WalletAppState extends State<WalletApp> {
  final AuthService _authService = AuthService();
  final IdleTimeoutService _idleService = IdleTimeoutService();
  final AppSettingsService _settings = AppSettingsService();
  _AppStage _stage = _AppStage.loading;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _idleService.stop();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      await _settings.load();
      final loggedIn = await _authService.isLoggedIn();
      if (!loggedIn) {
        _setStage(_AppStage.unauthenticated);
        return;
      }

      // Refresh session up-front to avoid immediate "session expired" after PIN.
      final refreshed = await _authService.refreshSession(
        triggerExpiredEventOnFailure: false,
      );
      if (refreshed['success'] != true) {
        await _authService.clearLocalSession();
        _setStage(_AppStage.unauthenticated);
        return;
      }

      // Check if user has PIN set (server-side via user data)
      final user = await _authService.getCurrentUser();
      final hasPin = user?['hasPin'] == true;

      if (!hasPin) {
        // No PIN set — user must set one before continuing
        _setStage(_AppStage.pinSetup);
      } else {
        _setStage(_AppStage.pinUnlock);
      }
    } catch (_) {
      _setStage(_AppStage.unauthenticated);
    }
  }

  void _setStage(_AppStage next) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = next;
    });
    // Start idle timer when authenticated, stop otherwise
    if (next == _AppStage.authenticated) {
      _idleService.start(onTimeout: _onIdleTimeout);
    } else {
      _idleService.stop();
    }
  }

  void _onIdleTimeout() {
    if (!mounted) return;
    PinSessionService().clear();
    // Since PIN is mandatory, always go to PIN unlock on idle timeout
    setState(() => _sessionExpired = true);
    _setStage(_AppStage.pinUnlock);
  }

  void _onUserActivity() {
    _idleService.resetTimer();
  }

  void _onUnlocked() {
    _sessionExpired = false;
    // User entered PIN to unlock, so mark balance as unlocked for this session
    PinSessionService().markBalanceUnlocked();
    _setStage(_AppStage.authenticated);
  }

  Future<void> _onUsePassword() async {
    PinSessionService().clear();
    await _authService.clearLocalSession();
    _setStage(_AppStage.unauthenticated);
  }

  void _onLoginSuccess() {
    // Re-bootstrap after successful email/password login so PIN check runs.
    PinSessionService().clear();
    _setStage(_AppStage.loading);
    _bootstrapAfterLogin();
  }

  /// Lighter bootstrap after login — session is already saved, just check PIN.
  Future<void> _bootstrapAfterLogin() async {
    try {
      final user = await _authService.getCurrentUser();
      final hasPin = user?['hasPin'] == true;
      if (!hasPin) {
        // No PIN set — redirect to PIN setup (mandatory)
        _setStage(_AppStage.pinSetup);
      } else {
        // Has PIN — user already just logged in with password, go straight to authenticated
        // Balance is still locked — user needs to enter PIN to reveal it
        _setStage(_AppStage.authenticated);
      }
    } catch (_) {
      _setStage(_AppStage.authenticated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      child: MaterialApp(
        title: 'e_wallet_app',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
        ),
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _stage == _AppStage.unauthenticated
            ? ThemeMode.light
            : _settings.themeMode,
        locale: Locale(_settings.language),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: switch (_stage) {
          _AppStage.loading => const _BootLoadingView(),
          _AppStage.unauthenticated => LoginPage(
            onLoginSuccess: _onLoginSuccess,
          ),
          _AppStage.pinSetup => PinSetupScreen(
            onComplete: () {
              PinSessionService().markBalanceUnlocked();
              _setStage(_AppStage.authenticated);
            },
          ),
          _AppStage.pinUnlock => PinUnlockScreen(
            onUnlocked: _onUnlocked,
            onUsePassword: _onUsePassword,
            sessionExpired: _sessionExpired,
          ),
          _AppStage.authenticated => HomeScreen(
            onLogout: () {
              PinSessionService().clear();
              _setStage(_AppStage.unauthenticated);
            },
          ),
        },
      ),
    );
  }
}

class _BootLoadingView extends StatelessWidget {
  const _BootLoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.text('boot_loading'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink700,
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
