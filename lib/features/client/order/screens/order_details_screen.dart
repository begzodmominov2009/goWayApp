import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/providers/client_cache_providers.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/place.dart';

/// Buyurtma tafsilotlari sahifasi — mashina turini, yuk og'irligini, yuk
/// turini va buyurtma vaqtini tanlash. Avval _showOrderDetails() ichida
/// bottom sheet sifatida ko'rsatilardi, endi to'liq ekran sahifa.
///
/// Natija: Navigator.pop(context, createdOrder) — buyurtma muvaffaqiyatli
/// yaratilganda backend'dan qaytgan order obyekti bilan, aks holda null.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  final Place fromPlace;
  final Place toPlace;
  final double? distKm;
  final int? timeMin;

  const OrderDetailsScreen({
    super.key,
    required this.fromPlace,
    required this.toPlace,
    this.distKm,
    this.timeMin,
  });

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  final _noteCtrl = TextEditingController();
  final _cargoTypeCtrl = TextEditingController();
  String? _selectedTruck;
  double? _selectedWeight;
  bool _isScheduled = false;
  bool _isTomorrow = false;
  int? _selectedHour;
  int? _selectedMinute;
  final String _priority = 'STANDARD';
  double? _calculatedPrice;
  bool _priceLoading = false;
  Timer? _priceDebounce;

  // Mashina turlari endi keshdan (clientTrucksCacheProvider) o'qiladi.
  List<Map<String, dynamic>> get _trucks =>
      ref.read(clientTrucksCacheProvider).valueOrNull ?? const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(clientTrucksCacheProvider.notifier).refreshIfStale();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _cargoTypeCtrl.dispose();
    _priceDebounce?.cancel();
    super.dispose();
  }

  void _recalculatePrice() {
    _priceDebounce?.cancel();
    if (_selectedTruck == null || _selectedWeight == null || widget.distKm == null) return;
    _priceDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _priceLoading = true);
      final price = await ref.read(clientRepositoryProvider).calculatePrice(
        truckType: _selectedTruck!, distance: widget.distKm!,
        weight: _selectedWeight!, priority: _priority,
      );
      if (!mounted) return;
      setState(() { _calculatedPrice = price; _priceLoading = false; });
    });
  }

  void _selectNow() {
    setState(() { _isScheduled = false; _isTomorrow = false; });
  }

  void _selectScheduled(bool isTomorrow) {
    final now = TimeOfDay.now();
    setState(() {
      _isScheduled = true;
      _isTomorrow = isTomorrow;
      _selectedHour ??= (now.hour + 1) % 24;
      _selectedMinute ??= 0;
    });
  }

  Future<void> _submit() async {
    final locale = ref.read(localeProvider).languageCode;
    if (_selectedTruck == null) return;
    if (_selectedWeight == null) {
      setState(() => _error = AppStrings.get('enter_weight_error', locale));
      return;
    }

    DateTime? scheduledFor;
    if (_isScheduled) {
      final now = DateTime.now();
      final baseDate = _isTomorrow ? now.add(const Duration(days: 1)) : now;
      scheduledFor = DateTime(
          baseDate.year, baseDate.month, baseDate.day, _selectedHour ?? 0, _selectedMinute ?? 0);
      final minAllowed = now.add(const Duration(hours: 1));
      if (scheduledFor.isBefore(minAllowed)) {
        setState(() => _error = AppStrings.get('order_type_min_time_error', locale));
        return;
      }
    }

    setState(() { _loading = true; _error = null; });
    try {
      final created = await ref.read(clientRepositoryProvider).createOrder(
        fromCity: widget.fromPlace.name,
        fromAddress: widget.fromPlace.address,
        toCity: widget.toPlace.name,
        toAddress: widget.toPlace.address,
        fromLatitude: widget.fromPlace.lat,
        fromLongitude: widget.fromPlace.lng,
        toLatitude: widget.toPlace.lat,
        toLongitude: widget.toPlace.lng,
        truckType: _selectedTruck!,
        weight: _selectedWeight!,
        cargoType: _cargoTypeCtrl.text.trim().isEmpty ? null : _cargoTypeCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        priority: _priority,
        isScheduled: _isScheduled,
        scheduledFor: scheduledFor,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      // Yo'nalish (shahar juftligi) hozircha faol bo'lmasa backend 400
      // bilan javob beradi va o'z xabarida aniq qaysi yo'nalish ekanini
      // aytadi — shu aniq matn to'g'ridan-to'g'ri modalda ko'rsatiladi.
      if (e is OrderCreationException && e.reasonKey == 'bad_request') {
        setState(() => _loading = false);
        _showInactiveRouteDialog(e.serverMessage);
        return;
      }
      setState(() { _loading = false; _error = _errorMessage(e, locale); });
    }
  }

  Future<void> _showInactiveRouteDialog(String? serverMessage) async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.get('route_inactive_title', locale),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 16,
          ),
        ),
        content: Text(
          serverMessage ?? AppStrings.get('generic_error', locale),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppStrings.get('close', locale),
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object e, String locale) {
    if (e is OrderCreationException) {
      switch (e.reasonKey) {
        case 'timeout':
          return AppStrings.get('error_timeout', locale);
        case 'no_connection':
          return AppStrings.get('error_no_connection', locale);
        case 'server_error':
          return AppStrings.get('error_server', locale);
      }
    }
    return AppStrings.get('generic_error', locale);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final trucksAsync = ref.watch(clientTrucksCacheProvider);
    final trucksLoading = trucksAsync.isLoading && !trucksAsync.hasValue;

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
                    AppStrings.get('order_details_page_title', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Column(children: [
                        const Icon(Icons.local_shipping, size: 14, color: AppTheme.primaryColor),
                        Container(width: 1, height: 12, color: border),
                        const Icon(Icons.flag, size: 14, color: AppTheme.successColor),
                      ]),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AddressHelper.shorten(widget.fromPlace.name),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(AddressHelper.shorten(widget.toPlace.name),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      )),
                    ]),
                    const SizedBox(height: 18),

                    if (widget.distKm != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: tabBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.route, size: 16, color: AppTheme.primaryColor),
                          const SizedBox(width: 7),
                          Text('${widget.distKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                          if (widget.timeMin != null) ...[
                            Container(margin: const EdgeInsets.symmetric(horizontal: 10), width: 1, height: 14, color: textSecondary.withOpacity(0.3)),
                            Icon(Icons.access_time, size: 14, color: textSecondary),
                            const SizedBox(width: 5),
                            Text(
                              widget.timeMin! >= 60
                                  ? '${widget.timeMin! ~/ 60}${AppStrings.get('route_time_hour', locale)} ${widget.timeMin! % 60}${AppStrings.get('route_time_min', locale)}'
                                  : '${widget.timeMin} ${AppStrings.get('route_time_min', locale)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 6),
                      Text(AppStrings.get('auto_calculated_hint', locale),
                          style: TextStyle(fontSize: 11, color: textSecondary)),
                      const SizedBox(height: 14),
                    ],

                    Text(AppStrings.get('select_vehicle', locale),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 10),

                    trucksLoading
                        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: AppLoadingIndicator()))
                        : SizedBox(
                            height: 96,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _uniqueTrucks.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (ctx2, i) {
                                final t = _uniqueTrucks[i];
                                final selected = _selectedTruck == t['type'];
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedTruck = t['type'] as String;
                                      _selectedWeight = null;
                                      _calculatedPrice = null;
                                    });
                                    _recalculatePrice();
                                  },
                                  child: Container(
                                    width: 108,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: selected ? AppTheme.primaryColor.withOpacity(0.1) : bg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: selected ? AppTheme.primaryColor : border, width: selected ? 2 : 1),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.local_shipping,
                                            size: 26, color: selected ? AppTheme.primaryColor : textSecondary),
                                        const SizedBox(height: 8),
                                        Text(t['name'] as String? ?? t['type'] as String,
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                                color: selected ? AppTheme.primaryColor : textPrimary),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text('${t['capacity']} t',
                                            style: TextStyle(fontSize: 11, color: textSecondary)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 16),

                    Text(AppStrings.get('weight_tons', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _weightOptions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx2, i) {
                          final w = _weightOptions[i];
                          final selected = _selectedWeight == w;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedWeight = w);
                              _recalculatePrice();
                            },
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
                                    : null,
                                color: selected ? null : bg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: selected ? AppTheme.primaryColor : border, width: selected ? 2 : 1),
                              ),
                              child: Text(
                                '${w.toStringAsFixed(1)} t',
                                style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: selected ? Colors.white : textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(AppStrings.get('cargo_type_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cargoTypeCtrl,
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(hintText: AppStrings.get('cargo_type_hint', locale), hintStyle: TextStyle(color: textSecondary)),
                    ),
                    const SizedBox(height: 16),

                    Text(AppStrings.get('order_when_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _TimeTab(
                          label: AppStrings.get('order_type_now', locale),
                          selected: !_isScheduled,
                          bg: tabBg, textPrimary: textPrimary,
                          onTap: _selectNow,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TimeTab(
                          label: AppStrings.get('order_type_today', locale),
                          selected: _isScheduled && !_isTomorrow,
                          bg: tabBg, textPrimary: textPrimary,
                          onTap: () => _selectScheduled(false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TimeTab(
                          label: AppStrings.get('order_type_tomorrow', locale),
                          selected: _isScheduled && _isTomorrow,
                          bg: tabBg, textPrimary: textPrimary,
                          onTap: () => _selectScheduled(true),
                        ),
                      ),
                    ]),
                    if (_isScheduled) ...[
                      const SizedBox(height: 14),
                      _InlineTimeSelector(
                        hour: _selectedHour ?? 0,
                        minute: _selectedMinute ?? 0,
                        bg: tabBg, textPrimary: textPrimary,
                        onHourChanged: (h) => setState(() => _selectedHour = h),
                        onMinuteChanged: (m) => setState(() => _selectedMinute = m),
                      ),
                    ],
                    const SizedBox(height: 12),

                    TextField(
                      controller: _noteCtrl,
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(hintText: AppStrings.get('note_optional', locale), hintStyle: TextStyle(color: textSecondary)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                    ],
                    if (_priceLoading) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: SizedBox(width: 20, height: 20, child: AppLoadingIndicator(strokeWidth: 2.5)),
                      ),
                    ] else if (_calculatedPrice != null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '${AppStrings.get('estimated_price_label', locale)}: ${_calculatedPrice!.toStringAsFixed(0)} so\'m',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _GradBtn(
                      label: AppStrings.get('place_order', locale),
                      loading: _loading,
                      onTap: (_selectedTruck == null) ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _uniqueTrucks {
    final map = <String, Map<String, dynamic>>{};
    for (final t in _trucks) {
      final key = t['type'] as String;
      if (!map.containsKey(key)) map[key] = t;
    }
    return map.values.toList();
  }

  List<double> get _weightOptions {
    final truck = _uniqueTrucks.firstWhere(
        (t) => t['type'] == _selectedTruck, orElse: () => {});
    final capacity = (truck['capacity'] as num?)?.toDouble() ?? 2.0;
    final step = capacity / 20;
    return List.generate(
        20, (i) => double.parse(((i + 1) * step).toStringAsFixed(2)));
  }
}

class _TimeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Color bg;
  final Color textPrimary;
  final VoidCallback onTap;

  const _TimeTab({
    required this.label, required this.selected,
    required this.bg, required this.textPrimary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
        ),
      ),
    );
  }
}

/// Soat/daqiqa tanlash — hour_minute_picker.dart dagi vizual naqshga
/// o'xshab, lekin alohida modal emas, shu sahifaning ichida ko'rinadi.
class _InlineTimeSelector extends StatelessWidget {
  static const List<int> _allowedMinutes = [0, 15, 30, 45];

  final int hour;
  final int minute;
  final Color bg;
  final Color textPrimary;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  const _InlineTimeSelector({
    required this.hour,
    required this.minute,
    required this.bg,
    required this.textPrimary,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 24,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) => _TimeChip(
              label: i.toString().padLeft(2, '0'),
              width: 42,
              selected: i == hour,
              bg: bg, textPrimary: textPrimary,
              onTap: () => onHourChanged(i),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _allowedMinutes.map((m) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _TimeChip(
                  label: m.toString().padLeft(2, '0'),
                  selected: m == minute,
                  bg: bg, textPrimary: textPrimary,
                  onTap: () => onMinuteChanged(m),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final double? width;
  final bool selected;
  final Color bg;
  final Color textPrimary;
  final VoidCallback onTap;

  const _TimeChip({
    required this.label, this.width, required this.selected,
    required this.bg, required this.textPrimary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : bg,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
        ),
      ),
    );
  }
}

class _GradBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _GradBtn({required this.label, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity, height: 50,
        decoration: BoxDecoration(
          gradient: enabled ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight) : null,
          color: enabled ? null : Colors.grey.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 22, height: 22, child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
