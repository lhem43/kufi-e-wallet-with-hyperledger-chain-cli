// lib/models/notification_model.dart
// Purpose: Model for notification data

import 'package:intl/intl.dart';

class NotificationModel {
  final String id;
  final String title;
  final String type; // 'transfer' or 'receive'
  final DateTime date;
  final String? amount;
  final String? phoneNumber;
  final String? transactionId;
  final String? balanceAfter;
  final String? message;

  NotificationModel({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    this.amount,
    this.phoneNumber,
    this.transactionId,
    this.balanceAfter,
    this.message,
  });

  String get formattedTime {
    return DateFormat('h:mm a').format(date).toUpperCase();
  }

  /// Relative time label, e.g. "vừa xong", "3 phút trước", "2 giờ trước"
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.isNegative) return 'vừa xong';
    if (diff.inSeconds < 60) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays == 1) return 'Hôm qua';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Parse amount into a formatted VND string like "+50.000" or "-25.000"
  String? get formattedAmount {
    final raw = amount?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return raw;
    final abs = parsed.abs().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    final isReceive =
        type == 'receive' || title.toLowerCase().contains('nhận');
    return '${isReceive ? '+' : '-'}$absđ';
  }

  /// Color for the amount display
  bool get isIncoming =>
      type == 'receive' || title.toLowerCase().contains('nhận');

  /// Formatted balance-after string like "1.250.000đ"
  String? get formattedBalanceAfter {
    final raw = balanceAfter?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return raw;
    final abs = parsed.abs().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return '$absđ';
  }

  /// Formatted date as dd/MM/yyyy HH:mm
  String get formattedDate {
    final d = date.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  /// Whether this is a balance-change notification (transfer/receive)
  bool get isBalanceChange =>
      type == 'transfer' || type == 'receive';

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'date': date.toIso8601String(),
      'amount': amount,
      'phoneNumber': phoneNumber,
      'transactionId': transactionId,
      'balanceAfter': balanceAfter,
      'message': message,
    };
  }

  // Create from JSON
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final rawDate = '${json['date'] ?? ''}'.trim();
    final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    return NotificationModel(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      type: '${json['type'] ?? ''}',
      date: parsedDate,
      amount: json['amount'] == null ? null : '${json['amount']}',
      phoneNumber: json['phoneNumber'] == null ? null : '${json['phoneNumber']}',
      transactionId: json['transactionId'] == null
          ? null
          : '${json['transactionId']}',
      balanceAfter: json['balanceAfter'] == null
          ? null
          : '${json['balanceAfter']}',
      message: json['message'] == null ? null : '${json['message']}',
    );
  }
}
