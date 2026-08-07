import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/providers/client_cache_providers.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/place.dart';
import '../../../../shared/widgets/map_address_picker.dart';

/// "Qayerdan?" / "Qayerga?" manzillarini tanlash sahifasi — avval
/// AddressModal orqali bottom sheet sifatida ko'rsatilardi, endi
/// to'liq ekran sahifa (go_router orqali navigatsiya qilinadi).
///
/// Natija: Navigator.pop(context, {'from': Place, 'to': Place}) —
/// ikkala manzil ham tanlanganda qaytariladi, aks holda null.
class SelectAddressScreen extends ConsumerStatefulWidget {
  final Place? initialFrom;
  final Place? initialTo;
  final double fromLat;
  final double fromLng;

  const SelectAddressScreen({
    super.key,
    required this.initialFrom,
    this.initialTo,
    required this.fromLat,
    required this.fromLng,
  });

  @override
  ConsumerState<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SelectAddressScreenState extends ConsumerState<SelectAddressScreen> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  Place? _fromPlace;
  Place? _toPlace;

  List<Place> _fromResults = [];
  List<Place> _toResults = [];
  bool _fromSearching = false;
  bool _toSearching = false;
  bool _fromFocused = false;
  bool _toFocused = false;

  Timer? _fromTimer;
  Timer? _toTimer;

  final Set<String> _savedPlaceKeys = {};

  bool get _allFilled => _fromPlace != null && _toPlace != null;

  @override
  void initState() {
    super.initState();
    _fromPlace = widget.initialFrom;
    _toPlace = widget.initialTo;
    _fromCtrl = TextEditingController(text: widget.initialFrom?.name ?? '');
    _toCtrl = TextEditingController(text: widget.initialTo?.name ?? '');

    _fromFocus.addListener(() => setState(() => _fromFocused = _fromFocus.hasFocus));
    _toFocus.addListener(() => setState(() => _toFocused = _toFocus.hasFocus));

    if (widget.initialTo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_toFocus);
      });
    }
    // Tezkor tanlash ro'yxati — SavedAddressesScreen bilan bir xil keshni
    // ulashadi (clientSavedAddressesCacheProvider), shu sabab bu yerga
    // o'tilganda yangi so'rov ketmaydi.
    ref.read(clientSavedAddressesCacheProvider.notifier).refreshIfStale();
  }

  // Yangi manzil tezkor saqlangandan keyin (majburiy yangilash).
  Future<void> _loadSavedAddresses() async {
    await ref.read(clientSavedAddressesCacheProvider.notifier).forceRefresh();
  }

  String _placeKey(Place p) => '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}';

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _fromTimer?.cancel();
    _toTimer?.cancel();
    super.dispose();
  }

  void _onFromChanged(String val) {
    _fromTimer?.cancel();
    if (val.isEmpty) {
      setState(() { _fromResults = []; _fromPlace = null; });
      return;
    }
    setState(() => _fromSearching = true);
    _fromTimer = Timer(const Duration(milliseconds: 500), () async {
      final results = await _search(val);
      if (mounted) setState(() { _fromResults = results; _fromSearching = false; });
    });
  }

  void _onToChanged(String val) {
    _toTimer?.cancel();
    if (val.isEmpty) {
      setState(() { _toResults = []; _toPlace = null; });
      return;
    }
    setState(() => _toSearching = true);
    _toTimer = Timer(const Duration(milliseconds: 500), () async {
      final results = await _search(val);
      if (mounted) setState(() { _toResults = results; _toSearching = false; });
    });
  }

  Future<List<Place>> _search(String query) async {
    final repo = ref.read(geocodeRepositoryProvider);
    final results = await repo.search(query, lat: widget.fromLat, lng: widget.fromLng);
    return results
        .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
        .toList();
  }

  Future<void> _openPicker(bool isFrom) async {
    final locale = ref.read(localeProvider).languageCode;
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapAddressPicker(
          initialLat: isFrom ? widget.fromLat : (_toPlace?.lat ?? widget.fromLat),
          initialLng: isFrom ? widget.fromLng : (_toPlace?.lng ?? widget.fromLng),
          title: isFrom ? AppStrings.get('from_question', locale) : AppStrings.get('to_question', locale),
          isFrom: isFrom,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isFrom) { _fromPlace = result; _fromCtrl.text = result.name; }
      else { _toPlace = result; _toCtrl.text = result.name; }
    });
  }

  // Tanlangan natijani inputga joylashtirish. Avval fokusni yo'qotamiz,
  // keyin bir freym kutib (addPostFrameCallback) matnni yangilaymiz —
  // aks holda FocusNode listener bilan setState orasida nomuvofiqlik
  // (race condition) yuzaga kelib, matn ekranga chiqmasligi mumkin edi.
  void _selectResult(Place place, {required bool isFrom}) {
    if (isFrom) {
      _fromFocus.unfocus();
    } else {
      _toFocus.unfocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (isFrom) {
          _fromPlace = place;
          _fromCtrl.text = place.name;
          _fromCtrl.selection = TextSelection.collapsed(offset: place.name.length);
          _fromResults = [];
          _fromFocused = false;
        } else {
          _toPlace = place;
          _toCtrl.text = place.name;
          _toCtrl.selection = TextSelection.collapsed(offset: place.name.length);
          _toResults = [];
          _toFocused = false;
        }
      });
    });
  }

  Future<void> _showQuickSaveDialog(Place place) async {
    if (_savedPlaceKeys.contains(_placeKey(place))) return;
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('quick_save_address_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameCtrl,
          style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
          decoration: InputDecoration(hintText: AppStrings.get('address_name_optional_hint', locale)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get('save', locale)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(clientRepositoryProvider).saveSavedAddress(
            name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : place.name,
            address: place.address.isNotEmpty ? place.address : place.name,
            latitude: place.lat,
            longitude: place.lng,
          );
      if (!mounted) return;
      setState(() => _savedPlaceKeys.add(_placeKey(place)));
      _loadSavedAddresses();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('address_saved_snackbar', locale)), backgroundColor: AppTheme.successColor),
      );
    } catch (_) {}
  }

  // Har ikkala chegarani ham InputBorder.none qilib qo'yish shart —
  // aks holda global tema (AppTheme)dagi focusedBorder ustunlik qilib,
  // bosilganda chiziq chiqib qoladi.
  InputDecoration _fieldDecoration({
    required String hint,
    required Color hintColor,
    required Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor),
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      suffixIcon: suffixIcon,
    );
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
    final savedAddresses =
        ref.watch(clientSavedAddressesCacheProvider).valueOrNull ?? const <Map<String, dynamic>>[];

    final showFrom = _fromFocused && (_fromResults.isNotEmpty || _fromSearching);
    final showTo = _toFocused && (_toResults.isNotEmpty || _toSearching);
    final results = showFrom ? _fromResults : _toResults;
    final searching = showFrom ? _fromSearching : _toSearching;
    final isFromActive = showFrom;

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
                    AppStrings.get('select_address_title', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ],
              ),
            ),

            // Inputlar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Column(children: [
                  // Qayerdan
                  Row(children: [
                    Padding(padding: const EdgeInsets.only(left: 12),
                      child: Container(width: 24, height: 24,
                        decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.local_shipping, size: 12, color: AppTheme.primaryColor)),
                    ),
                    Expanded(child: TextField(
                      controller: _fromCtrl,
                      focusNode: _fromFocus,
                      onChanged: _onFromChanged,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: _fieldDecoration(
                        hint: AppStrings.get('from_question', locale),
                        hintColor: textSecondary,
                        suffixIcon: _fromCtrl.text.isNotEmpty
                            ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                onPressed: () { _fromCtrl.clear(); setState(() { _fromPlace = null; _fromResults = []; }); })
                            : null,
                      ),
                    )),
                    _MapBtn(label: AppStrings.get('map_btn_label', locale), onTap: () => _openPicker(true)),
                  ]),
                  Divider(height: 1, color: border),
                  // Qayerga
                  Row(children: [
                    Padding(padding: const EdgeInsets.only(left: 12),
                      child: Container(width: 24, height: 24,
                        decoration: BoxDecoration(color: AppTheme.errorColor.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.location_on, size: 12, color: AppTheme.errorColor)),
                    ),
                    Expanded(child: TextField(
                      controller: _toCtrl,
                      focusNode: _toFocus,
                      onChanged: _onToChanged,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: _fieldDecoration(
                        hint: AppStrings.get('to_question', locale),
                        hintColor: textSecondary,
                        suffixIcon: _toCtrl.text.isNotEmpty
                            ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                onPressed: () { _toCtrl.clear(); setState(() { _toPlace = null; _toResults = []; }); })
                            : null,
                      ),
                    )),
                    _MapBtn(label: AppStrings.get('map_btn_label', locale), onTap: () => _openPicker(false)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 8),

            // Saqlangan manzillar — tezkor kirish uchun qisqa ro'yxat,
            // to'liq boshqaruv esa alohida SavedAddressesScreen'da
            if (savedAddresses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.get('saved_places', locale),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.4)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: savedAddresses.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          final item = savedAddresses[i];
                          final label = (item['name'] as String?)?.isNotEmpty == true
                              ? item['name'] as String
                              : (item['address'] as String? ?? '');
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              final place = Place(
                                name: item['name'] as String? ?? '',
                                address: item['address'] as String? ?? '',
                                lat: (item['latitude'] as num).toDouble(),
                                lng: (item['longitude'] as num).toDouble(),
                              );
                              _selectResult(place, isFrom: _fromFocus.hasFocus);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.bookmark, size: 14, color: AppTheme.primaryColor),
                                const SizedBox(width: 6),
                                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

            // Qidiruv natijalari
            if (showFrom || showTo)
              Expanded(
                child: searching
                    ? const Center(child: AppLoadingIndicator(strokeWidth: 2))
                    : results.isEmpty
                        ? Center(child: Text(AppStrings.get('no_results_found', locale), style: TextStyle(color: textSecondary)))
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: results.length,
                            itemBuilder: (ctx, i) {
                              final place = results[i];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _selectResult(place, isFrom: isFromActive),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: border, width: 0.5)),
                                    ),
                                    child: Row(children: [
                                      Container(width: 32, height: 32,
                                        decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.primaryColor)),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(place.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (place.address.isNotEmpty && place.address != place.name)
                                            Text(place.address, style: TextStyle(fontSize: 11, color: textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      )),
                                      if (place.distanceKm != null)
                                        Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            place.distanceKm! < 1
                                                ? '${(place.distanceKm! * 1000).round()} m'
                                                : '${place.distanceKm!.toStringAsFixed(1)} km',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          _savedPlaceKeys.contains(_placeKey(place)) ? Icons.bookmark : Icons.bookmark_border,
                                          size: 18,
                                          color: AppTheme.primaryColor,
                                        ),
                                        onPressed: () => _showQuickSaveDialog(place),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
              )
            else
              const Spacer(),

            // Pastki tugmalar — "Bekor qilish" doim ko'rinadi (Home'ga
            // to'g'ridan-to'g'ri qaytaradi, hech narsa saqlanmasdan),
            // "Manzil tasdiqlash" faqat ikkala manzil to'ldirilganda
            // ko'rinadi.
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: surface,
                border: Border(top: BorderSide(color: border)),
              ),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: border),
                      foregroundColor: textSecondary,
                    ),
                    child: Text(AppStrings.get('cancel_selection', locale),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                if (_allFilled) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _GradBtn(
                      label: AppStrings.get('confirm_address_btn', locale),
                      onTap: () => Navigator.pop(context, {'from': _fromPlace!, 'to': _toPlace!}),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MapBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.map_outlined, size: 12, color: AppTheme.primaryColor),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _GradBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GradBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity, height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
