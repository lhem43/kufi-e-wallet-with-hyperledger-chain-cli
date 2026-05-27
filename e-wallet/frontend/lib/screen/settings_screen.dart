import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

/// Sub-screen: Cài đặt — notification settings, theme mode, language.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _notificationService = NotificationService();
  final _settings = AppSettingsService();

  bool _loading = true;
  bool _saving = false;
  bool _emailNotificationsEnabled = false;
  bool _smsNotificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final result = await _notificationService.getNotificationSettings();
    if (!mounted) return;
    if (result['success'] == true) {
      final s = Map<String, dynamic>.from(
        (result['settings'] as Map?) ?? <String, dynamic>{},
      );
      setState(() {
        _emailNotificationsEnabled = s['emailEnabled'] == true;
        _smsNotificationsEnabled = s['smsEnabled'] == true;
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _updateNotification({bool? email, bool? sms}) async {
    if (email == null && sms == null) return;
    setState(() => _saving = true);
    final result = await _notificationService.updateNotificationSettings(
      emailEnabled: email,
      smsEnabled: sms,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      final s = Map<String, dynamic>.from(
        (result['settings'] as Map?) ?? <String, dynamic>{},
      );
      setState(() {
        _emailNotificationsEnabled = s['emailEnabled'] == true;
        _smsNotificationsEnabled = s['smsEnabled'] == true;
      });
    } else {
      await _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    return Scaffold(
      appBar: AppBar(title: Text(t('settings_title'))),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // Notification settings
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: Icons.notifications_outlined,
                            title: t('notifications'),
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _emailNotificationsEnabled,
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(
                                      () => _emailNotificationsEnabled = v,
                                    );
                                    _updateNotification(email: v);
                                  },
                            title: Text(t('email_notifications')),
                            subtitle: Text(t('email_notifications_hint')),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _smsNotificationsEnabled,
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (v) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            t('feature_in_development'),
                                          ),
                                        ),
                                      );
                                      setState(
                                        () => _smsNotificationsEnabled = false,
                                      );
                                      return;
                                    }
                                    setState(
                                      () => _smsNotificationsEnabled = false,
                                    );
                                    _updateNotification(sms: false);
                                  },
                            title: Text(t('sms_notifications')),
                            subtitle: Text(t('sms_notifications_hint')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Appearance ──
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: _settings.isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            title: t('appearance'),
                          ),
                          const SizedBox(height: 14),
                          _SelectableOption(
                            icon: Icons.light_mode_rounded,
                            label: t('light'),
                            selected: !_settings.isDark,
                            onTap: () {
                              _settings.setThemeMode(ThemeMode.light);
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          _SelectableOption(
                            icon: Icons.dark_mode_rounded,
                            label: t('dark'),
                            selected: _settings.isDark,
                            onTap: () {
                              _settings.setThemeMode(ThemeMode.dark);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Language
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: Icons.language_rounded,
                            title: t('language'),
                          ),
                          const SizedBox(height: 14),
                          _LanguageOption(
                            label: t('vietnamese'),
                            languageCode: 'vi',
                            selected: _settings.language == 'vi',
                            onTap: () async {
                              await _settings.setLanguage('vi');
                              if (!mounted) return;
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          _LanguageOption(
                            label: t('english'),
                            languageCode: 'en',
                            selected: _settings.language == 'en',
                            onTap: () async {
                              await _settings.setLanguage('en');
                              if (!mounted) return;
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // About
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('app_info'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(label: t('version'), value: '1.0.0'),
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: t('blockchain'),
                            value: 'Hyperledger Fabric',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ],
    );
  }
}

class _SelectableOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
          : (isDark
                ? Colors.white.withValues(alpha: 0.05)
                : AppColors.vanilla50),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? scheme.primary : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String label;
  final String languageCode;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.label,
    required this.languageCode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
          : (isDark
                ? Colors.white.withValues(alpha: 0.05)
                : AppColors.vanilla50),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _FlagIcon(languageCode: languageCode),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagIcon extends StatelessWidget {
  final String languageCode;

  const _FlagIcon({required this.languageCode});

  @override
  Widget build(BuildContext context) {
    final assetPath = languageCode == 'vi'
        ? 'assets/images/flags/vn.png'
        : 'assets/images/flags/us.png';
    return Container(
      width: 24,
      height: 18,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : AppColors.ink500,
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
