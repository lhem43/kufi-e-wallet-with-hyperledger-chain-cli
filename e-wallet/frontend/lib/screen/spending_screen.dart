import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_localizations.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class SpendingScreen extends StatefulWidget {
  const SpendingScreen({super.key});

  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends State<SpendingScreen> {
  static const _budgetKey = 'monthly_budget_vnd';

  final _userService = UserService();
  final _budgetController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _monthlyBudget = 0;
  List<Map<String, dynamic>> _transactions = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (!mounted) return;

    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final budget = prefs.getInt(_budgetKey) ?? 0;
      final tx = await _userService.getUserTransactions();

      if (!mounted) return;

      final budgetText = budget > 0 ? '$budget' : '';
      if (_budgetController.text != budgetText) {
        _budgetController.value = TextEditingValue(
          text: budgetText,
          selection: TextSelection.collapsed(offset: budgetText.length),
        );
      }

      setState(() {
        _monthlyBudget = budget;
        _transactions = tx;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = AppLocalizations.pick(
          vi: 'Không tải được dữ liệu chi tiêu. Vui lòng thử lại.',
          en: 'Unable to load spending data. Please try again.',
        );
      });
    }
  }

  Future<void> _saveBudget() async {
    final budget = int.tryParse(_budgetController.text.trim()) ?? 0;
    final normalized = max(0, budget);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_budgetKey, normalized);
    if (!mounted) return;

    setState(() => _monthlyBudget = normalized);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.pick(
            vi: 'Đã lưu ngân sách tháng.',
            en: 'Monthly budget saved.',
          ),
        ),
      ),
    );
  }

  DateTime _safeDate(Map<String, dynamic> tx) {
    final raw = '${tx['date'] ?? tx['createdAt'] ?? ''}'.trim();
    if (raw.isEmpty) return DateTime.now();
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  int _safeAmount(Map<String, dynamic> tx) {
    final value = tx['amount'];
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  bool _isSpendingTx(Map<String, dynamic> tx) {
    final direction = '${tx['direction'] ?? ''}'.toLowerCase();
    if (direction.contains('out')) return true;
    if (direction.contains('in')) return false;

    final type = '${tx['type'] ?? ''}'.toLowerCase();
    return type.contains('withdraw') ||
        type.contains('payment') ||
        type.contains('transfer') ||
        type.contains('send');
  }

  int _sumSpentForPeriod(bool Function(DateTime) predicate) {
    var total = 0;
    for (final tx in _transactions) {
      final amount = _safeAmount(tx);
      final date = _safeDate(tx);
      if (amount > 0 && _isSpendingTx(tx) && predicate(date)) {
        total += amount;
      }
    }
    return total;
  }

  Map<String, int> _buildCategoryMap() {
    final now = DateTime.now();
    final map = <String, int>{};
    for (final tx in _transactions) {
      final date = _safeDate(tx);
      if (date.year != now.year || date.month != now.month) continue;

      final amount = _safeAmount(tx);
      if (amount <= 0 || !_isSpendingTx(tx)) continue;

      final memo = '${tx['message'] ?? ''}'.toLowerCase();
      final recipient = '${tx['recipient'] ?? tx['recipientDisplayName'] ?? ''}'
          .toLowerCase();
      final content = '$memo $recipient';
      final category = _guessCategory(content);
      map[category] = (map[category] ?? 0) + amount;
    }
    return map;
  }

  List<Map<String, dynamic>> _recentMonthlySpending() {
    final now = DateTime.now();
    final list = _transactions.where((tx) {
      final date = _safeDate(tx);
      final amount = _safeAmount(tx);
      return amount > 0 &&
          _isSpendingTx(tx) &&
          date.year == now.year &&
          date.month == now.month;
    }).toList();

    list.sort((a, b) => _safeDate(b).compareTo(_safeDate(a)));
    return list.take(5).toList();
  }

  String _guessCategory(String content) {
    if (content.contains('coffee') ||
        content.contains('cafe') ||
        content.contains('ăn') ||
        content.contains('food')) {
      return AppLocalizations.pick(vi: 'Ăn uống', en: 'Food');
    }
    if (content.contains('taxi') ||
        content.contains('xe') ||
        content.contains('grab')) {
      return AppLocalizations.pick(vi: 'Di chuyển', en: 'Transport');
    }
    if (content.contains('shop') ||
        content.contains('mua') ||
        content.contains('mart')) {
      return AppLocalizations.pick(vi: 'Mua sắm', en: 'Shopping');
    }
    if (content.contains('bill') ||
        content.contains('điện') ||
        content.contains('nước') ||
        content.contains('internet')) {
      return AppLocalizations.pick(vi: 'Hóa đơn', en: 'Bills');
    }
    return AppLocalizations.pick(vi: 'Khác', en: 'Other');
  }

  String _formatMoney(num value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _displayName(Map<String, dynamic> tx) {
    final recipient = '${tx['recipientDisplayName'] ?? tx['recipient'] ?? ''}'
        .trim();
    final message = '${tx['message'] ?? ''}'.trim();
    if (recipient.isNotEmpty) return recipient;
    if (message.isNotEmpty) return message;
    return AppLocalizations.pick(vi: 'Giao dịch', en: 'Transaction');
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Text(
            tr(
              vi: 'Đang tải dữ liệu chi tiêu...',
              en: 'Loading spending data...',
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final todaySpent = _sumSpentForPeriod(
      (d) => d.year == now.year && d.month == now.month && d.day == now.day,
    );
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final weekSpent = _sumSpentForPeriod(
      (d) => !d.isBefore(weekStart) && d.isBefore(weekEnd),
    );
    final monthSpent = _sumSpentForPeriod(
      (d) => d.year == now.year && d.month == now.month,
    );

    final ratio = _monthlyBudget > 0 ? monthSpent / _monthlyBudget : 0.0;
    final normalized = ratio.clamp(0.0, 1.0);

    final categoryMap = _buildCategoryMap();
    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final recentTx = _recentMonthlySpending();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Chi tiêu', en: 'Spending')),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _loadData(showLoader: false),
            icon: Icon(
              _refreshing ? Icons.sync_disabled : Icons.refresh_rounded,
            ),
            tooltip: tr(vi: 'Làm mới', en: 'Refresh'),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              if (_refreshing) ...[
                Text(
                  tr(vi: 'Đang làm mới...', en: 'Refreshing...'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_error case final message?) ...[
                _ErrorBanner(message: message),
                const SizedBox(height: 12),
              ],
              _BudgetHeroCard(
                tr: tr,
                budgetController: _budgetController,
                onSave: _saveBudget,
                monthSpent: monthSpent,
                monthlyBudget: _monthlyBudget,
                ratio: ratio,
                normalizedRatio: normalized,
                formatMoney: _formatMoney,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final compact = maxWidth < 660;
                  final itemWidth = compact ? maxWidth : (maxWidth - 20) / 3;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _MetricCard(
                          label: tr(vi: 'Hôm nay', en: 'Today'),
                          value: '${_formatMoney(todaySpent)} đ',
                          icon: Icons.today_outlined,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _MetricCard(
                          label: tr(vi: 'Tuần này', en: 'This week'),
                          value: '${_formatMoney(weekSpent)} đ',
                          icon: Icons.date_range_outlined,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _MetricCard(
                          label: tr(vi: 'Tháng này', en: 'This month'),
                          value: '${_formatMoney(monthSpent)} đ',
                          icon: Icons.calendar_month_outlined,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          vi: 'Phân loại chi tiêu trong tháng',
                          en: 'Spending categories this month',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (sortedCategories.isEmpty)
                        Text(
                          tr(
                            vi: 'Chưa có giao dịch chi tiêu trong tháng này.',
                            en: 'No spending transactions this month yet.',
                          ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        )
                      else
                        ...sortedCategories.map((entry) {
                          final pct = monthSpent <= 0
                              ? 0.0
                              : (entry.value / monthSpent).clamp(0.0, 1.0);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_formatMoney(entry.value)} đ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    value: pct,
                                    backgroundColor: AppColors.violet100,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          AppColors.violet600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          vi: 'Giao dịch chi tiêu gần đây',
                          en: 'Recent spending transactions',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (recentTx.isEmpty)
                        Text(
                          tr(
                            vi: 'Bạn chưa có giao dịch chi tiêu gần đây.',
                            en: 'You do not have recent spending transactions.',
                          ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        )
                      else
                        ...recentTx.map((tx) {
                          final amount = _safeAmount(tx);
                          final time = _formatDateTime(_safeDate(tx));
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.violet100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.call_made_rounded,
                                    size: 18,
                                    color: AppColors.violet700,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _displayName(tx),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        time,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '-${_formatMoney(amount)} đ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetHeroCard extends StatelessWidget {
  final String Function({required String vi, required String en}) tr;
  final TextEditingController budgetController;
  final VoidCallback onSave;
  final int monthSpent;
  final int monthlyBudget;
  final double ratio;
  final double normalizedRatio;
  final String Function(num value) formatMoney;

  const _BudgetHeroCard({
    required this.tr,
    required this.budgetController,
    required this.onSave,
    required this.monthSpent,
    required this.monthlyBudget,
    required this.ratio,
    required this.normalizedRatio,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(vi: 'Ngân sách tháng', en: 'Monthly budget'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                vi: 'Thiết lập giới hạn để kiểm soát chi tiêu tốt hơn.',
                en: 'Set a target amount to keep spending under control.',
              ),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 460) {
                  return Column(
                    children: [
                      TextField(
                        controller: budgetController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr(
                            vi: 'Ngân sách (VND)',
                            en: 'Budget (VND)',
                          ),
                          hintText: tr(
                            vi: 'Ví dụ: 5.000.000',
                            en: 'Example: 5,000,000',
                          ),
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            tr(vi: 'Lưu ngân sách', en: 'Save budget'),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: budgetController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr(
                            vi: 'Ngân sách (VND)',
                            en: 'Budget (VND)',
                          ),
                          hintText: tr(
                            vi: 'Ví dụ: 5.000.000',
                            en: 'Example: 5,000,000',
                          ),
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 124,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(124, 50),
                        ),
                        onPressed: onSave,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(tr(vi: 'Lưu', en: 'Save')),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: normalizedRatio,
                backgroundColor: AppColors.violet100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  ratio >= 1 ? AppColors.danger : AppColors.success,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              monthlyBudget > 0
                  ? tr(
                      vi: 'Đã chi ${formatMoney(monthSpent)} đ / ${formatMoney(monthlyBudget)} đ',
                      en: 'Spent ${formatMoney(monthSpent)} VND / ${formatMoney(monthlyBudget)} VND',
                    )
                  : tr(
                      vi: 'Bạn chưa đặt ngân sách tháng.',
                      en: 'You have not set a monthly budget yet.',
                    ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEBED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.violet200),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.violet800,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.violet100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.violet700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
