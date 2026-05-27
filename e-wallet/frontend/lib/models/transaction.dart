class Transaction {
  final String name;
  final String bank;
  final double amount;
  final DateTime date;
  final String iconColor;

  Transaction({
    required this.name,
    required this.bank,
    required this.amount,
    required this.date,
    required this.iconColor,
  });

  bool get isPositive => amount >= 0;

  String get formattedAmount {
    final sign = isPositive ? '+' : '';
    return '$sign${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ';
  }

  String get formattedDate {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

