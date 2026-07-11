import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';

enum _HistoryFilter { all, delivered, cancelled }

class DriverOrderHistoryFullScreen extends ConsumerStatefulWidget {
  const DriverOrderHistoryFullScreen({super.key});

  @override
  ConsumerState<DriverOrderHistoryFullScreen> createState() => _DriverOrderHistoryFullScreenState();
}

class _DriverOrderHistoryFullScreenState extends ConsumerState<DriverOrderHistoryFullScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  _HistoryFilter _filter = _HistoryFilter.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final history = await ref.read(driverRepositoryProvider).getHistory();
      final list = ((history['orders'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() { _orders = list; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  bool _matchesFilter(String status) {
    switch (_filter) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.delivered:
        return status == 'DELIVERED' || status == 'COMPLETED';
      case _HistoryFilter.cancelled:
        return status == 'CANCELLED';
    }
  }

  bool _matchesSearch(Map<String, dynamic> order) {
    if (_searchQuery.isEmpty) return true;
    final from = (order['fromCity'] as String? ?? '').toLowerCase();
    final to = (order['toCity'] as String? ?? '').toLowerCase();
    return from.contains(_searchQuery) || to.contains(_searchQuery);
  }

  List<Map<String, dynamic>> get _filtered {
    return _orders.where((o) {
      final status = o['status'] as String? ?? '';
      return _matchesFilter(status) && _matchesSearch(o);
    }).toList();
  }

  // Sana bo'yicha guruhlash — client_orders_screen.dart bilan bir xil naqsh.
  // Bu yerda (7 kunlik cheklovsiz) TO'LIQ tarix guruhlanadi.
  Map<String, List<Map<String, dynamic>>> _groupedByDate(String locale) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final order in _filtered) {
      final createdAt = order['createdAt'] as String?;
      if (createdAt == null) continue;
      final date = DateTime.tryParse(createdAt);
      if (date == null) continue;
      final dateOnly = DateTime(date.year, date.month, date.day);

      String label;
      if (dateOnly == today) {
        label = AppStrings.get('today', locale);
      } else if (dateOnly == yesterday) {
        label = AppStrings.get('yesterday', locale);
      } else {
        const months = ['yan', 'fev', 'mar', 'apr', 'may', 'iyun', 'iyul', 'avg', 'sen', 'okt', 'noy', 'dek'];
        label = '${date.day} ${months[date.month - 1]}';
      }

      grouped.putIfAbsent(label, () => []).add(order);
    }
    return grouped;
  }

  // client_orders_screen.dart'dagi rang/matn mantig'iga mos
  Color _statusColor(String status) {
    switch (status) {
      case 'SEARCHING':
      case 'OFFERED':
        return AppTheme.warningColor;
      case 'ACCEPTED':
      case 'DRIVER_ARRIVING':
      case 'LOADING':
      case 'IN_TRANSIT':
        return AppTheme.primaryColor;
      case 'DELIVERED':
      case 'COMPLETED':
        return AppTheme.successColor;
      case 'CANCELLED':
        return AppTheme.errorColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _statusText(String status, String locale) {
    switch (status) {
      case 'SEARCHING': return AppStrings.get('status_searching', locale);
      case 'OFFERED': return AppStrings.get('status_offered', locale);
      case 'ACCEPTED': return AppStrings.get('status_accepted', locale);
      case 'DRIVER_ARRIVING': return AppStrings.get('status_driver_arriving', locale);
      case 'LOADING': return AppStrings.get('status_loading', locale);
      case 'IN_TRANSIT': return AppStrings.get('status_in_transit', locale);
      case 'DELIVERED': return AppStrings.get('status_delivered', locale);
      case 'COMPLETED': return AppStrings.get('status_completed', locale);
      case 'CANCELLED': return AppStrings.get('status_cancelled', locale);
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final grouped = _groupedByDate(locale);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.get('order_history_full_title', locale),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textPrimary, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Qidiruv
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: AppStrings.get('search_city_hint', locale),
                  hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, size: 18, color: textSecondary),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Filter tugmalari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _HistoryFilterBtn(
                    label: AppStrings.get('filter_all', locale),
                    selected: _filter == _HistoryFilter.all,
                    isDark: isDark,
                    onTap: () => setState(() => _filter = _HistoryFilter.all),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HistoryFilterBtn(
                    label: AppStrings.get('filter_delivered', locale),
                    selected: _filter == _HistoryFilter.delivered,
                    isDark: isDark,
                    onTap: () => setState(() => _filter = _HistoryFilter.delivered),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HistoryFilterBtn(
                    label: AppStrings.get('filter_cancelled', locale),
                    selected: _filter == _HistoryFilter.cancelled,
                    isDark: isDark,
                    onTap: () => setState(() => _filter = _HistoryFilter.cancelled),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Ro'yxat — barcha buyurtmalar, sana bo'yicha guruhlangan
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : grouped.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: textSecondary),
                            const SizedBox(height: 16),
                            Text(AppStrings.get('no_orders_found', locale), style: TextStyle(fontSize: 16, color: textSecondary)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: grouped.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 8, left: 4),
                                  child: Text(entry.key,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                                ),
                                ...entry.value.map((order) {
                                  final status = order['status'] as String? ?? '';
                                  final orderId = order['id'] as String? ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GestureDetector(
                                      onTap: () => context.push('/driver/order/$orderId'),
                                      child: Container(
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
                                                        decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
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
                                                        decoration: const BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle),
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
                                                    color: _statusColor(status).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(_statusText(status, locale),
                                                      style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.w700)),
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
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _HistoryFilterBtn({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : textSecondary,
          ),
        ),
      ),
    );
  }
}
