import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/providers/client_cache_providers.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

enum _FilterType { all, accepted, cancelled }

class ClientOrdersScreen extends ConsumerStatefulWidget {
  const ClientOrdersScreen({super.key});

  @override
  ConsumerState<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends ConsumerState<ClientOrdersScreen> {
  // Buyurtmalar tarixi keshdan (clientOrdersHistoryCacheProvider — FAQAT
  // 1-sahifa) + mahalliy holatda saqlanadigan keyingi sahifalar
  // (_extraOrders, pastga tortib "load more" bilan yuklanadi) birlashtirib
  // ko'rsatiladi. Backend so'rovning o'zida kHistoryOrderStatuses bilan
  // filtrlanadi (order.service.ts: where.status = { in: statuses } — aniq
  // moslik), shuning uchun bu yerda qo'shimcha status filtri shart emas.
  List<Map<String, dynamic>> get _orders {
    final page1 = ref.read(clientOrdersHistoryCacheProvider).valueOrNull;
    return [...(page1?.orders ?? const []), ..._extraOrders];
  }

  _FilterType _filter = _FilterType.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ==== Sahifalash (2-sahifadan boshlab) ====
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _extraOrders = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    ref.read(clientOrdersHistoryCacheProvider.notifier).refreshIfStale();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  // Bir vaqtda faqat bitta so'rov (himoya: _loadingMore) va oxirgi
  // sahifaga yetilgach yangi so'rov yubormaslik (himoya: _hasMore).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ref.read(clientRepositoryProvider).getOrdersPage(
            page: _currentPage + 1,
            limit: kClientOrdersPageSize,
            status: kHistoryOrderStatuses,
          );
      if (!mounted) return;
      setState(() {
        _extraOrders = [..._extraOrders, ...result.orders];
        _currentPage = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  // Majburiy yangilash — appbar "refresh" tugmasi, pull-to-refresh va
  // buyurtma bekor qilingandan keyin. 1-sahifadan qayta boshlaydi —
  // qo'shimcha sahifalar (_extraOrders) pastdagi ref.listen orqali
  // (build()da) 1-sahifa yangi ma'lumot bilan kelganda tozalanadi.
  Future<void> _load() async {
    await ref.read(clientOrdersHistoryCacheProvider.notifier).forceRefresh();
  }

  // Backend statuslarini guruhga ajratish — endi faqat 2 ta yakuniy guruh
  // qoladi (kutilayotgan/faol holatlar bu sahifada umuman ko'rinmaydi).
  bool _matchesFilter(String status) {
    switch (_filter) {
      case _FilterType.all:
        return true;
      case _FilterType.accepted:
        return ['DELIVERED', 'COMPLETED'].contains(status);
      case _FilterType.cancelled:
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

  // Sana bo'yicha guruhlash: Bugun/Kecha alohida, undan oldingilari oy+yil bo'yicha
  Map<String, List<Map<String, dynamic>>> _groupedByDate(String locale) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final order in _filtered) {
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

  String _filterLabel(_FilterType f, String locale) {
    switch (f) {
      case _FilterType.all: return AppStrings.get('filter_all', locale);
      case _FilterType.accepted: return AppStrings.get('filter_delivered', locale);
      case _FilterType.cancelled: return AppStrings.get('filter_cancelled', locale);
    }
  }

  bool _canCancel(String status) => status == 'SEARCHING' || status == 'OFFERED';

  Future<void> _cancelOrder(String orderId) async {
    await ref.read(clientRepositoryProvider).cancelOrder(orderId);
    _load();
  }

  void _showFilterSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              ..._FilterType.values.map((f) => ListTile(
                    title: Text(_filterLabel(f, locale),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary)),
                    trailing: _filter == f ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
                    onTap: () {
                      setState(() => _filter = f);
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1-sahifa keshi yangi ma'lumot bilan yangilanganda (forceRefresh —
    // pull-to-refresh/appbar tugmasi/refreshIfStale) mahalliy sahifalash
    // holati tozalanadi, shunda eski qo'shimcha sahifalar yangi 1-sahifa
    // ustiga qolib ketmaydi.
    ref.listen<AsyncValue<OrdersPage>>(clientOrdersHistoryCacheProvider, (previous, next) {
      final page = next.valueOrNull;
      if (page == null || identical(previous?.valueOrNull, page)) return;
      setState(() {
        _extraOrders = [];
        _currentPage = 1;
        _hasMore = page.hasMore;
      });
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final ordersAsync = ref.watch(clientOrdersHistoryCacheProvider);
    final loading = ordersAsync.isLoading && !ordersAsync.hasValue;

    final grouped = _groupedByDate(locale);
    final todayLabel = AppStrings.get('today', locale);
    final yesterdayLabel = AppStrings.get('yesterday', locale);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.get('my_orders', locale), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
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
          // Qidiruv + filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _showFilterSheet(context),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(children: [
                      const Center(child: Icon(Icons.tune, color: Colors.white, size: 20)),
                      if (_filter != _FilterType.all)
                        Positioned(
                          right: 7, top: 7,
                          child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),

          // Ro'yxat
          Expanded(
            child: loading
                ? const Center(child: AppLoadingIndicator())
                : _filtered.isEmpty
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
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            ...grouped.entries.map((entry) {
                            final isRecent = entry.key == todayLabel || entry.key == yesterdayLabel;
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
                                            canCancel: _canCancel(status),
                                            statusColor: _statusColor(status),
                                            statusText: _statusText(status, locale),
                                            onTap: () => context.push('/client/order/$orderId'),
                                            onCancel: () => _cancelOrder(orderId),
                                          )
                                        : _CompactOrderCard(
                                            order: order,
                                            status: status,
                                            locale: locale,
                                            isDark: isDark,
                                            canCancel: _canCancel(status),
                                            statusColor: _statusColor(status),
                                            statusText: _statusText(status, locale),
                                            onTap: () => context.push('/client/order/$orderId'),
                                            onCancel: () => _cancelOrder(orderId),
                                          ),
                                  );
                                }),
                              ],
                            );
                            }),
                            if (_loadingMore)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: AppLoadingIndicator()),
                              ),
                          ],
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
  final bool canCancel;
  final Color statusColor;
  final String statusText;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  const _DetailedOrderCard({
    required this.order, required this.status, required this.locale, required this.isDark,
    required this.canCancel, required this.statusColor, required this.statusText,
    required this.onTap, required this.onCancel,
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
              ],
              if (canCancel)
                TextButton(
                  onPressed: onCancel,
                  child: Text(AppStrings.get('cancel', locale), style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w700)),
                )
              else if (!isCancelled)
                GestureDetector(
                  onTap: onTap,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(AppStrings.get('order_details', locale).toUpperCase(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: 0.3)),
                    const Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryColor),
                  ]),
                ),
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
  final bool canCancel;
  final Color statusColor;
  final String statusText;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  const _CompactOrderCard({
    required this.order, required this.status, required this.locale, required this.isDark,
    required this.canCancel, required this.statusColor, required this.statusText,
    required this.onTap, required this.onCancel,
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
                onSelected: (v) {
                  if (v == 'details') onTap();
                  if (v == 'cancel') onCancel();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'details', child: Text(AppStrings.get('order_details', locale))),
                  if (canCancel)
                    PopupMenuItem(value: 'cancel', child: Text(AppStrings.get('cancel', locale), style: const TextStyle(color: AppTheme.errorColor))),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
