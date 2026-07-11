import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/driver_repository.dart';

class DriverHistoryScreen extends ConsumerStatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  ConsumerState<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends ConsumerState<DriverHistoryScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  String _filter = 'ALL'; // ALL, COMPLETED, CANCELLED

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await ref.read(driverRepositoryProvider).getHistory();
      setState(() {
        _orders = List.from((history['orders'] as List?) ?? []);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_filter == 'ALL') return _orders;
    return _orders.where((o) => o['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Buyurtmalar tarixi',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Filter
          Container(
            color: surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _FilterChip(label: 'Barchasi', value: 'ALL', selected: _filter, onTap: (v) => setState(() => _filter = v), isDark: isDark),
                const SizedBox(width: 8),
                _FilterChip(label: 'Yakunlangan', value: 'COMPLETED', selected: _filter, onTap: (v) => setState(() => _filter = v), isDark: isDark),
                const SizedBox(width: 8),
                _FilterChip(label: 'Bekor', value: 'CANCELLED', selected: _filter, onTap: (v) => setState(() => _filter = v), isDark: isDark),
              ],
            ),
          ),
          Divider(height: 1, color: border),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: textSecondary),
                            const SizedBox(height: 12),
                            Text('Buyurtmalar yo\'q', style: TextStyle(color: textSecondary, fontSize: 15)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final order = _filtered[i] as Map<String, dynamic>;
                            final isDone = order['status'] == 'COMPLETED';
                            final isCancelled = order['status'] == 'CANCELLED';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(order['fromCity'] ?? '—',
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              child: Icon(Icons.arrow_forward, size: 14, color: textSecondary),
                                            ),
                                            Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.successColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(order['toCity'] ?? '—',
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDone
                                              ? AppTheme.successColor.withOpacity(0.1)
                                              : isCancelled
                                                  ? AppTheme.errorColor.withOpacity(0.1)
                                                  : AppTheme.primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isDone ? 'Yakunlandi' : isCancelled ? 'Bekor' : order['status'] ?? '',
                                          style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w700,
                                            color: isDone ? AppTheme.successColor : isCancelled ? AppTheme.errorColor : AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 13, color: textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        order['createdAt']?.toString().substring(0, 10) ?? '',
                                        style: TextStyle(fontSize: 12, color: textSecondary),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${order['price'] ?? 0} so\'m',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary),
                                      ),
                                    ],
                                  ),
                                  if (order['truckType'] != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.local_shipping_outlined, size: 13, color: textSecondary),
                                        const SizedBox(width: 4),
                                        Text(order['truckType'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                                        if (order['weight'] != null) ...[
                                          const SizedBox(width: 10),
                                          Icon(Icons.scale_outlined, size: 13, color: textSecondary),
                                          const SizedBox(width: 4),
                                          Text('${order['weight']} t', style: TextStyle(fontSize: 12, color: textSecondary)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  final bool isDark;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isSelected ? null : (isDark ? AppTheme.darkBackground : AppTheme.backgroundColor),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : (isDark ? AppTheme.darkBorder : AppTheme.borderColor),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}