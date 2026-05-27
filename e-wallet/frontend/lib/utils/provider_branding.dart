import 'package:flutter/material.dart';

class ProviderBranding {
  final String code;
  final String displayName;
  final String logoUrl;
  final IconData fallbackIcon;
  final Color accentColor;

  const ProviderBranding({
    required this.code,
    required this.displayName,
    required this.logoUrl,
    required this.fallbackIcon,
    required this.accentColor,
  });
}

ProviderBranding providerBrandingFromCode(String rawCode) {
  final code = rawCode.trim().toUpperCase();
  switch (code) {
    case 'MOMO':
      return const ProviderBranding(
        code: 'MOMO',
        displayName: 'MoMo',
        logoUrl: 'https://www.google.com/s2/favicons?domain=momo.vn&sz=128',
        fallbackIcon: Icons.account_balance_wallet_rounded,
        accentColor: Color(0xFFC2185B),
      );
    case 'ZALOPAY':
      return const ProviderBranding(
        code: 'ZALOPAY',
        displayName: 'ZaloPay',
        logoUrl: 'https://www.google.com/s2/favicons?domain=zalopay.vn&sz=128',
        fallbackIcon: Icons.payments_rounded,
        accentColor: Color(0xFF1565C0),
      );
    case 'VNPAY':
      return const ProviderBranding(
        code: 'VNPAY',
        displayName: 'VNPAY',
        logoUrl: 'https://www.google.com/s2/favicons?domain=vnpay.vn&sz=128',
        fallbackIcon: Icons.qr_code_2_rounded,
        accentColor: Color(0xFF2E7D32),
      );
    case 'TECHCOMBANK':
      return const ProviderBranding(
        code: 'TECHCOMBANK',
        displayName: 'Techcombank',
        logoUrl:
            'https://www.google.com/s2/favicons?domain=techcombank.com.vn&sz=128',
        fallbackIcon: Icons.account_balance_rounded,
        accentColor: Color(0xFFC62828),
      );
    case 'VIETCOMBANK':
      return const ProviderBranding(
        code: 'VIETCOMBANK',
        displayName: 'Vietcombank',
        logoUrl:
            'https://www.google.com/s2/favicons?domain=vietcombank.com.vn&sz=128',
        fallbackIcon: Icons.account_balance_rounded,
        accentColor: Color(0xFF1B5E20),
      );
    default:
      return const ProviderBranding(
        code: 'BANK',
        displayName: 'Nguồn tiền liên kết',
        logoUrl: 'https://www.google.com/s2/favicons?domain=bank.com&sz=128',
        fallbackIcon: Icons.account_balance_wallet_rounded,
        accentColor: Color(0xFF6A1B9A),
      );
  }
}

class ProviderLogoAvatar extends StatelessWidget {
  final ProviderBranding branding;
  final double size;

  const ProviderLogoAvatar({
    super.key,
    required this.branding,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          branding.logoUrl,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Container(
            color: branding.accentColor.withValues(alpha: 0.1),
            child: Icon(
              branding.fallbackIcon,
              color: branding.accentColor,
              size: size * 0.46,
            ),
          ),
        ),
      ),
    );
  }
}
