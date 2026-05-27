import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import '../services/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import 'receipt_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  static const String _todayKey = 'today';
  static const String _yesterdayKey = 'yesterday';
  static const String _weekKey = 'week';
  static const String _olderKey = 'older';

  final _notificationService = NotificationService();
  final _userService = UserService();
  List<NotificationModel> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    final notifications = await _notificationService.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _loading = false;
    });
    await _notificationService.markNotificationsSeen();
  }

  String _getTimeCategory(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return _todayKey;
    if (diff.inDays == 1) return _yesterdayKey;
    if (diff.inDays <= 7) return _weekKey;
    return _olderKey;
  }

  Map<String, List<NotificationModel>> _groupNotifications() {
    final grouped = <String, List<NotificationModel>>{
      _todayKey: [],
      _yesterdayKey: [],
      _weekKey: [],
      _olderKey: [],
    };
    for (final n in _notifications) {
      final bucket = _getTimeCategory(n.date);
      grouped.putIfAbsent(bucket, () => <NotificationModel>[]).add(n);
    }
    return grouped;
  }

  String _categoryLabel(String key) {
    switch (key) {
      case _todayKey:
        return AppLocalizations.pick(vi: 'Hôm nay', en: 'Today');
      case _yesterdayKey:
        return AppLocalizations.pick(vi: 'Hôm qua', en: 'Yesterday');
      case _weekKey:
        return AppLocalizations.pick(vi: '7 ngày gần đây', en: 'Last 7 days');
      default:
        return AppLocalizations.pick(vi: 'Cũ hơn', en: 'Older');
    }
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
            ? AppLocalizations.pick(
                vi: 'Nguồn tiền liên kết',
                en: 'Linked funding source',
              )
            : raw.trim();
    }
  }

  String _counterpartyForReceipt(Map<String, dynamic> tx) {
    final type = '${tx['type'] ?? ''}'.trim().toUpperCase();
    final provider = _providerDisplayName('${tx['externalPartner'] ?? ''}');
    if (type == 'DEPOSIT' || type == 'WITHDRAWAL') {
      return provider;
    }
    final recipientRaw =
        '${tx['recipientDisplayName'] ?? tx['recipientPhone'] ?? tx['recipient'] ?? AppLocalizations.pick(vi: 'Đối tác', en: 'Partner')}';
    return recipientRaw.trim().isEmpty
        ? AppLocalizations.pick(vi: 'Đối tác', en: 'Partner')
        : recipientRaw.trim();
  }

  Future<void> _handleNotificationTap(NotificationModel n) async {
    final txId = n.transactionId?.trim() ?? '';
    if (txId.isEmpty) return;

    // Try to find receipt data from local transactions
    final transactions = await _userService.syncLocalTransactions();
    Map<String, dynamic>? tx;
    for (final t in transactions) {
      if ('${t['transactionId'] ?? ''}' == txId) {
        tx = t;
        break;
      }
    }
    if (!mounted) return;

    if (tx != null) {
      final selectedTx = tx;
      final receipt = selectedTx['receipt'] is Map
          ? Map<String, dynamic>.from(selectedTx['receipt'] as Map)
          : <String, dynamic>{};
      final amount = _toInt(selectedTx['amount']);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            recipient: _counterpartyForReceipt(selectedTx),
            amount: amount,
            transactionDate: _safeDate(selectedTx),
            transactionId: txId,
            transactionStatus: '${selectedTx['status'] ?? ''}',
            settlementStatus: '${selectedTx['settlementStatus'] ?? ''}',
            chainStatus: '${selectedTx['chainStatus'] ?? ''}',
            chainTxId: '${receipt['tx_id'] ?? ''}',
            blockNumber: receipt['block_number'],
            blockHash:
                '${receipt['block_hash'] ?? receipt['receipt']?['block_hash'] ?? ''}',
            merkleRoot:
                '${receipt['receipt_hash'] ?? receipt['receipt']?['receipt_hash'] ?? ''}',
            commitmentHash:
                '${receipt['commitment_hash'] ?? receipt['receipt']?['commitment_hash'] ?? ''}',
            errorCode: '${selectedTx['errorCode'] ?? ''}',
            errorMessage: '${selectedTx['errorMessage'] ?? ''}',
            senderNote: '${selectedTx['message'] ?? ''}',
          ),
        ),
      );
    } else {
      // Navigate back to home with receipt tab focused
      if (Navigator.of(context).canPop()) {
        Navigator.of(
          context,
        ).pop({'action': 'open_receipts', 'transactionId': txId});
      }
    }
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  DateTime _safeDate(Map<String, dynamic> tx) {
    final raw = '${tx['date'] ?? tx['createdAt'] ?? ''}'.trim();
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final mutedColor = scheme.onSurface.withValues(alpha: 0.5);
    final grouped = _groupNotifications();
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;
    final pad = compact ? 14.0 : 18.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.pick(vi: 'Thông báo', en: 'Notifications'),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              onPressed: _loadNotifications,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: AppLocalizations.pick(vi: 'Làm mới', en: 'Refresh'),
            ),
        ],
      ),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 64,
                      color: mutedColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.pick(
                        vi: 'Chưa có thông báo nào',
                        en: 'No notifications yet',
                      ),
                      style: TextStyle(
                        color: subColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadNotifications,
                child: ListView(
                  padding: EdgeInsets.all(pad),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    for (final key in const [
                      _todayKey,
                      _yesterdayKey,
                      _weekKey,
                      _olderKey,
                    ])
                      if ((grouped[key] ?? []).isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(
                            top: key == _todayKey ? 0 : 16,
                            bottom: 8,
                          ),
                          child: Text(
                            _categoryLabel(key).toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: subColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        ...((grouped[key] ?? const <NotificationModel>[])).map(
                          (n) => _NotificationTile(
                            notification: n,
                            compact: compact,
                            onTap: () => _handleNotificationTap(n),
                          ),
                        ),
                      ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final bool compact;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.notification,
    required this.compact,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);
    final mutedColor = scheme.onSurface.withValues(alpha: 0.5);
    final tileBg = isDark ? const Color(0xFF2D2835) : Colors.white;
    final tileBorder = isDark ? const Color(0xFF5A4A61) : Colors.transparent;

    final isIncoming = notification.isIncoming;
    final amountText = notification.formattedAmount;
    final isBalanceChange = notification.isBalanceChange;

    final Color iconBg;
    final Color iconColor;
    final IconData icon;

    if (isIncoming) {
      iconBg = AppColors.success.withValues(alpha: 0.12);
      iconColor = AppColors.success;
      icon = Icons.arrow_downward_rounded;
    } else {
      iconBg = isDark ? const Color(0xFF46384D) : AppColors.violet100;
      iconColor = isDark ? const Color(0xFFF0B3C8) : AppColors.violet600;
      icon = Icons.arrow_upward_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tileBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tileBorder),
        ),
        elevation: 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 12,
            ),
            child: isBalanceChange
                ? _buildBalanceChangeTile(
                    context,
                    icon,
                    iconBg,
                    iconColor,
                    amountText,
                    isIncoming,
                    titleColor,
                    subColor,
                    mutedColor,
                  )
                : _buildGenericTile(
                    context,
                    icon,
                    iconBg,
                    iconColor,
                    amountText,
                    isIncoming,
                    titleColor,
                    subColor,
                    mutedColor,
                  ),
          ),
        ),
      ),
    );
  }

  /// Balance-change notification: shows amount, balance after, note, date
  Widget _buildBalanceChangeTile(
    BuildContext context,
    IconData icon,
    Color iconBg,
    Color iconColor,
    String? amountText,
    bool isIncoming,
    Color titleColor,
    Color subColor,
    Color mutedColor,
  ) {
    final balanceAfterText = notification.formattedBalanceAfter;
    final noteText = (notification.message ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: compact ? 20 : 22),
        ),
        SizedBox(width: compact ? 10 : 14),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                _localizedTitle(notification.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 14,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 6),
              // Amount
              if (amountText != null)
                _infoRow(
                  AppLocalizations.pick(vi: 'Số tiền', en: 'Amount'),
                  amountText,
                  valueColor: isIncoming ? AppColors.success : AppColors.danger,
                  bold: true,
                  labelColor: subColor,
                  defaultValueColor: titleColor,
                ),
              // Balance after
              if (balanceAfterText != null) ...[
                const SizedBox(height: 3),
                _infoRow(
                  AppLocalizations.pick(vi: 'Số dư', en: 'Balance'),
                  balanceAfterText,
                  labelColor: subColor,
                  defaultValueColor: titleColor,
                ),
              ],
              // Note
              if (noteText.isNotEmpty) ...[
                const SizedBox(height: 3),
                _infoRow(
                  AppLocalizations.pick(vi: 'Ghi chú', en: 'Note'),
                  noteText,
                  labelColor: subColor,
                  defaultValueColor: titleColor,
                ),
              ],
              // Date
              const SizedBox(height: 3),
              _infoRow(
                AppLocalizations.pick(vi: 'Ngày', en: 'Date'),
                notification.formattedDate,
                valueColor: subColor,
                labelColor: subColor,
                defaultValueColor: titleColor,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 20, color: mutedColor),
      ],
    );
  }

  /// Generic (non-balance) notification: title + time ago
  Widget _buildGenericTile(
    BuildContext context,
    IconData icon,
    Color iconBg,
    Color iconColor,
    String? amountText,
    bool isIncoming,
    Color titleColor,
    Color subColor,
    Color mutedColor,
  ) {
    return Row(
      children: [
        Container(
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: compact ? 20 : 22),
        ),
        SizedBox(width: compact ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizedTitle(notification.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 14,
                  color: titleColor,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _relativeTime(notification.date),
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: subColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (amountText != null)
              Text(
                amountText,
                style: TextStyle(
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w800,
                  color: isIncoming ? AppColors.success : AppColors.danger,
                ),
              ),
            const SizedBox(height: 2),
            Icon(Icons.chevron_right_rounded, size: 20, color: mutedColor),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
    Color labelColor = AppColors.ink500,
    Color defaultValueColor = AppColors.ink900,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 55,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: valueColor ?? defaultValueColor,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.isNegative || diff.inSeconds < 60) {
      return AppLocalizations.pick(vi: 'Vừa xong', en: 'Just now');
    }
    if (diff.inMinutes < 60) {
      return AppLocalizations.pick(
        vi: '${diff.inMinutes} phút trước',
        en: '${diff.inMinutes} min ago',
      );
    }
    if (diff.inHours < 24) {
      return AppLocalizations.pick(
        vi: '${diff.inHours} giờ trước',
        en: '${diff.inHours} h ago',
      );
    }
    if (diff.inDays == 1) {
      return AppLocalizations.pick(vi: 'Hôm qua', en: 'Yesterday');
    }
    if (diff.inDays < 7) {
      return AppLocalizations.pick(
        vi: '${diff.inDays} ngày trước',
        en: '${diff.inDays} d ago',
      );
    }
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _localizedTitle(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty || AppSettingsService().language != 'en') {
      return title;
    }

    if (title.startsWith('Hóa đơn điện tử đã sẵn sàng cho giao dịch ')) {
      final suffix = title.replaceFirst(
        'Hóa đơn điện tử đã sẵn sàng cho giao dịch ',
        '',
      );
      return 'E-receipt is ready for transaction $suffix';
    }
    if (title == 'Nhận tiền thành công') return 'Money received successfully';
    if (title == 'Giao dịch thất bại') return 'Transaction failed';
    if (title.startsWith('Đã tạo yêu cầu nạp tiền qua ')) {
      final provider = title.replaceFirst('Đã tạo yêu cầu nạp tiền qua ', '');
      return 'Top-up request created via $provider';
    }
    if (title.startsWith('Đã tạo yêu cầu rút tiền qua ')) {
      final provider = title.replaceFirst('Đã tạo yêu cầu rút tiền qua ', '');
      return 'Withdrawal request created via $provider';
    }
    if (title.startsWith('Nạp tiền thành công qua ')) {
      final provider = title.replaceFirst('Nạp tiền thành công qua ', '');
      return 'Top-up successful via $provider';
    }
    if (title.startsWith('Rút tiền thành công qua ')) {
      final provider = title.replaceFirst('Rút tiền thành công qua ', '');
      return 'Withdrawal successful via $provider';
    }
    return title;
  }
}
