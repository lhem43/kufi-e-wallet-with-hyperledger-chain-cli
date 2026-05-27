import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/pin_session_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pin_code_boxes.dart';
import 'login_page.dart';
import 'notification_screen.dart';
import 'external_cash_flow_screen.dart';
import 'profile_screen.dart';
import 'qr_center_screen.dart';
import 'receipt_history_screen.dart';
import 'receipt_screen.dart';
import 'send_money_screen.dart';
import 'spending_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;
  final String? initialReceiptTransactionId;
  final VoidCallback? onLogout;

  const HomeScreen({
    super.key,
    this.initialTab = 0,
    this.initialReceiptTransactionId,
    this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _userService = UserService();
  final _notificationService = NotificationService();

  bool _loading = true;
  bool _balanceVisible = false;
  bool _hasPinProtection = false;
  int _currentTab = 0;
  int _unreadNotifications = 0;
  String _userName = 'Người dùng Kufi';
  String _userPhone = '';
  double _balance = 0;
  List<Map<String, dynamic>> _transactions = [];
  String? _highlightReceiptTxId;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab.clamp(0, 2);
    _highlightReceiptTxId = widget.initialReceiptTransactionId;
    _reload();
  }

  Future<void> _reload() async {
    final t = AppLocalizations.text;
    setState(() {
      _loading = true;
    });

    final user = await _authService.getCurrentUser();
    final transactions = await _userService.syncLocalTransactions();
    final balance = await _userService.getCurrentUserBalance();
    final hasPin = user?['hasPin'] == true;
    final unread = await _notificationService.getUnreadCount();

    if (!mounted) {
      return;
    }

    final displayName = '${user?['displayName'] ?? ''}'.trim();
    final email = '${user?['email'] ?? ''}'.trim();
    final resolvedName = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email : t('user_kufi'));

    setState(() {
      _userName = resolvedName;
      _userPhone = '${user?['phone'] ?? ''}';
      _transactions = transactions;
      _balance = balance;
      _hasPinProtection = hasPin;
      _unreadNotifications = unread;
      _loading = false;
    });
  }

  String _formatMoney(num value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _relativeTime(DateTime date) {
    final t = AppLocalizations.text;
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) {
      return t(
        'seconds_ago',
        params: {'value': '${diff.inSeconds.clamp(1, 59)}'},
      );
    }
    if (diff.inMinutes < 60) {
      return t('minutes_ago', params: {'value': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return t('hours_ago', params: {'value': '${diff.inHours}'});
    }
    if (diff.inDays <= 3) {
      return t('days_ago', params: {'value': '${diff.inDays}'});
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _openNotifications() async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    await _notificationService.markNotificationsSeen();
    if (!mounted) {
      return;
    }

    if (result is Map &&
        result['action'] == 'open_receipts' &&
        '${result['transactionId'] ?? ''}'.trim().isNotEmpty) {
      setState(() {
        _currentTab = 1;
        _highlightReceiptTxId = '${result['transactionId'] ?? ''}';
      });
    }
    await _reload();
  }

  Future<void> _toggleBalanceVisibility() async {
    if (_balanceVisible) {
      setState(() {
        _balanceVisible = false;
      });
      return;
    }
    if (!_hasPinProtection) {
      setState(() {
        _balanceVisible = true;
      });
      return;
    }

    // If already unlocked this session, skip PIN prompt
    if (PinSessionService().isBalanceUnlocked) {
      setState(() {
        _balanceVisible = true;
      });
      return;
    }

    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinUnlockDialog(authService: _authService),
    );
    if (unlocked == true && mounted) {
      PinSessionService().markBalanceUnlocked();
      setState(() {
        _balanceVisible = true;
      });
    }
  }

  Future<void> _logout() async {
    PinSessionService().clear();
    await _authService.logout();
    if (!mounted) {
      return;
    }
    if (widget.onLogout != null) {
      widget.onLogout!();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  /// Sync balance visibility with PinSessionService after returning from
  /// screens that may have unlocked the balance (e.g. SendMoneyScreen).
  Future<void> _syncBalanceVisibility() async {
    if (PinSessionService().isBalanceUnlocked && !_balanceVisible) {
      setState(() => _balanceVisible = true);
    }
    await _reload();
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  DateTime _safeDate(Map<String, dynamic> tx) {
    final raw = '${tx['date'] ?? tx['createdAt'] ?? ''}';
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  String _providerDisplayName(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'MOMO':
        return 'MoMo';
      case 'ZALOPAY':
        return 'ZaloPay';
      case 'VNPAY':
        return 'VNPAY';
      case 'TECHCOMBANK':
        return 'Techcombank';
      case 'VIETCOMBANK':
        return 'Vietcombank';
      default:
        return raw.trim().isEmpty
            ? AppLocalizations.text('linked_funding_source')
            : raw.trim();
    }
  }

  String _counterpartyForReceipt(Map<String, dynamic> tx) {
    final type = '${tx['type'] ?? ''}'.trim().toUpperCase();
    final providerCode = '${tx['externalPartner'] ?? ''}';
    final providerName = _providerDisplayName(providerCode);
    if (type == 'DEPOSIT') {
      return providerName;
    }
    if (type == 'WITHDRAWAL') {
      return providerName;
    }
    final recipientRaw =
        '${tx['recipientDisplayName'] ?? tx['recipientPhone'] ?? tx['recipient'] ?? AppLocalizations.text('transaction_partner')}';
    return recipientRaw.trim().isEmpty
        ? AppLocalizations.text('transaction_partner')
        : recipientRaw.trim();
  }

  void _openReceiptDetail(Map<String, dynamic> tx) {
    final receipt = tx['receipt'] is Map
        ? Map<String, dynamic>.from(tx['receipt'] as Map)
        : <String, dynamic>{};
    final amount = _toInt(tx['amount']);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          recipient: _counterpartyForReceipt(tx),
          amount: amount,
          transactionDate: _safeDate(tx),
          transactionId: '${tx['transactionId'] ?? ''}',
          transactionStatus: '${tx['status'] ?? ''}',
          settlementStatus: '${tx['settlementStatus'] ?? ''}',
          chainStatus: '${tx['chainStatus'] ?? ''}',
          chainTxId: '${receipt['tx_id'] ?? ''}',
          blockNumber: receipt['block_number'],
          blockHash:
              '${receipt['block_hash'] ?? receipt['receipt']?['block_hash'] ?? ''}',
          merkleRoot:
              '${receipt['receipt_hash'] ?? receipt['receipt']?['receipt_hash'] ?? ''}',
          commitmentHash:
              '${receipt['commitment_hash'] ?? receipt['receipt']?['commitment_hash'] ?? ''}',
          errorCode: '${tx['errorCode'] ?? ''}',
          errorMessage: '${tx['errorMessage'] ?? ''}',
          senderNote: '${tx['message'] ?? ''}',
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final t = AppLocalizations.text;
    final scheme = Theme.of(context).colorScheme;
    final mutedText = scheme.onSurface.withValues(alpha: 0.72);
    final subtleText = scheme.onSurface.withValues(alpha: 0.58);

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
        children: [
          _HeaderRow(
            userName: _userName,
            unreadNotifications: _unreadNotifications,
            onNotificationTap: _openNotifications,
            onLogoutTap: _logout,
          ),
          const SizedBox(height: 12),
          _BalanceHero(
            revealed: _balanceVisible,
            onToggleReveal: _toggleBalanceVisibility,
            balanceText: '${_formatMoney(_balance)}đ',
            subtitle: _userPhone.isEmpty
                ? t('wallet_subtitle_default')
                : '${t('wallet_phone_prefix')}: $_userPhone',
            onTransfer: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
                  )
                  .then((_) => _syncBalanceVisibility());
            },
            onQrPay: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const QrCenterScreen()),
                  )
                  .then((_) => _reload());
            },
          ),
          const SizedBox(height: 14),
          _QuickActions(
            onTransfer: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
                  )
                  .then((_) => _syncBalanceVisibility());
            },
            onTopup: () => _openExternalCashFlow(isTopup: true),
            onWithdraw: () => _openExternalCashFlow(isTopup: false),
            onQrCenter: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const QrCenterScreen()),
                  )
                  .then((_) => _reload());
            },
            onSpending: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SpendingScreen()),
                  )
                  .then((_) => _reload());
            },
          ),
          const SizedBox(height: 14),
          if (_balanceVisible)
            _RecentTransactions(
              transactions: _transactions.take(8).toList(),
              formatMoney: _formatMoney,
              relativeTime: _relativeTime,
              onTap: _openReceiptDetail,
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 14,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 40,
                      color: subtleText,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t('hidden_recent_transactions_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('hidden_recent_transactions_hint'),
                      style: TextStyle(color: subtleText, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = <Widget>[
      _buildHomeTab(),
      ReceiptHistoryScreen(
        transactions: _transactions,
        formatMoney: _formatMoney,
        onRefresh: _reload,
        highlightTransactionId: _highlightReceiptTxId,
      ),
      ProfileScreen(onProfileUpdated: _reload),
    ];

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: IndexedStack(index: _currentTab, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() {
            _currentTab = index;
            if (index != 1) {
              _highlightReceiptTxId = null;
            }
          });
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: AppLocalizations.text('nav_home'),
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: AppLocalizations.text('nav_receipts'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: AppLocalizations.text('nav_profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalCashFlow({required bool isTopup}) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExternalCashFlowScreen(isTopup: isTopup),
      ),
    );
    if (completed == true) {
      await _reload();
    }
  }
}

class _HeaderRow extends StatelessWidget {
  final String userName;
  final int unreadNotifications;
  final VoidCallback onNotificationTap;
  final VoidCallback onLogoutTap;

  const _HeaderRow({
    required this.userName,
    required this.unreadNotifications,
    required this.onNotificationTap,
    required this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final greetingColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.74);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('hello'), style: TextStyle(color: greetingColor)),
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        _HeaderAction(
          icon: Icons.notifications_active_outlined,
          badgeCount: unreadNotifications,
          onTap: onNotificationTap,
          tooltip: t('notification_tooltip'),
        ),
        const SizedBox(width: 8),
        _HeaderAction(
          icon: Icons.logout_rounded,
          onTap: onLogoutTap,
          tooltip: t('logout_tooltip'),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderAction({
    required this.icon,
    this.badgeCount = 0,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final backgroundColor = isDark
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.84)
        : Colors.white.withValues(alpha: 0.9);
    final hoverColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : AppColors.violet50.withValues(alpha: 0.34);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          hoverColor: hoverColor,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, color: accent, size: 21)),
                if (badgeCount > 0)
                  Positioned(
                    top: 4,
                    right: 3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

class _BalanceHero extends StatelessWidget {
  final bool revealed;
  final VoidCallback onToggleReveal;
  final String balanceText;
  final String subtitle;
  final VoidCallback onTransfer;
  final VoidCallback onQrPay;

  const _BalanceHero({
    required this.revealed,
    required this.onToggleReveal,
    required this.balanceText,
    required this.subtitle,
    required this.onTransfer,
    required this.onQrPay,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionBg = isDark
        ? const Color(0xFF732842).withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.18);
    final actionStroke = isDark
        ? const Color(0xFFCB6F8C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.35);
    final subtitleColor = isDark
        ? const Color(0xFFE9D2DC)
        : const Color(0xFFF7D8DE);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: isDark ? AppColors.darkCardGradient : AppColors.cardGradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t('secured_by_kufi'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onToggleReveal,
                tooltip: revealed ? t('hide_balance') : t('show_balance'),
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: isDark ? 0.12 : 0.15),
                ),
                icon: Icon(
                  revealed ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            t('available_balance'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w700,
              fontFamily: 'BeVietnamPro',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            revealed ? balanceText : '● ● ● ● ● ● ● ●',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFamily: 'BeVietnamPro',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: subtitleColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTransfer,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: actionStroke,
                    ),
                    foregroundColor: Colors.white,
                    backgroundColor: actionBg,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(t('transfer')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onQrPay,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: actionStroke,
                    ),
                    foregroundColor: Colors.white,
                    backgroundColor: actionBg,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(t('qr_payment')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onTransfer;
  final VoidCallback onTopup;
  final VoidCallback onWithdraw;
  final VoidCallback onQrCenter;
  final VoidCallback onSpending;

  const _QuickActions({
    required this.onTransfer,
    required this.onTopup,
    required this.onWithdraw,
    required this.onQrCenter,
    required this.onSpending,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final titleColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.8);

    final actions = [
      (icon: Icons.send_rounded, label: t('transfer'), onTap: onTransfer),
      (icon: Icons.arrow_downward_rounded, label: t('topup'), onTap: onTopup),
      (icon: Icons.arrow_upward_rounded, label: t('withdraw'), onTap: onWithdraw),
      (
        icon: Icons.qr_code_scanner_rounded,
        label: t('qr_payment'),
        onTap: onQrCenter,
      ),
      (icon: Icons.insights_outlined, label: t('spending'), onTap: onSpending),
    ];
    final width = MediaQuery.of(context).size.width;
    final columns = width < 430 ? 3 : 5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('transaction_utilities'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final itemWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: 10,
                  children: actions
                      .map(
                        (a) => SizedBox(
                          width: itemWidth,
                          child: _ActionChip(
                            icon: a.icon,
                            label: a.label,
                            onTap: a.onTap,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionColor = isDark ? const Color(0xFFA22F58) : AppColors.momoPink;
    final iconColor = Colors.white;
    final chipBorder = isDark ? const Color(0xFFD37C9B) : Colors.transparent;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: actionColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: chipBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x352E1221),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final String Function(num) formatMoney;
  final String Function(DateTime) relativeTime;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _RecentTransactions({
    required this.transactions,
    required this.formatMoney,
    required this.relativeTime,
    required this.onTap,
  });

  DateTime _safeDate(Map<String, dynamic> tx) {
    final raw = '${tx['date'] ?? tx['createdAt'] ?? ''}';
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  int _safeAmount(Map<String, dynamic> tx) {
    final value = tx['amount'];
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  bool _isVisible(Map<String, dynamic> tx) {
    final status = '${tx['status'] ?? ''}'.toUpperCase();
    if (status.contains('FAIL')) {
      return false;
    }
    return true;
  }

  String _providerDisplayName(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'MOMO':
        return 'MoMo';
      case 'ZALOPAY':
        return 'ZaloPay';
      case 'VNPAY':
        return 'VNPAY';
      case 'TECHCOMBANK':
        return 'Techcombank';
      case 'VIETCOMBANK':
        return 'Vietcombank';
      default:
        return raw.trim().isEmpty
            ? AppLocalizations.text('linked_funding_source')
            : raw.trim();
    }
  }

  String _counterpartyLabel(Map<String, dynamic> tx, bool isIncoming) {
    final type = '${tx['type'] ?? ''}'.trim().toUpperCase();
    final provider = _providerDisplayName('${tx['externalPartner'] ?? ''}');
    if (type == 'DEPOSIT') {
      return provider;
    }
    if (type == 'WITHDRAWAL') {
      return provider;
    }
    final counterpartRaw = isIncoming
        ? '${tx['senderDisplayName'] ?? tx['fromUserId'] ?? AppLocalizations.text('sender')}'
        : '${tx['recipientDisplayName'] ?? tx['recipientPhone'] ?? tx['toUserId'] ?? AppLocalizations.text('recipient')}';
    return counterpartRaw.trim().isEmpty
        ? (isIncoming
              ? AppLocalizations.text('sender')
              : AppLocalizations.text('recipient'))
        : counterpartRaw.trim();
  }

  String _senderNote(Map<String, dynamic> tx) {
    final memo = '${tx['message'] ?? ''}'.trim();
    if (memo.isNotEmpty) {
      return memo;
    }
    final type = '${tx['type'] ?? ''}'.trim().toUpperCase();
    final provider = _providerDisplayName('${tx['externalPartner'] ?? ''}');
    if (type == 'DEPOSIT') {
      return AppLocalizations.text(
        'deposit_via',
        params: {'provider': provider},
      );
    }
    if (type == 'WITHDRAWAL') {
      return AppLocalizations.text(
        'withdraw_via',
        params: {'provider': provider},
      );
    }
    return '';
  }

  String _displayStatus(Map<String, dynamic> tx) {
    final status = '${tx['status'] ?? ''}'.trim().toUpperCase();
    if (status == 'COMPLETED') {
      return AppLocalizations.text('status_success');
    }
    if (status.contains('FAIL') || status.contains('ERROR')) {
      return AppLocalizations.text('status_failed');
    }
    return AppLocalizations.text('status_processing');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = isDark ? const Color(0xFF2D2834) : Colors.white;
    final tileBorder = isDark ? const Color(0xFF5A4A61) : Colors.transparent;
    final contentColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final hintColor = scheme.onSurface.withValues(alpha: 0.62);

    final visibleTransactions = transactions.where(_isVisible).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t('recent_transactions'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: contentColor,
                  ),
                ),
                Text(
                  t('hide_transaction_info'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.violet600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (visibleTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t('no_transactions')),
              )
            else
              ...visibleTransactions.map((tx) {
                final amount = _safeAmount(tx);
                final date = _safeDate(tx);
                final status = _displayStatus(tx);
                final direction = '${tx['direction'] ?? 'OUT'}'.toUpperCase();
                final isIncoming = direction == 'IN' || direction == 'INCOMING';
                final counterpart = _counterpartyLabel(tx, isIncoming);
                final senderNote = _senderNote(tx);

                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: tileColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: tileBorder),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onTap(tx),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isIncoming
                                    ? const Color(0xFFE7F7F0)
                                    : AppColors.violet100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isIncoming
                                    ? Icons.call_received_rounded
                                    : Icons.call_made_rounded,
                                color: isIncoming
                                    ? AppColors.success
                                    : AppColors.violet700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    counterpart,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: contentColor,
                                    ),
                                  ),
                                  if (senderNote.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      senderNote,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  Text(
                                    '$status · ${relativeTime(date)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${isIncoming ? '+' : '-'}${formatMoney(amount)}đ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isIncoming
                                    ? AppColors.success
                                    : contentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PinUnlockDialog extends StatefulWidget {
  final AuthService authService;

  const _PinUnlockDialog({required this.authService});

  @override
  State<_PinUnlockDialog> createState() => _PinUnlockDialogState();
}

class _PinUnlockDialogState extends State<_PinUnlockDialog> {
  final _pinController = TextEditingController();
  bool _verifying = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final t = AppLocalizations.text;
    if (_verifying) {
      return;
    }
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() {
        _errorText = t('pin_exact_6');
      });
      return;
    }
    setState(() {
      _verifying = true;
      _errorText = null;
    });
    final valid = await widget.authService.verifyServerPin(pin);
    if (!mounted) {
      return;
    }
    if (!valid) {
      setState(() {
        _verifying = false;
        _errorText = t('pin_incorrect');
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.text;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('pin_verify_title'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'BeVietnamPro',
                ),
              ),
              const SizedBox(height: 6),
              Text(t('pin_unlock_balance_prompt')),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _pinController,
                enabled: !_verifying,
                autofocus: true,
                label: t('secure_pin_label'),
                helperText: t('enter_six_digits'),
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() {
                      _errorText = null;
                    });
                  }
                },
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _verifying
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _verifying ? null : _verify,
                      child: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(t('unlock_balance')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
