import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../theme/app_theme.dart';
import 'receipt_screen.dart';

class ReceiptHistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final String Function(num value) formatMoney;
  final Future<void> Function() onRefresh;
  final String? highlightTransactionId;

  const ReceiptHistoryScreen({
    super.key,
    required this.transactions,
    required this.formatMoney,
    required this.onRefresh,
    this.highlightTransactionId,
  });

  String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) {
      return AppLocalizations.text(
        'seconds_ago',
        params: {'value': '${diff.inSeconds.clamp(1, 59)}'},
      );
    }
    if (diff.inMinutes < 60) {
      return AppLocalizations.text(
        'minutes_ago',
        params: {'value': '${diff.inMinutes}'},
      );
    }
    if (diff.inHours < 24) {
      return AppLocalizations.text(
        'hours_ago',
        params: {'value': '${diff.inHours}'},
      );
    }
    if (diff.inDays <= 3) {
      return AppLocalizations.text(
        'days_ago',
        params: {'value': '${diff.inDays}'},
      );
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _mapUiState(Map<String, dynamic> tx) {
    final status = '${tx['status'] ?? ''}'.toUpperCase();
    final statusFailed = status.contains('FAIL') || status.contains('ERROR');
    if (statusFailed) {
      return 'hidden';
    }
    if (status == 'COMPLETED') {
      return 'success';
    }
    return 'processing';
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

  DateTime _safeDate(String raw) {
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

  String _directionLabel(Map<String, dynamic> tx, bool isIncoming) {
    final type = '${tx['type'] ?? ''}'.trim().toUpperCase();
    if (type == 'DEPOSIT') {
      return AppLocalizations.text('topup');
    }
    if (type == 'WITHDRAWAL') {
      return AppLocalizations.text('withdraw');
    }
    return isIncoming
        ? AppLocalizations.pick(vi: 'Nhận tiền', en: 'Receive money')
        : AppLocalizations.pick(vi: 'Chuyển tiền', en: 'Transfer money');
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subtitleColor = scheme.onSurface.withValues(alpha: 0.74);
    final itemBg = isDark ? const Color(0xFF2D2835) : Colors.white;
    final highlightedBg = isDark
        ? const Color(0xFF373041)
        : AppColors.vanilla100;
    final itemBorder = isDark ? const Color(0xFF5A4A61) : Colors.transparent;
    final processingTextColor = isDark
        ? const Color(0xFFE3C7D4)
        : AppColors.ink700;
    final processingBg = isDark ? const Color(0xFF4A3A4A) : AppColors.violet100;
    final successBg = isDark
        ? const Color(0xFF1F3B33).withValues(alpha: 0.6)
        : AppColors.success.withValues(alpha: 0.12);
    final successColor = isDark ? const Color(0xFF4AD09B) : AppColors.success;
    final outgoingAmountColor = isDark ? const Color(0xFFE7ECF8) : titleColor;

    final visible =
        transactions.where((tx) => _mapUiState(tx) != 'hidden').toList()
          ..sort((a, b) {
            final aDate = _safeDate('${a['date'] ?? a['createdAt'] ?? ''}');
            final bDate = _safeDate('${b['date'] ?? b['createdAt'] ?? ''}');
            return bDate.compareTo(aDate);
          });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isDark ? const Color(0xFF87405D) : AppColors.violet600,
                      isDark ? const Color(0xFFB84D71) : AppColors.momoPink,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(vi: 'Hóa đơn điện tử', en: 'E-receipts'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              vi: 'Các giao dịch thành công và đang xử lý. Giao dịch thất bại sẽ không hiển thị.',
              en: 'Only successful or processing transactions are shown. Failed ones are hidden.',
            ),
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  tr(
                    vi: 'Chưa có hóa đơn phù hợp.',
                    en: 'No matching receipts yet.',
                  ),
                ),
              ),
            )
          else
            ...visible.map((tx) {
              final txId = '${tx['transactionId'] ?? ''}'.trim();
              final uiState = _mapUiState(tx);
              final isHighlighted =
                  highlightTransactionId != null &&
                  highlightTransactionId == txId;
              final amount = _toInt(tx['amount']);
              final date = _safeDate(
                '${tx['date'] ?? tx['createdAt'] ?? DateTime.now().toIso8601String()}',
              );
              final direction = '${tx['direction'] ?? 'OUT'}'.toUpperCase();
              final isIncoming = direction == 'IN' || direction == 'INCOMING';

              final counterpart = _counterpartyLabel(tx, isIncoming);

              final badge = switch (uiState) {
                'success' => (
                  label: AppLocalizations.text('status_success'),
                  color: AppColors.success,
                  bg: AppColors.success.withValues(alpha: 0.12),
                  icon: Icons.verified_rounded,
                ),
                _ => (
                  label: AppLocalizations.text('status_processing'),
                  color: processingTextColor,
                  bg: processingBg,
                  icon: Icons.pending_rounded,
                ),
              };

              final directionLabel = _directionLabel(tx, isIncoming);
              final directionIcon = isIncoming
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded;
              final directionIconBg = isIncoming
                  ? AppColors.success.withValues(alpha: 0.12)
                  : (isDark ? const Color(0xFF46384D) : AppColors.violet100);
              final directionIconColor = isIncoming
                  ? AppColors.success
                  : (isDark ? const Color(0xFFF0B3C8) : AppColors.violet600);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: isHighlighted ? highlightedBg : itemBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: itemBorder),
                  ),
                  elevation: 0.5,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openReceiptDetail(context, tx),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: directionIconBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              directionIcon,
                              color: directionIconColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counterpart,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$directionLabel · ${_relativeTime(date)}',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isIncoming ? '+' : '-'}${formatMoney(amount)}đ',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isIncoming
                                      ? successColor
                                      : outgoingAmountColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: uiState == 'success'
                                      ? successBg
                                      : badge.bg,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      badge.icon,
                                      size: 11,
                                      color: uiState == 'success'
                                          ? successColor
                                          : badge.color,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      badge.label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                        color: uiState == 'success'
                                            ? successColor
                                            : badge.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    );
  }

  void _openReceiptDetail(BuildContext context, Map<String, dynamic> tx) {
    final receipt = tx['receipt'] is Map
        ? Map<String, dynamic>.from(tx['receipt'] as Map)
        : <String, dynamic>{};
    final amount = _toInt(tx['amount']);
    final recipientRaw =
        '${tx['recipientDisplayName'] ?? tx['recipientPhone'] ?? tx['recipient'] ?? tx['toUserId'] ?? ''}';
    final recipient = recipientRaw.trim().isEmpty
        ? AppLocalizations.text('transaction_partner')
        : recipientRaw.trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          recipient: recipient,
          amount: amount,
          transactionDate: _safeDate(
            '${tx['date'] ?? tx['createdAt'] ?? DateTime.now().toIso8601String()}',
          ),
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
        ),
      ),
    );
  }
}
