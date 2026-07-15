import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/place.dart';

/// Buyurtma tafsilotlari sahifasi — mashina turini va yuk og'irligini
/// tanlash. Avval _showOrderDetails() ichida bottom sheet sifatida
/// ko'rsatilardi, endi to'liq ekran sahifa.
///
/// Natija: Navigator.pop(context, createdOrder) — buyurtma muvaffaqiyatli
/// yaratilganda backend'dan qaytgan order obyekti bilan, aks holda null.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  final Place fromPlace;
  final Place toPlace;

  const OrderDetailsScreen({
    super.key,
    required this.fromPlace,
    required this.toPlace,
  });

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  final _weightCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedTruck;
  List<Map<String, dynamic>> _trucks = [];
  bool _loading = false;
  bool _trucksLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(clientRepositoryProvider).getTrucks().then((t) {
      if (!mounted) return;
      setState(() { _trucksLoading = false; _trucks = t; });
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final locale = ref.read(localeProvider).languageCode;
    if (_selectedTruck == null) return;
    if (_weightCtrl.text.isEmpty) {
      setState(() => _error = AppStrings.get('enter_weight_error', locale));
      return;
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
        weight: double.parse(_weightCtrl.text),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = _errorMessage(e, locale); });
    }
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

                    Text(AppStrings.get('select_vehicle', locale),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 10),

                    _trucksLoading
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
                                  onTap: () => setState(() => _selectedTruck = t['type'] as String),
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
                    TextField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(hintText: '1.5', hintStyle: TextStyle(color: textSecondary), suffixText: 't'),
                    ),
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
