import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';

/// Rejalashtirilgan (kelajakdagi) buyurtmalar ro'yxati — "Bugun"/"Ertaga"
/// tablari orasida almashib, har bir buyurtmani ko'rish va qabul qilish
/// imkonini beradi.
class DriverScheduledOrdersScreen extends ConsumerStatefulWidget {
  const DriverScheduledOrdersScreen({super.key});

  @override
  ConsumerState<DriverScheduledOrdersScreen> createState() => _DriverScheduledOrdersScreenState();
}

class _DriverScheduledOrdersScreenState extends ConsumerState<DriverScheduledOrdersScreen> {
  String _day = 'today';
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
      final list = await ref.read(driverRepositoryProvider).getScheduledOrders(_day);
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _orders = []; _loading = false; });
    }
  }

  void _switchDay(String day) {
    if (_day == day) return;
    setState(() => _day = day);
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
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: AppLoadingIndicator())
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
  final VoidCallback onDetail;

  const _ScheduledOrderCard({
    required this.order, required this.isDark, required this.locale,
    required this.surface, required this.border, required this.textPrimary,
    required this.textSecondary, required this.onDetail,
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
