import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/geo_repository.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/tutorial_sheet.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

/// Rejalashtirilgan (kelajakdagi) buyurtmalar ro'yxati — "Bugun"/"Ertaga"
/// tablari orasida almashib, yo'nalish bo'yicha filtrlab, har bir
/// buyurtmani ko'rish va qabul qilish imkonini beradi.
class DriverScheduledOrdersScreen extends ConsumerStatefulWidget {
  const DriverScheduledOrdersScreen({super.key});

  @override
  ConsumerState<DriverScheduledOrdersScreen> createState() => _DriverScheduledOrdersScreenState();
}

class _DriverScheduledOrdersScreenState extends ConsumerState<DriverScheduledOrdersScreen> {
  String _day = 'today';
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];

  List<_LineOption> _driverLines = [];
  String? _selectedLineId;
  String _selectedLineLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadDriverLines();
    _maybeShowScheduledTutorial();
  }

  Future<void> _maybeShowScheduledTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seen_scheduled_tutorial') == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showScheduledTutorial();
    });
    await prefs.setBool('seen_scheduled_tutorial', true);
  }

  void _showScheduledTutorial() {
    final locale = ref.read(localeProvider).languageCode;
    showTutorialSheet(
      context,
      title: AppStrings.get('tutorial_scheduled_title', locale),
      bullets: [
        AppStrings.get('tutorial_scheduled_1', locale),
        AppStrings.get('tutorial_scheduled_2', locale),
        AppStrings.get('tutorial_scheduled_3', locale),
        AppStrings.get('tutorial_scheduled_4', locale),
      ],
      icon: Icons.event_note,
      locale: locale,
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(driverRepositoryProvider).getScheduledOrders(_day, lineId: _selectedLineId);
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[DriverScheduledOrdersScreen] Rejalashtirilgan buyurtmalarni yuklashda xatolik: $e');
      if (mounted) setState(() { _orders = []; _loading = false; });
    }
  }

  Future<void> _loadDriverLines() async {
    try {
      final raw = await ref.read(driverRepositoryProvider).getDriverLines();
      final items = raw.map((e) => _LineOption.fromJson(e)).toList();
      if (!mounted) return;
      setState(() => _driverLines = items);
      _resolveLineLabels();
    } catch (e) {
      debugPrint('[DriverScheduledOrdersScreen] Liniyalarni yuklashda xatolik: $e');
    }
  }

  Future<void> _resolveLineLabels() async {
    if (_driverLines.isEmpty) return;
    final repo = ref.read(geoRepositoryProvider);
    final regions = await repo.getAllRegions();
    final districtsCache = <String, List<GeoDistrict>>{};

    GeoRegion? findRegion(String? id) {
      if (id == null) return null;
      for (final r in regions) {
        if (r.id == id) return r;
      }
      return null;
    }

    GeoDistrict? findDistrict(List<GeoDistrict> list, String? id) {
      if (id == null) return null;
      for (final d in list) {
        if (d.id == id) return d;
      }
      return null;
    }

    for (final line in _driverLines) {
      if (line.fromDistrictId != null && line.fromRegionId != null) {
        districtsCache[line.fromRegionId!] ??= await repo.getAllDistricts(line.fromRegionId!);
        line.fromLabel = findDistrict(districtsCache[line.fromRegionId!]!, line.fromDistrictId)?.name
            ?? findRegion(line.fromRegionId)?.name ?? '';
      } else {
        line.fromLabel = findRegion(line.fromRegionId)?.name ?? '';
      }
      if (line.toDistrictId != null && line.toRegionId != null) {
        districtsCache[line.toRegionId!] ??= await repo.getAllDistricts(line.toRegionId!);
        line.toLabel = findDistrict(districtsCache[line.toRegionId!]!, line.toDistrictId)?.name
            ?? findRegion(line.toRegionId)?.name ?? '';
      } else {
        line.toLabel = findRegion(line.toRegionId)?.name ?? '';
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  void _switchDay(String day) {
    if (_day == day) return;
    setState(() => _day = day);
    _load();
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_LineOption>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _RouteFilterSheet(lines: _driverLines, currentLineId: _selectedLineId),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedLineId = result.id;
      _selectedLineLabel = result.id == null ? '' : '${result.fromLabel} → ${result.toLabel}';
    });
    _load();
  }

  void _clearFilter() {
    setState(() {
      _selectedLineId = null;
      _selectedLineLabel = '';
    });
    _load();
  }

  Future<void> _openDetail(Map<String, dynamic> order) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderDetailSheet(order: order),
    );
    if (result == null || !mounted) return;

    final locale = ref.read(localeProvider).languageCode;
    final success = result['success'] == true;
    final message = result['message'] as String?;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? AppStrings.get('order_accepted_success', locale)
            : (message ?? AppStrings.get('order_already_taken', locale))),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
    // Buyurtma qabul qilingan yoki boshqa haydovchiga tegishli bo'lib
    // qolgan bo'lsa ham, u endi ro'yxatdan chiqishi kerak — shuning
    // uchun ikkala holatda ham ro'yxat yangilanadi.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

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
                    AppStrings.get('scheduled_orders_title', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.help_outline, color: textSecondary, size: 20),
                    onPressed: _showScheduledTutorial,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _DayTab(
                      label: AppStrings.get('today_tab', locale),
                      selected: _day == 'today',
                      isDark: isDark,
                      onTap: () => _switchDay('today'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DayTab(
                      label: AppStrings.get('tomorrow_tab', locale),
                      selected: _day == 'tomorrow',
                      isDark: isDark,
                      onTap: () => _switchDay('tomorrow'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: _selectedLineId != null ? AppTheme.primaryColor.withOpacity(0.1) : bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _selectedLineId != null ? AppTheme.primaryColor.withOpacity(0.4) : border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.route_outlined, size: 14, color: _selectedLineId != null ? AppTheme.primaryColor : textSecondary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _selectedLineId == null ? AppStrings.get('all_routes', locale) : _selectedLineLabel,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: _selectedLineId != null ? AppTheme.primaryColor : textPrimary,
                              ),
                            ),
                          ),
                          if (_selectedLineId != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _clearFilter,
                              child: const Icon(Icons.close, size: 14, color: AppTheme.primaryColor),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.tune, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: 4,
                      itemBuilder: (ctx, i) => _SkeletonOrderCard(isDark: isDark),
                    )
                  : _orders.isEmpty
                      ? _EmptyState(locale: locale, textSecondary: textSecondary)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: _orders.length,
                            itemBuilder: (ctx, i) {
                              final order = _orders[i];
                              return _ScheduledOrderCard(
                                order: order,
                                isDark: isDark,
                                locale: locale,
                                surface: surface,
                                border: border,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                isYourRoute: _isYourRoute(order, _driverLines),
                                onDetail: () => _openDetail(order),
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

bool _isYourRoute(Map<String, dynamic> order, List<_LineOption> lines) {
  if (lines.isEmpty) return false;
  final orderFromDistrictId = order['fromDistrictId'] as String?;
  final orderToDistrictId = order['toDistrictId'] as String?;
  final orderFromRegionId = order['fromRegionId'] as String?;
  final orderToRegionId = order['toRegionId'] as String?;
  final fromCity = (order['fromCity'] as String? ?? '').toLowerCase();
  final toCity = (order['toCity'] as String? ?? '').toLowerCase();

  for (final line in lines) {
    if (orderFromDistrictId != null && orderToDistrictId != null &&
        line.fromDistrictId != null && line.toDistrictId != null) {
      if (line.fromDistrictId == orderFromDistrictId && line.toDistrictId == orderToDistrictId) return true;
      continue;
    }
    if (orderFromRegionId != null && orderToRegionId != null &&
        line.fromRegionId != null && line.toRegionId != null) {
      if (line.fromRegionId == orderFromRegionId && line.toRegionId == orderToRegionId) return true;
      continue;
    }
    if (fromCity.isNotEmpty && toCity.isNotEmpty && line.fromLabel.isNotEmpty && line.toLabel.isNotEmpty) {
      final lineFrom = line.fromLabel.toLowerCase();
      final lineTo = line.toLabel.toLowerCase();
      if ((fromCity.contains(lineFrom) || lineFrom.contains(fromCity)) &&
          (toCity.contains(lineTo) || lineTo.contains(toCity))) {
        return true;
      }
    }
  }
  return false;
}

String _formatTime(dynamic iso) {
  if (iso is! String) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String? _extractClientName(Map<String, dynamic> order) {
  final client = order['client'];
  if (client is Map) {
    final name = client['fullName'] ?? client['name'];
    if (name is String && name.isNotEmpty) return name;
  }
  final flat = order['clientName'];
  if (flat is String && flat.isNotEmpty) return flat;
  return null;
}

/// Haydovchining bitta yo'nalishi — filter sheet'da va "Sizning
/// yo'nalishingiz" solishtiruvida ishlatiladi. `id == null` — "Barcha
/// yo'nalishlar" (filtrsiz) variantini bildiradi.
class _LineOption {
  final String? id;
  final String? fromRegionId;
  final String? fromDistrictId;
  final String? toRegionId;
  final String? toDistrictId;
  String fromLabel;
  String toLabel;

  _LineOption({
    this.id, this.fromRegionId, this.fromDistrictId,
    this.toRegionId, this.toDistrictId,
    this.fromLabel = '', this.toLabel = '',
  });

  factory _LineOption.fromJson(Map<String, dynamic> json) => _LineOption(
        id: json['id']?.toString(),
        fromRegionId: json['fromRegionId'] as String?,
        fromDistrictId: json['fromDistrictId'] as String?,
        toRegionId: json['toRegionId'] as String?,
        toDistrictId: json['toDistrictId'] as String?,
      );
}

class _RouteFilterSheet extends ConsumerWidget {
  final List<_LineOption> lines;
  final String? currentLineId;
  const _RouteFilterSheet({required this.lines, required this.currentLineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(AppStrings.get('filter_by_route', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
            ),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.route_outlined, color: currentLineId == null ? AppTheme.primaryColor : textSecondary),
              title: Text(AppStrings.get('all_routes', locale),
                  style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary)),
              trailing: currentLineId == null ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
              onTap: () => Navigator.pop(context, _LineOption(id: null)),
            ),
            if (lines.isNotEmpty) Divider(height: 1, color: border),
            ...lines.map((l) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.alt_route, color: currentLineId == l.id ? AppTheme.primaryColor : textSecondary),
                  title: Text(
                    '${l.fromLabel} → ${l.toLabel}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                  trailing: currentLineId == l.id ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
                  onTap: () => Navigator.pop(context, l),
                )),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _DayTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _DayTab({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.transparent : border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String locale;
  final Color textSecondary;
  const _EmptyState({required this.locale, required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_outlined, size: 48, color: textSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            AppStrings.get('no_scheduled_orders', locale),
            style: TextStyle(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ScheduledOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final bool isYourRoute;
  final VoidCallback onDetail;

  const _ScheduledOrderCard({
    required this.order, required this.isDark, required this.locale,
    required this.surface, required this.border, required this.textPrimary,
    required this.textSecondary, required this.isYourRoute, required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final fromCity = order['fromCity'] as String? ?? '';
    final toCity = order['toCity'] as String? ?? '';
    final price = (order['price'] as num?) ?? 0;
    final timeText = _formatTime(order['scheduledFor']);
    final priceText = price > 0
        ? '${(price / 1000).toStringAsFixed(0)}000 so\'m'
        : AppStrings.get('price_not_set', locale);

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
              if (timeText.isNotEmpty) ...[
                const Icon(Icons.access_time, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(timeText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
              ],
              const Spacer(),
              Text(priceText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          if (isYourRoute) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 11, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Text(AppStrings.get('your_route_badge', locale),
                      style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
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
            child: OutlinedButton(
              onPressed: onDetail,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: AppTheme.primaryColor),
                foregroundColor: AppTheme.primaryColor,
              ),
              child: Text(AppStrings.get('order_details', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _OrderDetailSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const _OrderDetailSheet({required this.order});

  @override
  ConsumerState<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<_OrderDetailSheet> {
  bool _accepting = false;

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    final orderId = widget.order['id'].toString();
    try {
      await ref.read(driverRepositoryProvider).acceptScheduledOrder(orderId);
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      String? message;
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] is String) message = data['message'] as String;
      }
      if (mounted) Navigator.pop(context, {'success': false, 'message': message});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    final order = widget.order;
    final truckType = order['truckType'] as String? ?? '';
    final weight = order['weight'];
    final price = (order['price'] as num?) ?? 0;
    final note = order['note'] as String?;
    final clientName = _extractClientName(order);
    final timeText = _formatTime(order['scheduledFor']);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(AppStrings.get('order_detail_title', locale),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 14),
            if (clientName != null) ...[
              _DetailRow(icon: Icons.person_outline, label: AppStrings.get('full_name', locale), value: clientName,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
              const SizedBox(height: 10),
            ],
            if (timeText.isNotEmpty) ...[
              _DetailRow(icon: Icons.access_time, label: AppStrings.get('scheduled_time_label', locale), value: timeText,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
              const SizedBox(height: 10),
            ],
            _DetailRow(
              icon: Icons.local_shipping_outlined,
              label: AppStrings.get('vehicle_type_label', locale),
              value: truckType,
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.scale_outlined,
              label: AppStrings.get('weight_label', locale),
              value: weight != null ? '$weight t' : '-',
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.payments_outlined,
              label: AppStrings.get('price_label', locale),
              value: price > 0 ? '${(price / 1000).toStringAsFixed(0)}000 so\'m' : AppStrings.get('price_not_set', locale),
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.notes_outlined,
                label: AppStrings.get('note_label', locale),
                value: note,
                bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _accepting ? null : _accept,
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  gradient: _accepting ? null : const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  color: _accepting ? Colors.grey.withOpacity(0.25) : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _accepting
                      ? const SizedBox(width: 22, height: 22, child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(AppStrings.get('accept_order', locale), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color bg;
  final Color border;
  final Color textP;
  final Color textS;

  const _DetailRow({
    required this.icon, required this.label, required this.value,
    required this.bg, required this.border, required this.textP, required this.textS,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 0.5)),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: textS))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textP), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
