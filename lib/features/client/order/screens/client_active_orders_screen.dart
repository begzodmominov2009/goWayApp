import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';

// driver qabul qilgandan yetkazib berilgunicha bo'lgan holatlar —
// order_progress_screen.dart dagi _kFoundStatuses va
// active_order_details_screen.dart dagi _kLiveTrackedStatuses bilan bir xil
// ro'yxat (backend OrderStatus enumidan tekshirilgan: SEARCHING, OFFERED,
// ACCEPTED, DRIVER_ARRIVING, LOADING, IN_TRANSIT, DELIVERED, COMPLETED,
// CANCELLED, SCHEDULED).
const List<String> _kActiveStatuses = ['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'];

/// Client uchun — driver qabul qilib, hozir bajarayotgan buyurtmalar
/// ro'yxati. driver_scheduled_orders_screen.dart namuna sifatida olingan
/// (kartochka ko'rinishi, bo'sh holat, skelet), lekin bu yerda kun
/// tablari/qidiruv/filtr yo'q — faqat oddiy ro'yxat, chunki odatda faol
/// buyurtma bittadan ko'p bo'lmaydi. Har bir kartochka mavjud
/// active_order_details_screen.dart (jonli kuzatuv) ga o'tkazadi — bu
/// ekranning o'ziga umuman tegilmagan.
class ClientActiveOrdersScreen extends ConsumerStatefulWidget {
  const ClientActiveOrdersScreen({super.key});

  @override
  ConsumerState<ClientActiveOrdersScreen> createState() => _ClientActiveOrdersScreenState();
}

class _ClientActiveOrdersScreenState extends ConsumerState<ClientActiveOrdersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(clientRepositoryProvider).getOrders();
      if (!mounted) return;
      setState(() {
        _orders = list.where((o) => _kActiveStatuses.contains(o['status'] as String? ?? '')).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ClientActiveOrdersScreen] Faol buyurtmalarni yuklashda xatolik: $e');
      if (mounted) setState(() { _orders = []; _loading = false; });
    }
  }

  void _openTracking(Map<String, dynamic> order) {
    context.push(AppRoutes.clientActiveOrderDetails, extra: {'order': order});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    AppStrings.get('my_active_orders', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: 3,
                      itemBuilder: (ctx, i) => _SkeletonOrderCard(isDark: isDark),
                    )
                  : _orders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_shipping_outlined, size: 48, color: textSecondary.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              Text(
                                AppStrings.get('no_active_orders', locale),
                                style: TextStyle(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: _orders.length,
                            itemBuilder: (ctx, i) {
                              final order = _orders[i];
                              return _ActiveOrderCard(
                                order: order,
                                isDark: isDark,
                                locale: locale,
                                surface: surface,
                                border: border,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                onTrack: () => _openTracking(order),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'ACCEPTED':
      return AppTheme.primaryColor;
    case 'DRIVER_ARRIVING':
      return AppTheme.warningColor;
    case 'LOADING':
    case 'IN_TRANSIT':
      return AppTheme.successColor;
    default:
      return AppTheme.primaryColor;
  }
}

String _statusText(String status, String locale) {
  switch (status) {
    case 'ACCEPTED': return AppStrings.get('status_accepted', locale);
    case 'DRIVER_ARRIVING': return AppStrings.get('status_driver_arriving', locale);
    case 'LOADING': return AppStrings.get('status_loading', locale);
    case 'IN_TRANSIT': return AppStrings.get('status_in_transit', locale);
    default: return status;
  }
}

class _ActiveOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTrack;

  const _ActiveOrderCard({
    required this.order, required this.isDark, required this.locale,
    required this.surface, required this.border, required this.textPrimary,
    required this.textSecondary, required this.onTrack,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? '';
    final fromCity = order['fromCity'] as String? ?? '';
    final toCity = order['toCity'] as String? ?? '';
    final price = (order['price'] as num?) ?? 0;
    final priceText = price > 0
        ? '${(price / 1000).toStringAsFixed(0)}000 so\'m'
        : AppStrings.get('price_not_set', locale);
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.25 : 0.06), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(_statusText(status, locale),
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ),
              const Spacer(),
              Text(priceText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Column(children: [
                const Icon(Icons.local_shipping, size: 14, color: AppTheme.primaryColor),
                Container(width: 1, height: 12, color: border),
                const Icon(Icons.flag, size: 14, color: AppTheme.successColor),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fromCity, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(toCity, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onTrack,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: AppTheme.primaryColor),
                foregroundColor: AppTheme.primaryColor,
              ),
              icon: const Icon(Icons.my_location, size: 16),
              label: Text(AppStrings.get('live_tracking', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buyurtma kartasi o'rnida ko'rinadigan miltillovchi skelet.
class _SkeletonOrderCard extends StatelessWidget {
  final bool isDark;
  const _SkeletonOrderCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final highlight = isDark ? const Color(0xFF475569) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 60, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              const Spacer(),
              Container(width: 70, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ]),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(width: 140, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}
