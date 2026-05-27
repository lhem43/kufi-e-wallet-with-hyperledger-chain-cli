import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import 'receive_qr_screen.dart';
import 'scan_to_pay_screen.dart';

class QrCenterScreen extends StatefulWidget {
  const QrCenterScreen({super.key});

  @override
  State<QrCenterScreen> createState() => _QrCenterScreenState();
}

class _QrCenterScreenState extends State<QrCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final headerBtnBg = isDark ? const Color(0xFF2A3140) : AppColors.violet50;
    final headerBtnIcon = isDark
        ? const Color(0xFFB7C3D8)
        : AppColors.violet700;
    final tabBg = isDark ? const Color(0xFF242B36) : Colors.white;
    final tabShadow = isDark
        ? Colors.transparent
        : AppColors.ink900.withValues(alpha: 0.06);
    final tabIndicator = isDark
        ? scheme.primary.withValues(alpha: 0.85)
        : AppColors.momoPink;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 20,
                  compact ? 10 : 16,
                  compact ? 14 : 20,
                  0,
                ),
                child: Row(
                  children: [
                    Material(
                      color: headerBtnBg,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: headerBtnIcon,
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 12),
                    Container(
                      width: compact ? 38 : 44,
                      height: compact ? 38 : 44,
                      decoration: BoxDecoration(
                        color: tabIndicator,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(vi: 'QR thanh toán', en: 'QR payment'),
                            style: TextStyle(
                              fontSize: compact ? 22 : 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'BeVietnamPro',
                              color: titleColor,
                            ),
                          ),
                          Text(
                            tr(
                              vi: 'Nhận hoặc quét QR',
                              en: 'Receive or scan QR',
                            ),
                            style: TextStyle(
                              fontSize: compact ? 12 : 13,
                              color: subColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab bar ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 20,
                  14,
                  compact ? 14 : 20,
                  0,
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tabBg,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: tabShadow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: tabIndicator,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: subColor,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'BeVietnamPro',
                      fontSize: compact ? 13 : 14,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'BeVietnamPro',
                      fontSize: compact ? 13 : 14,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(tr(vi: 'Mã của tôi', en: 'My QR')),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(tr(vi: 'Quét mã', en: 'Scan QR')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── Tab views ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    ReceiveQrScreen(embedded: true),
                    ScanToPayScreen(embedded: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
