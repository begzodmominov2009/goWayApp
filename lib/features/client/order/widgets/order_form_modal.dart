import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geo_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/providers/client_cache_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/animated_clear_button.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/close_circle_button.dart';
import '../../../../shared/widgets/map_address_picker.dart';
import '../../../../shared/widgets/place.dart';

// Barcha ichki modallar (manzil qidiruv, mashina/og'irlik/vaqt tanlash)
// shu BITTA, izchil animatsiya uslubini ishlatadi — driver_profile_screen.dart
// dagi bilan bir xil qiymatlar, Flutter'ning standart (sheetAnimationStyle
// berilmagan holatdagi) animatsiyasiga qaraganda silliqroq his qiladi.
final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

/// Buyurtma yaratish formasi — manzil tanlash (SelectAddressScreen) va
/// buyurtma tafsilotlari (OrderDetailsScreen) BITTA bottom-sheet modalga
/// birlashtirilgan. Ekranning ~85% balandligini egallaydi.
///
/// Natija (Tasdiqlash bosilganda): {'fromPlace': Place, 'toPlace': Place,
/// 'truckType': String, 'weight': double, 'loadType': String ('TOP'|'BACK'),
/// 'cargoType': String?, 'note': String?, 'isScheduled': bool,
/// 'scheduledFor': DateTime?, 'distKm': double?, 'timeMin': int?} — yoki
/// null (modal yopilsa).
Future<Map<String, dynamic>?> showOrderFormModal(
  BuildContext context, {
  Place? initialFrom,
  Place? initialTo,
  required double fromLat,
  required double fromLng,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    sheetAnimationStyle: _kSheetAnimationStyle,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _OrderFormModal(
        initialFrom: initialFrom,
        initialTo: initialTo,
        fromLat: fromLat,
        fromLng: fromLng,
      ),
    ),
  );
}

class _OrderFormModal extends ConsumerStatefulWidget {
  final Place? initialFrom;
  final Place? initialTo;
  final double fromLat;
  final double fromLng;

  const _OrderFormModal({
    required this.initialFrom,
    required this.initialTo,
    required this.fromLat,
    required this.fromLng,
  });

  @override
  ConsumerState<_OrderFormModal> createState() => _OrderFormModalState();
}

class _OrderFormModalState extends ConsumerState<_OrderFormModal> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  final _cargoTypeCtrl = TextEditingController();
  final _cargoTypeFocus = FocusNode();
  final _noteCtrl = TextEditingController();
  final _noteFocus = FocusNode();

  // Modal tepasidan chiqadigan ogohlantirish banneri (SnackBar o'rniga —
  // SnackBar ScaffoldMessenger orqali pastki Scaffold'ga bog'lanadi va
  // shu bottom-sheet modal ORQASIDA (past z-tartibda) chiqib, foydalanuvchi
  // uni UMUMAN ko'rmaydi). _lastTopWarningText chiqish (fade-out)
  // animatsiyasi davomida ham matn ko'rinib turishi uchun _topWarning
  // null bo'lgandan keyin ham saqlanadi.
  String? _topWarning;
  String _lastTopWarningText = '';
  Color _topWarningColor = AppTheme.errorColor;
  Timer? _topWarningTimer;

  Place? _fromPlace;
  Place? _toPlace;

  // Manzil qidiruv modali yoki xarita orqali oxirgi marta qaysi maydon
  // ("Qayerdan" yoki "Qayerga") bilan ishlangani — saqlangan manzil
  // chipi bosilganda shu maydon to'ldiriladi (select_address_screen.dart
  // dagi _fromFocus.hasFocus mantig'iga o'xshab, lekin bu yerda inputlar
  // readOnly bo'lgani sabab fokus o'rniga shu bayroq ishlatiladi).
  bool _lastTappedIsFrom = false;

  double? _currentDistKm;
  int? _currentTimeMin;
  bool _routeLoading = false;

  // /check-point orqali manzil tanlangan zahoti tekshirish — har bir
  // maydon ("Qayerdan"/"Qayerga") mustaqil. _fromCheckGen/_toCheckGen —
  // foydalanuvchi tez-tez manzil o'zgartirsa, eskirgan javob e'tiborsiz
  // qoldirilishi uchun (faqat oxirgi so'rov gen'i joriy bo'lsa natija
  // qo'llaniladi).
  bool _fromChecking = false;
  bool _toChecking = false;
  int _fromCheckGen = 0;
  int _toCheckGen = 0;

  String? _selectedTruck;
  double? _selectedWeight;
  String? _selectedLoadType;
  bool _isScheduled = false;
  bool _isTomorrow = false;
  int? _selectedHour;
  int? _selectedMinute;
  final String _priority = 'STANDARD';
  double? _calculatedPrice;
  bool _priceLoading = false;
  Timer? _priceDebounce;

  List<Map<String, dynamic>> get _trucks =>
      ref.read(clientTrucksCacheProvider).valueOrNull ?? const [];

  @override
  void initState() {
    super.initState();
    _fromPlace = widget.initialFrom;
    _toPlace = widget.initialTo;
    _fromCtrl = TextEditingController(text: widget.initialFrom?.name ?? '');
    _toCtrl = TextEditingController(text: widget.initialTo?.name ?? '');
    ref.read(clientSavedAddressesCacheProvider.notifier).refreshIfStale();
    ref.read(clientTrucksCacheProvider.notifier).refreshIfStale();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadTruckImages());
    if (_fromPlace != null && _toPlace != null) {
      _recalculateRoute();
    }
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _cargoTypeCtrl.dispose();
    _cargoTypeFocus.dispose();
    _noteCtrl.dispose();
    _noteFocus.dispose();
    _priceDebounce?.cancel();
    _topWarningTimer?.cancel();
    super.dispose();
  }

  Future<void> _preloadTruckImages() async {
    for (final t in _uniqueTrucks) {
      final url = t['imageUrl'] as String?;
      if (url != null && url.isNotEmpty && mounted) {
        precacheImage(NetworkImage(url), context).catchError((_) {});
      }
    }
  }

  void _setPlace(Place place, {required bool isFrom}) {
    setState(() {
      if (isFrom) {
        _fromPlace = place;
        _fromCtrl.text = place.name;
      } else {
        _toPlace = place;
        _toCtrl.text = place.name;
      }
      _calculatedPrice = null;
    });
    _recalculateRoute();
    _checkPoint(isFrom: isFrom);
  }

  // Manzil tanlangan har bir yo'ldan (qidiruv, xarita, saqlangan manzil,
  // qidiruv tarixi) o'tadigan YAGONA nuqta — _setPlace() barchasi uchun
  // umumiy chaqiruvchi, shuning uchun shu yerga qo'shish barcha yo'llarni
  // avtomatik qamrab oladi.
  Future<void> _checkPoint({required bool isFrom}) async {
    final place = isFrom ? _fromPlace : _toPlace;
    if (place == null) return;
    final myGen = isFrom ? ++_fromCheckGen : ++_toCheckGen;
    setState(() {
      if (isFrom) {
        _fromChecking = true;
      } else {
        _toChecking = true;
      }
    });
    final result = await ref.read(geoRepositoryProvider).checkPoint(
          latitude: place.lat, longitude: place.lng, name: place.name,
        );
    if (!mounted) return;
    final isStale = isFrom ? myGen != _fromCheckGen : myGen != _toCheckGen;
    if (isStale) return;
    setState(() {
      if (isFrom) {
        _fromChecking = false;
      } else {
        _toChecking = false;
      }
    });
    // Tarmoq xatosida (result == null) oqim to'xtamaydi — buyurtma
    // yaratishdagi mavjud tekshiruv (backendReasonKey) baribir ushlab qoladi.
    if (result == null || result.active) return;
    _showRegionWarningSheet(result, isFrom: isFrom);
  }

  Future<void> _showRegionWarningSheet(CheckPointResult result, {required bool isFrom}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _RegionWarningSheet(
        reasonKey: result.reasonKey,
        regionName: result.regionName,
        isFrom: isFrom,
        onViewRegions: () {
          Navigator.pop(ctx);
          _showRegionsListSheet();
        },
      ),
    );
  }

  // Sarlavhalar yonidagi "?" bosilganda ochiladigan yordam tushuntirish
  // modali — mavjud bottom-sheet uslubiga mos (drag tutqich +
  // CloseCircleButton, radius 24). SnackBar EMAS — bu forma modali ham
  // o'zining Scaffold'iga ega emas, shuning uchun SnackBar shu modal
  // ORQASIDA chiqib ko'rinmay qolar edi.
  Future<void> _showHelpSheet({required String title, required List<_InfoSection> sections}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _HelpInfoSheet(title: title, sections: sections),
    );
  }

  Future<void> _showRegionsListSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => const _RegionsListSheet(),
    );
  }

  void _clearPlace(bool isFrom) {
    setState(() {
      if (isFrom) {
        _fromCtrl.clear();
        _fromPlace = null;
      } else {
        _toCtrl.clear();
        _toPlace = null;
      }
    });
    _recalculateRoute();
  }

  Future<void> _recalculateRoute() async {
    if (_fromPlace == null || _toPlace == null) {
      setState(() {
        _currentDistKm = null;
        _currentTimeMin = null;
        _calculatedPrice = null;
      });
      return;
    }
    setState(() => _routeLoading = true);
    final repo = ref.read(geocodeRepositoryProvider);
    final route = await repo.getRoute(
      fromLat: _fromPlace!.lat, fromLng: _fromPlace!.lng,
      toLat: _toPlace!.lat, toLng: _toPlace!.lng,
    );
    if (!mounted) return;
    setState(() {
      _currentDistKm = route?.distanceKm;
      _currentTimeMin = route?.durationMin;
      _routeLoading = false;
    });
    _recalculatePrice();
  }

  void _recalculatePrice() {
    _priceDebounce?.cancel();
    if (_selectedTruck == null || _selectedWeight == null || _currentDistKm == null) return;
    _priceDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _priceLoading = true);
      final price = await ref.read(clientRepositoryProvider).calculatePrice(
        truckType: _selectedTruck!, distance: _currentDistKm!,
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

  Future<void> _openMapPicker(bool isFrom) async {
    _lastTappedIsFrom = isFrom;
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
    _setPlace(result, isFrom: isFrom);
  }

  Future<void> _openSearchModal(bool isFrom) async {
    _lastTappedIsFrom = isFrom;
    final result = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _AddressSearchModal(
        isFrom: isFrom, biasLat: widget.fromLat, biasLng: widget.fromLng,
      ),
    );
    if (result == null) return;
    _setPlace(result, isFrom: isFrom);
  }

  Future<void> _showTruckPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _TruckPickerSheet(
        trucks: _uniqueTrucks, initialType: _selectedTruck,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedTruck = result;
        _selectedWeight = null;
        _calculatedPrice = null;
      });
      _recalculatePrice();
    }
  }

  Future<void> _showWeightPicker() async {
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _WeightPickerSheet(options: _weightOptions, initial: _selectedWeight),
    );
    if (result != null) {
      setState(() => _selectedWeight = result);
      _recalculatePrice();
    }
  }

  Future<void> _showTimePicker() async {
    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _TimePickerSheet(initialHour: _selectedHour, initialMinute: _selectedMinute),
    );
    if (result != null) {
      setState(() {
        _selectedHour = result['hour'];
        _selectedMinute = result['minute'];
      });
    }
  }

  // Modal TEPASIDAN chiqadigan ogohlantirish — SnackBar EMAS. Bu bottom
  // sheet o'zining Scaffold'i yo'q, shuning uchun ScaffoldMessenger orqali
  // chiqarilgan SnackBar pastdagi ekranning Scaffold'iga bog'lanadi va shu
  // modal ORQASIDA (past z-tartibda) chiqib, foydalanuvchi uni umuman
  // ko'rmaydi (masalan "vaqt 1 soatdan kam" xatosi shu sabab ko'rinmasdi).
  void _showTopBanner(String message, {Color color = AppTheme.errorColor}) {
    _topWarningTimer?.cancel();
    setState(() {
      _topWarning = message;
      _lastTopWarningText = message;
      _topWarningColor = color;
    });
    _topWarningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _topWarning = null);
    });
  }

  void _showValidationError(String message) => _showTopBanner(message, color: AppTheme.errorColor);

  void _submit() {
    final locale = ref.read(localeProvider).languageCode;
    if (_fromPlace == null || _toPlace == null) {
      _showValidationError(AppStrings.get('enter_address', locale));
      return;
    }
    if (_selectedTruck == null) {
      _showValidationError(AppStrings.get('select_truck_error', locale));
      return;
    }
    if (_selectedWeight == null) {
      _showValidationError(AppStrings.get('enter_weight_error', locale));
      return;
    }
    if (_cargoTypeCtrl.text.trim().isEmpty) {
      _showValidationError(AppStrings.get('enter_cargo_type_error', locale));
      return;
    }
    if (_selectedLoadType == null) {
      _showValidationError(AppStrings.get('select_load_type_error', locale));
      return;
    }
    if (_isScheduled && (_selectedHour == null || _selectedMinute == null)) {
      _showValidationError(AppStrings.get('select_time_error', locale));
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
        _showValidationError(AppStrings.get('order_type_min_time_error', locale));
        return;
      }
    }

    Navigator.pop(context, {
      'fromPlace': _fromPlace,
      'toPlace': _toPlace,
      'truckType': _selectedTruck,
      'weight': _selectedWeight,
      'loadType': _selectedLoadType,
      'cargoType': _cargoTypeCtrl.text.trim().isEmpty ? null : _cargoTypeCtrl.text.trim(),
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'isScheduled': _isScheduled,
      'scheduledFor': scheduledFor,
      'distKm': _currentDistKm,
      'timeMin': _currentTimeMin,
    });
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
    final count = (capacity / 0.1).round();
    return List.generate(count, (i) {
      final raw = (i + 1) * 0.1;
      return (raw * 10).round() / 10; // floating-point xatosini oldini olish
    });
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
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final savedAddresses =
        ref.watch(clientSavedAddressesCacheProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final trucksAsync = ref.watch(clientTrucksCacheProvider);
    final trucksLoading = trucksAsync.isLoading && !trucksAsync.hasValue;
    final selectedTruckData = _selectedTruck != null
        ? _uniqueTrucks.firstWhere((t) => t['type'] == _selectedTruck, orElse: () => {})
        : null;

    // Klaviatura chiqqanda butun modal shu qadar yuqoriga suriladi — shu
    // orqali ichkaridagi Expanded(SingleChildScrollView) uchun mavjud
    // balandlik haqiqatan qisqaradi va TextField'ning standart "fokusda
    // ko'rinadigan joyga o'zi scroll qilish" xulq-atvori to'g'ri ishlaydi
    // (_AddressSearchModal'da ham xuddi shu naqsh ishlatilgan).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Tortish tutqichi + yopish tugmasi.
            // MUHIM: Stack o'lchamsiz qoldirilsa, faqat pozitsiyalanmagan
            // farzandiga (tortish tutqichi, ~14px balandlik) qarab
            // kichrayib qoladi — natijada Positioned yopish tugmasi
            // Stack chegarasidan tashqarida qolib, Clip.hardEdge tufayli
            // deyarli butunlay kesilib ko'rinmay qoladi (ham balandlikda,
            // ham eni Stack kengligiga bog'liq bo'lgani uchun gorizontal
            // joylashuvda ham). SizedBox bilan aniq o'lcham berish shart.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(width: 36, height: 4,
                        decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
                  ),
                  Positioned(
                    right: 12, top: 8,
                    child: CloseCircleButton(
                      bg: tabBg, iconColor: textSecondary,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),

            // Qolgan barcha mazmun — BITTA yagona scroll oqimida. Avval
            // manzil inputlari va saqlangan manzillar alohida, "qotib
            // turuvchi" bo'lak sifatida chiqarilgan edi — scroll qilinganda
            // ular joyida qolib, faqat pastki qism surilardi. Endi hammasi
            // shu bitta SingleChildScrollView ichida, birga suriladi.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: Column(
                  children: [
                    // Manzil inputlari
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
                              readOnly: true,
                              onTap: () => _openSearchModal(true),
                              style: TextStyle(fontSize: 13, color: textPrimary),
                              decoration: _fieldDecoration(
                                hint: AppStrings.get('from_question', locale),
                                hintColor: textSecondary,
                                suffixIcon: _fromChecking
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: SizedBox(width: 14, height: 14, child: AppLoadingIndicator(strokeWidth: 2)),
                                      )
                                    : (_fromCtrl.text.isNotEmpty
                                        ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                            onPressed: () => _clearPlace(true))
                                        : null),
                              ),
                            )),
                            _MapBtn(label: AppStrings.get('map_btn_label', locale), onTap: () => _openMapPicker(true)),
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
                              readOnly: true,
                              onTap: () => _openSearchModal(false),
                              style: TextStyle(fontSize: 13, color: textPrimary),
                              decoration: _fieldDecoration(
                                hint: AppStrings.get('to_question', locale),
                                hintColor: textSecondary,
                                suffixIcon: _toChecking
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: SizedBox(width: 14, height: 14, child: AppLoadingIndicator(strokeWidth: 2)),
                                      )
                                    : (_toCtrl.text.isNotEmpty
                                        ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                            onPressed: () => _clearPlace(false))
                                        : null),
                              ),
                            )),
                            _MapBtn(label: AppStrings.get('map_btn_label', locale), onTap: () => _openMapPicker(false)),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Saqlangan manzillar — tezkor kirish uchun qisqa ro'yxat
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
                                      _setPlace(place, isFrom: _lastTappedIsFrom);
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

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _routeLoading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: SizedBox(width: 20, height: 20, child: AppLoadingIndicator(strokeWidth: 2)),
                                  ),
                                )
                              : (_currentDistKm != null
                                  ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: tabBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        const Icon(Icons.route, size: 16, color: AppTheme.primaryColor),
                                        const SizedBox(width: 7),
                                        Text('${_currentDistKm!.toStringAsFixed(1)} km',
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                                        if (_currentTimeMin != null) ...[
                                          Container(margin: const EdgeInsets.symmetric(horizontal: 10), width: 1, height: 14, color: textSecondary.withOpacity(0.3)),
                                          Icon(Icons.access_time, size: 14, color: textSecondary),
                                          const SizedBox(width: 5),
                                          Text(
                                            _currentTimeMin! >= 60
                                                ? '${_currentTimeMin! ~/ 60}${AppStrings.get('route_time_hour', locale)} ${_currentTimeMin! % 60}${AppStrings.get('route_time_min', locale)}'
                                                : '$_currentTimeMin ${AppStrings.get('route_time_min', locale)}',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
                                          ),
                                        ],
                                      ]),
                                    )
                                  : const SizedBox.shrink()),
                          if (!_routeLoading && _currentDistKm != null) ...[
                            const SizedBox(height: 6),
                            Text(AppStrings.get('auto_calculated_hint', locale),
                                style: TextStyle(fontSize: 11, color: textSecondary)),
                            const SizedBox(height: 14),
                          ],

                          Row(children: [
                            Text(AppStrings.get('select_vehicle', locale),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.help_outline, size: 16, color: textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showHelpSheet(
                                title: AppStrings.get('select_vehicle', locale),
                                sections: [_InfoSection(body: AppStrings.get('vehicle_help_full', locale))],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),

                          trucksLoading
                              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: AppLoadingIndicator()))
                              : GestureDetector(
                                  onTap: _showTruckPicker,
                                  child: Container(
                                    width: double.infinity,
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: border),
                                    ),
                                    child: Row(
                                      children: [
                                        if (selectedTruckData != null) ...[
                                          _TruckThumbnail(
                                            imageUrl: selectedTruckData['imageUrl'] as String?,
                                            size: 32, radius: 10,
                                            bg: bg, iconColor: textSecondary,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              selectedTruckData['name'] as String? ?? _selectedTruck!,
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ] else
                                          Expanded(
                                            child: Text(
                                              AppStrings.get('select_vehicle_hint', locale),
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textSecondary),
                                            ),
                                          ),
                                        Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: textSecondary),
                                      ],
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 16),

                          Row(children: [
                            Text(AppStrings.get('weight_tons', locale),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.help_outline, size: 16, color: textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showHelpSheet(
                                title: AppStrings.get('weight_tons', locale),
                                sections: [_InfoSection(body: AppStrings.get('weight_help_full', locale))],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Opacity(
                            opacity: _selectedTruck == null ? 0.6 : 1.0,
                            child: GestureDetector(
                              onTap: () {
                                if (_selectedTruck == null) {
                                  _showTopBanner(
                                    AppStrings.get('select_truck_first_warning', locale),
                                    color: AppTheme.warningColor,
                                  );
                                  return;
                                }
                                _showWeightPicker();
                              },
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: border),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _selectedWeight != null
                                          ? '${_selectedWeight!.toStringAsFixed(1)} t'
                                          : AppStrings.get('select_weight_hint', locale),
                                      style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: _selectedWeight != null ? textPrimary : textSecondary,
                                      ),
                                    ),
                                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: textSecondary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text(AppStrings.get('cargo_type_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _cargoTypeCtrl,
                                  focusNode: _cargoTypeFocus,
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 13, color: textPrimary),
                                  decoration: InputDecoration(hintText: AppStrings.get('cargo_type_hint', locale), hintStyle: TextStyle(color: textSecondary)),
                                ),
                              ),
                              AnimatedClearButton(controller: _cargoTypeCtrl, focusNode: _cargoTypeFocus),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(children: [
                            Text(AppStrings.get('load_type_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.help_outline, size: 16, color: textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showHelpSheet(
                                title: AppStrings.get('load_type_label', locale),
                                sections: [_InfoSection(body: AppStrings.get('load_type_help_full', locale))],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: _TimeTab(
                                label: AppStrings.get('load_from_top', locale),
                                selected: _selectedLoadType == 'TOP',
                                bg: tabBg, textPrimary: textPrimary,
                                onTap: () => setState(() => _selectedLoadType = 'TOP'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TimeTab(
                                label: AppStrings.get('load_from_back', locale),
                                selected: _selectedLoadType == 'BACK',
                                bg: tabBg, textPrimary: textPrimary,
                                onTap: () => setState(() => _selectedLoadType = 'BACK'),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 16),

                          Row(children: [
                            Text(AppStrings.get('order_when_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.help_outline, size: 16, color: textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showHelpSheet(
                                title: AppStrings.get('order_when_label', locale),
                                sections: [
                                  _InfoSection(subtitle: AppStrings.get('order_type_now', locale), body: AppStrings.get('time_help_now', locale)),
                                  _InfoSection(subtitle: AppStrings.get('order_type_today', locale), body: AppStrings.get('time_help_today', locale)),
                                  _InfoSection(subtitle: AppStrings.get('order_type_tomorrow', locale), body: AppStrings.get('time_help_tomorrow', locale)),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
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
                            GestureDetector(
                              onTap: _showTimePicker,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: border),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      (_selectedHour != null && _selectedMinute != null)
                                          ? '${_selectedHour!.toString().padLeft(2, '0')}:${_selectedMinute!.toString().padLeft(2, '0')}'
                                          : AppStrings.get('select_time_hint', locale),
                                      style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: (_selectedHour != null && _selectedMinute != null) ? textPrimary : textSecondary,
                                      ),
                                    ),
                                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: textSecondary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _noteCtrl,
                                  focusNode: _noteFocus,
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 13, color: textPrimary),
                                  decoration: InputDecoration(hintText: AppStrings.get('note_optional', locale), hintStyle: TextStyle(color: textSecondary)),
                                ),
                              ),
                              AnimatedClearButton(controller: _noteCtrl, focusNode: _noteFocus),
                            ],
                          ),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Doimiy "Tasdiqlash" tugmasi — barcha MAJBURIY maydonlar
            // to'ldirilmaguncha o'chiq turadi (Izoh MAJBURIY EMAS, shu
            // sabab shartga kirmaydi). _cargoTypeCtrl.text faqat
            // TextEditingController orqali o'zgaradi (setState
            // chaqirmaydi), shuning uchun uni ValueListenableBuilder bilan
            // tinglaymiz — shunda har harf kiritilganda FAQAT shu tugma
            // qayta quriladi, butun modal emas (ortiqcha rebuild yo'q).
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: surface,
                border: Border(top: BorderSide(color: border)),
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _cargoTypeCtrl,
                builder: (context, cargoValue, _) {
                  final canSubmit = _fromPlace != null &&
                      _toPlace != null &&
                      _selectedTruck != null &&
                      _selectedWeight != null &&
                      cargoValue.text.trim().isNotEmpty &&
                      _selectedLoadType != null &&
                      (!_isScheduled || (_selectedHour != null && _selectedMinute != null));
                  return _GradBtn(
                    label: AppStrings.get('place_order', locale),
                    onTap: canSubmit ? _submit : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
          ),
          // Modal tepasidan chiqadigan ogohlantirish banneri — Positioned
          // orqali kontent ustiga (overlay) qo'yiladi, shu bilan pastdagi
          // Column/ScrollView o'lchami o'zgarmaydi (layout sakramaydi).
          // Yopish tugmasi (CloseCircleButton) bilan to'qnashmasligi uchun
          // sarlavha qatoridan (48px) pastroqda joylashgan.
          Positioned(
            top: 56, left: 16, right: 16,
            child: IgnorePointer(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                offset: _topWarning != null ? Offset.zero : const Offset(0, -0.3),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  opacity: _topWarning != null ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _topWarningColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_lastTopWarningText,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manzil qidiruv ichki modali — asosiy formadagi "Qayerdan"/"Qayerga"
/// inputlaridan biri bosilganda pastdan chiqadi (asosiy modal ustida).
/// Faqat BITTA maydon uchun ishlaydi (isFrom orqali biladi), natijani
/// Navigator.pop(context, selectedPlace) orqali qaytaradi.
class _AddressSearchModal extends ConsumerStatefulWidget {
  final bool isFrom;
  final double biasLat;
  final double biasLng;

  const _AddressSearchModal({
    required this.isFrom, required this.biasLat, required this.biasLng,
  });

  @override
  ConsumerState<_AddressSearchModal> createState() => _AddressSearchModalState();
}

class _AddressSearchModalState extends ConsumerState<_AddressSearchModal> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<Place> _results = [];
  bool _searching = false;
  Timer? _debounce;
  final Set<String> _savedPlaceKeys = {};

  // Qidiruv tarixi (GET /address-history) — modal ochilganda bir marta
  // yuklanadi, input bo'sh bo'lganda "Saqlangan manzillar" bilan birga
  // ko'rsatiladi.
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    // Klaviatura darhol (autofocus bilan) chiqsa, sheet hali sirg'alib
    // kirayotgan animatsiya bilan to'qnashib, "sakrash"ga o'xshab ko'rinardi
    // — shuning uchun fokus so'rovi sheet ochilish animatsiyasi tugagunicha
    // kechiktiriladi.
    Future.delayed(_kSheetAnimationStyle.duration ?? const Duration(milliseconds: 350), () {
      if (mounted) FocusScope.of(context).requestFocus(_focus);
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _placeKey(Place p) => '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}';

  Future<void> _loadHistory() async {
    try {
      final history = await ref.read(clientRepositoryProvider).getAddressHistory();
      if (!mounted) return;
      setState(() => _history = history);
    } catch (_) {}
  }

  // Har bir tugma bosilganda setState chaqirilaversa (qiymat allaqachon
  // bir xil bo'lsa ham), butun modal daraxti har bir belgi kiritilganda
  // qayta qurilib, yozishda sezilarli "lag" beradi. Shuning uchun faqat
  // haqiqatan o'zgarganda setState chaqiriladi.
  void _onChanged(String val) {
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      if (_results.isNotEmpty || _searching) {
        setState(() { _results = []; _searching = false; });
      }
      return;
    }
    if (!_searching) setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () => _performSearch(val));
  }

  Future<void> _performSearch(String val) async {
    if (val.trim().isEmpty) return;
    _debounce?.cancel();
    if (!_searching) setState(() => _searching = true);
    final repo = ref.read(geocodeRepositoryProvider);
    final results = await repo.search(val, lat: widget.biasLat, lng: widget.biasLng);
    if (!mounted) return;
    setState(() {
      _results = results
          .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
          .toList();
      _searching = false;
    });
  }

  // Qidiruv natijasi, saqlangan manzil yoki tarixdan tanlanganda —
  // fon rejimida qidiruv tarixiga yoziladi (xato bo'lsa jimgina
  // e'tiborsiz qoldiriladi) va modal shu manzil bilan yopiladi.
  void _selectPlace(Place place) {
    unawaited(
      ref.read(clientRepositoryProvider).addAddressHistory(
            address: place.address.isNotEmpty ? place.address : place.name,
            latitude: place.lat,
            longitude: place.lng,
          ).catchError((_) {}),
    );
    Navigator.pop(context, place);
  }

  Future<void> _openMapPicker() async {
    final locale = ref.read(localeProvider).languageCode;
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapAddressPicker(
          initialLat: widget.biasLat,
          initialLng: widget.biasLng,
          title: widget.isFrom ? AppStrings.get('from_question', locale) : AppStrings.get('to_question', locale),
          isFrom: widget.isFrom,
        ),
      ),
    );
    if (result == null || !mounted) return;
    Navigator.pop(context, result);
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
      ref.read(clientSavedAddressesCacheProvider.notifier).forceRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('address_saved_snackbar', locale)), backgroundColor: AppTheme.successColor),
      );
    } catch (_) {}
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
    final savedAddresses =
        ref.watch(clientSavedAddressesCacheProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final hasQuery = _ctrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(width: 36, height: 4,
                            decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
                      ),
                      Positioned(
                        right: 12, top: 8,
                        child: CloseCircleButton(
                          bg: tabBg, iconColor: textSecondary,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(children: [
                    Icon(widget.isFrom ? Icons.local_shipping : Icons.location_on, size: 16,
                        color: widget.isFrom ? AppTheme.primaryColor : AppTheme.errorColor),
                    const SizedBox(width: 8),
                    Text(
                      widget.isFrom ? AppStrings.get('from_question', locale) : AppStrings.get('to_question', locale),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border),
                          ),
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            onChanged: _onChanged,
                            style: TextStyle(fontSize: 14, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: AppStrings.get('search_address_hint', locale),
                              hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.map_outlined, size: 18, color: AppTheme.primaryColor),
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                onPressed: _openMapPicker,
                              ),
                              // Standart 48x48 minimal maydonni bekor qiladi —
                              // aks holda 44px balandlikdagi konteynerdan
                              // chiqib ketishi mumkin edi.
                              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                            ),
                          ),
                        ),
                      ),
                      // X tugmasi — client_scheduled_orders_screen.dart dagi
                      // bilan bir xil naqsh: inputning suffixIcon'i EMAS,
                      // uning YONIDA (tashqarisida), Row'da alohida element
                      // sifatida. Shu bilan input o'zi Expanded orqali fokus
                      // olganda silliq qisqarib, X yonidan sirg'alib chiqadi
                      // — 44px balandlikdagi input ichiga zich sig'dirishga
                      // urinish (avval suffixIcon ichida edi) yo'q.
                      AnimatedClearButton(
                        controller: _ctrl,
                        focusNode: _focus,
                        onCleared: () => setState(() => _results = []),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: !hasQuery
                      ? _buildSuggestions(savedAddresses, textPrimary, textSecondary, border, locale)
                      : (_searching
                          ? const Center(child: AppLoadingIndicator(strokeWidth: 2))
                          : (_results.isEmpty
                              ? Center(child: Text(AppStrings.get('no_results_found', locale), style: TextStyle(color: textSecondary)))
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: _results.length,
                                  itemBuilder: (ctx, i) {
                                    final place = _results[i];
                                    return _AddressResultTile(
                                      place: place,
                                      icon: Icons.location_on_outlined,
                                      iconColor: AppTheme.primaryColor,
                                      textPrimary: textPrimary, textSecondary: textSecondary, border: border,
                                      onTap: () => _selectPlace(place),
                                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
                                    );
                                  },
                                ))),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border(top: BorderSide(color: border)),
                  ),
                  child: hasQuery
                      ? _GradBtn(
                          label: AppStrings.get('search_btn', locale),
                          onTap: () => _performSearch(_ctrl.text),
                        )
                      : OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: border),
                            foregroundColor: textSecondary,
                          ),
                          child: Text(AppStrings.get('close', locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // "Saqlangan manzillar" va "Qidiruv tarixi" — ikkalasi ham aniq
  // sarlavha bilan, faqat mos ro'yxat bo'sh bo'lmaganda ko'rsatiladi.
  Widget _buildSuggestions(
    List<Map<String, dynamic>> savedAddresses,
    Color textPrimary, Color textSecondary, Color border,
    String locale,
  ) {
    if (savedAddresses.isEmpty && _history.isEmpty) return const SizedBox.shrink();

    Place savedToPlace(Map<String, dynamic> item) => Place(
          name: item['name'] as String? ?? '',
          address: item['address'] as String? ?? '',
          lat: (item['latitude'] as num).toDouble(),
          lng: (item['longitude'] as num).toDouble(),
        );
    Place historyToPlace(Map<String, dynamic> item) => Place(
          name: item['address'] as String? ?? '',
          address: '',
          lat: (item['latitude'] as num).toDouble(),
          lng: (item['longitude'] as num).toDouble(),
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (savedAddresses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(AppStrings.get('saved_places', locale),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.4)),
          ),
          ...savedAddresses.map((item) => _AddressResultTile(
                place: savedToPlace(item),
                icon: Icons.bookmark,
                iconColor: AppTheme.primaryColor,
                textPrimary: textPrimary, textSecondary: textSecondary, border: border,
                onTap: () => _selectPlace(savedToPlace(item)),
              )),
        ],
        if (savedAddresses.isNotEmpty && _history.isNotEmpty)
          Divider(height: 24, thickness: 1, color: border),
        if (_history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(AppStrings.get('search_history_title', locale),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.4)),
          ),
          ..._history.map((item) => _AddressResultTile(
                place: historyToPlace(item),
                icon: Icons.history,
                iconColor: textSecondary,
                textPrimary: textPrimary, textSecondary: textSecondary, border: border,
                onTap: () => _selectPlace(historyToPlace(item)),
              )),
        ],
      ],
    );
  }
}

/// Manzil qatori — qidiruv natijalari, saqlangan manzillar va qidiruv
/// tarixi bo'limlarida bir xil ko'rinish uchun ishlatiladi.
class _AddressResultTile extends StatelessWidget {
  final Place place;
  final IconData icon;
  final Color iconColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final VoidCallback onTap;
  final Widget? trailing;

  const _AddressResultTile({
    required this.place, required this.icon, required this.iconColor,
    required this.textPrimary, required this.textSecondary, required this.border,
    required this.onTap, this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 0.5)),
          ),
          child: Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: iconColor)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (place.address.isNotEmpty && place.address != place.name)
                  Text(place.address, style: TextStyle(fontSize: 11, color: textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            if (trailing != null) trailing!,
          ]),
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

/// Truck rasmi — agar `imageUrl` bo'lsa tarmoqdan yuklab ko'rsatadi
/// (yuklanmasa yoki bo'lmasa, placeholder ikonkaga tushadi).
class _TruckThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double radius;
  final Color bg;
  final Color iconColor;

  const _TruckThumbnail({
    required this.imageUrl, required this.size, required this.radius,
    required this.bg, required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Icon(Icons.local_shipping, size: size * 0.55, color: iconColor),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        imageUrl!,
        width: size, height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

/// Mashina turini tanlash — ro'yxat-modal (radio + rasm + nom + tavsif).
class _TruckPickerSheet extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> trucks;
  final String? initialType;
  const _TruckPickerSheet({required this.trucks, this.initialType});

  @override
  ConsumerState<_TruckPickerSheet> createState() => _TruckPickerSheetState();
}

class _TruckPickerSheetState extends ConsumerState<_TruckPickerSheet> {
  String? _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.initialType;
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

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(
                  AppStrings.get('select_vehicle', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
                ),
              ),
              CloseCircleButton(
                bg: tabBg, iconColor: textSecondary,
                onTap: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.trucks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final t = widget.trucks[i];
                  final selected = _tempSelected == t['type'];
                  return GestureDetector(
                    onTap: () => setState(() => _tempSelected = t['type'] as String),
                    child: Row(
                      children: [
                        Container(
                          width: 22, height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? AppTheme.primaryColor : Colors.transparent,
                            border: Border.all(color: selected ? AppTheme.primaryColor : border, width: 2),
                          ),
                          child: selected
                              ? Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        _TruckThumbnail(
                          imageUrl: t['imageUrl'] as String?,
                          size: 48, radius: 12,
                          bg: bg, iconColor: textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t['name'] as String? ?? t['type'] as String,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('${t['capacity']} t',
                                  style: TextStyle(fontSize: 12, color: textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        AppStrings.get('cancel', locale),
                        style: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _tempSelected != null ? () => Navigator.pop(context, _tempSelected) : null,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: _tempSelected != null
                          ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight)
                          : null,
                      color: _tempSelected != null ? null : Colors.grey.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        AppStrings.get('select_button', locale),
                        style: TextStyle(color: _tempSelected != null ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Yuk og'irligini tanlash — Cupertino uslubidagi g'ildirak (wheel) picker,
/// pastdan chiquvchi modal ichida.
class _WeightPickerSheet extends ConsumerStatefulWidget {
  final List<double> options;
  final double? initial;
  const _WeightPickerSheet({required this.options, this.initial});

  @override
  ConsumerState<_WeightPickerSheet> createState() => _WeightPickerSheetState();
}

class _WeightPickerSheetState extends ConsumerState<_WeightPickerSheet> {
  late final FixedExtentScrollController _scrollCtrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    final idx = widget.initial != null ? widget.options.indexOf(widget.initial!) : -1;
    _index = idx >= 0 ? idx : 0;
    _scrollCtrl = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  AppStrings.get('weight_tons', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
                ),
              ),
              CloseCircleButton(
                bg: tabBg, iconColor: textSecondary,
                onTap: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: CupertinoPicker(
                itemExtent: 40,
                backgroundColor: Colors.transparent,
                scrollController: _scrollCtrl,
                onSelectedItemChanged: (i) => _index = i,
                children: widget.options
                    .map((w) => Center(
                          child: Text(
                            '${w.toStringAsFixed(1)} t',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.pop(context, widget.options[_index]),
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    AppStrings.get('apply', locale),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vaqt (soat/daqiqa) tanlash — Cupertino uslubidagi g'ildirak (wheel)
/// picker, pastdan chiquvchi modal ichida.
class _TimePickerSheet extends ConsumerStatefulWidget {
  final int? initialHour;
  final int? initialMinute;
  const _TimePickerSheet({this.initialHour, this.initialMinute});

  @override
  ConsumerState<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends ConsumerState<_TimePickerSheet> {
  late final FixedExtentScrollController _hourScrollCtrl;
  late final FixedExtentScrollController _minuteScrollCtrl;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = (widget.initialHour ?? 0).clamp(0, 23);
    _minute = (widget.initialMinute ?? 0).clamp(0, 59);
    _hourScrollCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteScrollCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourScrollCtrl.dispose();
    _minuteScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  AppStrings.get('select_time_hint', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
                ),
              ),
              CloseCircleButton(
                bg: tabBg, iconColor: textSecondary,
                onTap: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      backgroundColor: Colors.transparent,
                      scrollController: _hourScrollCtrl,
                      onSelectedItemChanged: (i) => _hour = i,
                      children: List.generate(
                        24,
                        (i) => Center(
                          child: Text(
                            i.toString().padLeft(2, '0'),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      ':',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: textPrimary),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      backgroundColor: Colors.transparent,
                      scrollController: _minuteScrollCtrl,
                      onSelectedItemChanged: (i) => _minute = i,
                      children: List.generate(
                        60,
                        (i) => Center(
                          child: Text(
                            i.toString().padLeft(2, '0'),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.pop(context, {'hour': _hour, 'minute': _minute}),
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    AppStrings.get('apply', locale),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _HelpInfoSheet uchun bitta bo'lim — [subtitle] berilsa (masalan "Vaqt
/// tanlash" uchun Hozir/Bugun/Ertaga), alohida kichik sarlavha bilan
/// ajratib ko'rsatiladi; berilmasa faqat [body] chiqadi.
class _InfoSection {
  final String? subtitle;
  final String body;
  const _InfoSection({this.subtitle, required this.body});
}

/// Sarlavhalar yonidagi "?" bosilganda chiqadigan yordam tushuntirish
/// modali — loyihadagi boshqa pastdan chiquvchi modallar bilan bir xil
/// uslubda (drag tutqich + CloseCircleButton, radius 24, padding 20/12).
/// Kirish parametrlari (title/sections) chaqiruvchi tomonda AppStrings
/// bilan oldindan hal qilingan matnlar, shuning uchun bu widget'ning
/// o'zi Riverpod/locale'ga bog'liq emas — faqat kerakli qism (shu
/// modalning o'zi) quriladi, boshqa hech narsaga ta'sir qilmaydi.
class _HelpInfoSheet extends StatelessWidget {
  final String title;
  final List<_InfoSection> sections;
  const _HelpInfoSheet({required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
              ),
              CloseCircleButton(bg: tabBg, iconColor: textSecondary, onTap: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 14),
            // Sarlavha qatori (tutqich + title + X) doim tepada qotib
            // turishi uchun Column'ning ODDIY (flex bo'lmagan) farzandi
            // sifatida qoladi; faqat bo'limlar qismi ConstrainedBox +
            // shrinkWrap orqali cheklanadi — _TruckPickerSheet'dagi bilan
            // bir xil naqsh (shu faylda allaqachon ishlatilgan). Natija:
            // qisqa matnda Column shunchaki kichik bo'ladi (shrinkWrap
            // tufayli ortiqcha bo'sh joy qolmaydi), uzun matnda esa
            // maksimal balandlikdan oshib ketmay, o'zi ichida scroll
            // qiladi (ekrandan chiqmaydi).
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final section in sections) ...[
                      if (section.subtitle != null) ...[
                        Text(section.subtitle!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                        const SizedBox(height: 4),
                      ],
                      Text(section.body, style: TextStyle(fontSize: 13, color: textSecondary, height: 1.5)),
                      if (section != sections.last) const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

/// Manzil (bitta nuqta — "Qayerdan" yoki "Qayerga") tanlangan zahoti
/// /check-point orqali tekshirilib, hudud faol bo'lmasa yoki umuman
/// aniqlanmasa ko'rsatiladigan ogohlantirish — boshqa pastdan chiquvchi
/// modallar (masalan _TruckPickerSheet) bilan bir xil uslubda.
class _RegionWarningSheet extends ConsumerWidget {
  final String? reasonKey;
  final String? regionName;
  final bool isFrom;
  final VoidCallback onViewRegions;

  const _RegionWarningSheet({
    required this.reasonKey,
    required this.regionName,
    required this.isFrom,
    required this.onViewRegions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    final isUnresolved = reasonKey == 'location_unresolved';
    final title = isUnresolved
        ? AppStrings.get('location_unresolved_title', locale)
        : AppStrings.get('route_inactive_title', locale);
    final message = isUnresolved
        ? (isFrom
            ? AppStrings.get('location_unresolved_from_message', locale)
            : AppStrings.get('location_unresolved_to_message', locale))
        : AppStrings.get('region_inactive_dialog_message', locale).replaceFirst('{region}', regionName ?? '');

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 36, height: 4,
                      decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
                  Positioned(
                    right: 0, top: 0,
                    child: CloseCircleButton(bg: tabBg, iconColor: textSecondary, onTap: () => Navigator.pop(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AppTheme.warningColor.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(isUnresolved ? Icons.location_off_outlined : Icons.pin_drop_outlined,
                  color: AppTheme.warningColor, size: 30),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewRegions,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: border),
                    foregroundColor: textPrimary,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(AppStrings.get('view_active_regions', locale),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GradBtn(label: AppStrings.get('close', locale), onTap: () => Navigator.pop(context)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Barcha viloyatlar ro'yxati — faqat ko'rish uchun (GET /regions/all,
/// admin bo'lmagan foydalanuvchi ham ochadi). Ko'rinishi
/// region_picker_page.dart dagi ro'yxatga o'xshash, lekin tanlash yo'q —
/// bosilganda hech narsa bo'lmaydi.
class _RegionsListSheet extends ConsumerStatefulWidget {
  const _RegionsListSheet();

  @override
  ConsumerState<_RegionsListSheet> createState() => _RegionsListSheetState();
}

class _RegionsListSheetState extends ConsumerState<_RegionsListSheet> {
  bool _loading = true;
  List<GeoRegion> _regions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(geoRepositoryProvider).getAllRegions();
    list.sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    setState(() {
      _regions = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return FractionallySizedBox(
      heightFactor: 0.75,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(width: 36, height: 4,
                        decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
                    Positioned(
                      right: 0, top: 0,
                      child: CloseCircleButton(bg: tabBg, iconColor: textSecondary, onTap: () => Navigator.pop(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(AppStrings.get('regions_list_title', locale),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: AppLoadingIndicator())
                    : ListView.separated(
                        itemCount: _regions.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: border),
                        itemBuilder: (ctx, i) {
                          final region = _regions[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  region.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                      color: region.isActive ? textPrimary : textSecondary),
                                ),
                              ),
                              if (!region.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(AppStrings.get('route_inactive_badge', locale),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary)),
                                ),
                            ]),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: border),
                    foregroundColor: textPrimary,
                  ),
                  child: Text(AppStrings.get('close', locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
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
