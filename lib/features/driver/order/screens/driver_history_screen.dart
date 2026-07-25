import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/providers/driver_cache_providers.dart';
import '../../../../core/router/app_router.dart';

class DriverHistoryScreen extends ConsumerStatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  ConsumerState<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends ConsumerState<DriverHistoryScreen> {
  // Buyurtmalar tarixi endi keshdan (driverHistoryCacheProvider) o'qiladi.
  List<Map<String, dynamic>> get _orders {
    final data = ref.read(driverHistoryCacheProvider).valueOrNull;
    return ((data?['orders'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    ref.read(driverHistoryCacheProvider.notifier).refreshIfStale();
  }

  // Majburiy yangilash — appbar "refresh" tugmasi va pull-to-refresh.
  Future<void> _load() async {
    await ref.read(driverHistoryCacheProvider.notifier).forceRefresh();
  }

  // Faqat oxirgi 7 kunlik buyurtmalar
  List<Map<String, dynamic>> get _recentOrders {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _orders.where((order) {
      final createdAt = order['createdAt'] as String?;
      if (createdAt == null) return false;
      final date = DateTime.tryParse(createdAt);
      return date != null && date.isAfter(cutoff);
    }).toList();
  }

  // Sana bo'yicha guruhlash — client_orders_screen.dart bilan bir xil naqsh
  Map<String, List<Map<String, dynamic>>> _groupedByDate(String locale) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final order in _recentOrders) {
      final createdAt = order['createdAt'] as String?;
      if (createdAt == null) continue;
      final date = DateTime.tryParse(createdAt)?.toLocal();
      if (date == null) continue;
      final dateOnly = DateTime(date.year, date.month, date.day);

      String label;
      if (dateOnly == today) {
        label = AppStrings.get('today', locale);
      } else if (dateOnly == yesterday) {
        label = AppStrings.get('yesterday', locale);
      } else {
        label = _monthYearLabel(date, locale);
      }

      grouped.putIfAbsent(label, () => []).add(order);
    }
    return grouped;
  }

  String _monthYearLabel(DateTime date, String locale) {
    final key = 'month_${date.month.toString().padLeft(2, '0')}';
    return '${AppStrings.get(key, locale)} ${date.year}';
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
    final historyAsync = ref.watch(driverHistoryCacheProvider);
    final loading = historyAsync.isLoading && !historyAsync.hasValue;

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
        title: Text(AppStrings.get('order_history_title', locale),
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
          // "Barchasini ko'rish" — to'liq tarix sahifasiga o'tish (faqat tarix mavjud bo'lsa)
          if (_recentOrders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push(AppRoutes.driverOrderHistoryFull),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppStrings.get('view_all_history', locale),
                          style: const TextStyle(fontSize: 13, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                      const Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
              ),
            ),

          // Ro'yxat — oxirgi 7 kunlik, sana bo'yicha guruhlangan
          Expanded(
            child: loading
                ? const Center(child: AppLoadingIndicator())
                : grouped.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: textSecondary),
                            const SizedBox(height: 12),
                            Text(AppStrings.get('no_orders_found', locale), style: TextStyle(color: textSecondary, fontSize: 15)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: grouped.entries.map((entry) {
                            final isRecent = entry.key == AppStrings.get('today', locale) || entry.key == AppStrings.get('yesterday', locale);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 14, bottom: 10),
                                  child: Row(children: [
                                    Text(entry.key,
                                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Divider(color: border, thickness: 1)),
                                  ]),
                                ),
                                ...entry.value.map((order) {
                                  final status = order['status'] as String? ?? '';
                                  final orderId = order['id'] as String? ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: isRecent
                                        ? _DetailedOrderCard(
                                            order: order,
                                            status: status,
                                            locale: locale,
                                            isDark: isDark,
                                            statusColor: _statusColor(status),
                                            statusText: _statusText(status, locale),
                                            onTap: () => context.push('/driver/order/$orderId'),
                                          )
                                        : _CompactOrderCard(
                                            order: order,
                                            status: status,
                                            locale: locale,
                                            isDark: isDark,
                                            statusColor: _statusColor(status),
                                            statusText: _statusText(status, locale),
                                            onTap: () => context.push('/driver/order/$orderId'),
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

String _shortTripId(String id) => id.isEmpty ? '' : (id.length >= 6 ? id.substring(0, 6) : id).toUpperCase();

String _time12h(DateTime date) {
  final local = date.toLocal();
  final period = local.hour >= 12 ? 'PM' : 'AM';
  final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  return '$h12:$m $period';
}

IconData _leadingIconFor(String status) {
  if (status == 'CANCELLED') return Icons.close;
  if (status == 'DELIVERED' || status == 'COMPLETED') return Icons.local_shipping;
  return Icons.access_time_outlined;
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    );
  }
}

class _DetailedOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String status;
  final String locale;
  final bool isDark;
  final Color statusColor;
  final String statusText;
  final VoidCallback onTap;

  const _DetailedOrderCard({
    required this.order, required this.status, required this.locale, required this.isDark,
    required this.statusColor, required this.statusText, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final orderId = order['id'] as String? ?? '';
    final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '');
    final isCancelled = status == 'CANCELLED';
    final price = order['price'] as num?;
    final priceText = price != null ? '${price.toStringAsFixed(0)} so\'m' : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: statusColor.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(_leadingIconFor(status), color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${AppStrings.get('trip_label', locale)} #${_shortTripId(orderId)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(_time12h(createdAt), style: TextStyle(fontSize: 12, color: textSecondary)),
                  ],
                ]),
              ),
              _StatusPill(text: statusText, color: statusColor),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                Container(width: 2, height: 32, color: border),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle)),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppStrings.get('from_label', locale), style: TextStyle(fontSize: 10, color: textSecondary)),
                  Text(order['fromCity'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Text(AppStrings.get('to_label', locale), style: TextStyle(fontSize: 10, color: textSecondary)),
                  Text(order['toCity'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Divider(color: border, height: 1),
            const SizedBox(height: 10),
            Row(children: [
              if (isCancelled) ...[
                if (priceText.isNotEmpty)
                  Text(priceText, style: TextStyle(fontSize: 14, color: textSecondary, decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.get('order_cancelled', locale),
                      style: const TextStyle(fontSize: 12, color: AppTheme.errorColor, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ] else ...[
                Expanded(child: Text(priceText, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary))),
                GestureDetector(
                  onTap: onTap,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(AppStrings.get('order_details', locale).toUpperCase(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: 0.3)),
                    const Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryColor),
                  ]),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

class _CompactOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String status;
  final String locale;
  final bool isDark;
  final Color statusColor;
  final String statusText;
  final VoidCallback onTap;

  const _CompactOrderCard({
    required this.order, required this.status, required this.locale, required this.isDark,
    required this.statusColor, required this.statusText, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '');
    final isCancelled = status == 'CANCELLED';
    final price = order['price'] as num?;
    final priceText = price != null ? '${price.toStringAsFixed(0)} so\'m' : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (createdAt != null)
                Text('${createdAt.day} ${AppStrings.get('month_${createdAt.month.toString().padLeft(2, '0')}', locale)} • ${_time12h(createdAt)}',
                    style: TextStyle(fontSize: 12, color: textSecondary)),
              const Spacer(),
              _StatusPill(text: statusText, color: statusColor),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.primaryColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(order['fromCity'] as String? ?? '',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 12, color: textSecondary),
              ),
              const Icon(Icons.near_me_outlined, size: 13, color: AppTheme.successColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(order['toCity'] as String? ?? '',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (isCancelled) ...[
                if (priceText.isNotEmpty)
                  Text(priceText, style: TextStyle(fontSize: 13, color: textSecondary, decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.get('order_cancelled', locale),
                      style: const TextStyle(fontSize: 11, color: AppTheme.errorColor, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ] else
                Expanded(child: Text(priceText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary))),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: textSecondary),
                padding: EdgeInsets.zero,
                onSelected: (_) => onTap(),
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'details', child: Text(AppStrings.get('order_details', locale))),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
