import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

class LanguageDropdown extends StatelessWidget {
  final AppSettingsService settings;
  final VoidCallback? onChanged;

  const LanguageDropdown({
    super.key,
    required this.settings,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final current = settings.language == 'en' ? 'en' : 'vi';
    final compactCode = current == 'vi' ? 'VI' : 'EN';

    return PopupMenuButton<String>(
      tooltip: t('language'),
      initialValue: current,
      color: const Color(0xFFF7EDF2),
      elevation: 8,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0xFF5A2A3A).withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.violet100.withValues(alpha: 0.75)),
      ),
      constraints: const BoxConstraints(minWidth: 170),
      onSelected: (value) async {
        await settings.setLanguage(value);
        onChanged?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'vi',
          child: _MenuRow(
            code: 'vi',
            label: t('vietnamese'),
            selected: current == 'vi',
          ),
        ),
        PopupMenuItem(
          value: 'en',
          child: _MenuRow(
            code: 'en',
            label: t('english'),
            selected: current == 'en',
          ),
        ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FlagBadge(code: current),
              const SizedBox(width: 8),
              Text(
                compactCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;

  const _MenuRow({
    required this.code,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? AppColors.ink900 : AppColors.ink700;
    return Row(
      children: [
        _FlagBadge(code: code),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.violet100.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 8),
          const Icon(Icons.check_rounded, size: 16, color: AppColors.momoPink),
        ],
      ],
    );
  }
}

class _FlagBadge extends StatelessWidget {
  final String code;

  const _FlagBadge({required this.code});

  String get _assetPath => code == 'vi'
      ? 'assets/images/flags/vn.png'
      : 'assets/images/flags/us.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 14,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Image.asset(
        _assetPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) =>
            code == 'vi' ? const _VietnamFlag() : const _UsFlag(),
      ),
    );
  }
}

class _VietnamFlag extends StatelessWidget {
  const _VietnamFlag();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFDA251D),
      child: Center(
        child: Icon(
          Icons.star_rounded,
          size: 10,
          color: Color(0xFFFFD34D),
        ),
      ),
    );
  }
}

class _UsFlag extends StatelessWidget {
  const _UsFlag();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: List.generate(13, (i) {
            return Expanded(
              child: ColoredBox(
                color: i.isEven ? const Color(0xFFB22234) : Colors.white,
              ),
            );
          }),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: 7.6,
            height: 7.8,
            color: const Color(0xFF3C3B6E),
            child: Stack(
              children: const [
                Positioned(top: 1.1, left: 1.0, child: _UsDot()),
                Positioned(top: 1.1, left: 3.1, child: _UsDot()),
                Positioned(top: 1.1, left: 5.2, child: _UsDot()),
                Positioned(top: 3.3, left: 2.0, child: _UsDot()),
                Positioned(top: 3.3, left: 4.1, child: _UsDot()),
                Positioned(top: 5.5, left: 1.0, child: _UsDot()),
                Positioned(top: 5.5, left: 3.1, child: _UsDot()),
                Positioned(top: 5.5, left: 5.2, child: _UsDot()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UsDot extends StatelessWidget {
  const _UsDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.9,
      height: 0.9,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
    );
  }
}
