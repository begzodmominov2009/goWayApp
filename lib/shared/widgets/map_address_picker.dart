import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import 'animated_clear_button.dart';
import 'app_loading_indicator.dart';
import 'circle_icon_button.dart';
import '../../core/network/geocode_repository.dart';
import '../widgets/place.dart';

/// Markaziy pin (xarita) orqali aniqlangan manzil holati — pastki panel
/// shu qiymatga obuna bo'ladi.
class _AddressResolution {
  final bool resolving;
  final String fullAddr;
  final String addr;
  const _AddressResolution({required this.resolving, required this.fullAddr, required this.addr});
  static const initial = _AddressResolution(resolving: true, fullAddr: '', addr: '');
}

/// Qidiruv holati — natijalar, "qidirilmoqda" bayrog'i va inputning
/// fokusda-yo'qligi. `showResults` shu uchalasidan hisoblanadi: natija
/// ro'yxati (yoki qidiruv) faqat input FOKUSDA bo'lganda ko'rsatiladi.
class _SearchState {
  final List<Place> results;
  final bool searching;
  final bool hasFocus;
  const _SearchState({required this.results, required this.searching, required this.hasFocus});
  static const initial = _SearchState(results: [], searching: false, hasFocus: false);

  _SearchState copyWith({List<Place>? results, bool? searching, bool? hasFocus}) => _SearchState(
        results: results ?? this.results,
        searching: searching ?? this.searching,
        hasFocus: hasFocus ?? this.hasFocus,
      );

  bool get showResults => hasFocus && (results.isNotEmpty || searching);
}

class MapAddressPicker extends ConsumerStatefulWidget {
  final double initialLat;
  final double initialLng;
  final String title;
  final bool isFrom;

  const MapAddressPicker({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.title,
    required this.isFrom,
  });

  @override
  ConsumerState<MapAddressPicker> createState() => _MapAddressPickerState();
}

class _MapAddressPickerState extends ConsumerState<MapAddressPicker> {
  YandexMapController? _mapController;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // _searchCtrl/_searchFocus bilan bir xil sabab (order_form_modal.dart
  // dagi _searchClearButton'ga qarang) — X tugmasi BIR MARTA, late final
  // maydon sifatida yaratiladi, build() ichida emas.
  late final Widget _searchClearButton = AnimatedClearButton(
    controller: _searchCtrl,
    focusNode: _searchFocus,
    onCleared: () => _searchNotifier.value = _searchNotifier.value.copyWith(results: []),
  );

  // Markaziy nuqta — kamera harakati bilan bir xil kadrda yangilanadi,
  // lekin bu ODDIY maydon: hech qanday UI shu maydonning o'ziga
  // to'g'ridan-to'g'ri obuna bo'lmaydi (faqat _confirm()/_resolveCenter()
  // kabi joylarda o'qiladi), shuning uchun uni yangilash rebuild talab
  // qilmaydi.
  Point _centerPoint = const Point(latitude: 0, longitude: 0);

  // === Performance (4-band) uchun MUHIM: setState() O'RNIGA ValueNotifier ===
  // Har biri FAQAT o'ziga tegishli kichik subtree'ni qayta quradi — butun
  // Scaffold (jumladan YandexMap ustidagi qatlamlar) EMAS. _MapAddressPickerState
  // ning o'z build() metodi shu tuzatishdan keyin AMALDA faqat BIR MARTA
  // (dastlabki chizishda) ishga tushadi — qolgan hammasi quyidagi
  // ValueListenableBuilder'lar orqali.
  final ValueNotifier<bool> _cameraMovingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _panelTransparentNotifier = ValueNotifier(false);
  final ValueNotifier<_AddressResolution> _addressNotifier = ValueNotifier(_AddressResolution.initial);
  final ValueNotifier<_SearchState> _searchNotifier = ValueNotifier(_SearchState.initial);

  Timer? _debounce;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _centerPoint = Point(latitude: widget.initialLat, longitude: widget.initialLng);
    _searchFocus.addListener(() {
      _searchNotifier.value = _searchNotifier.value.copyWith(hasFocus: _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _idleTimer?.cancel();
    _cameraMovingNotifier.dispose();
    _panelTransparentNotifier.dispose();
    _addressNotifier.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  Future<void> _resolveCenter() async {
    _addressNotifier.value = _AddressResolution(
      resolving: true, fullAddr: _addressNotifier.value.fullAddr, addr: _addressNotifier.value.addr,
    );
    final repo = ref.read(geocodeRepositoryProvider);
    final result = await repo.reverse(_centerPoint.latitude, _centerPoint.longitude);
    if (!mounted) return;
    _addressNotifier.value = _AddressResolution(
      resolving: false,
      fullAddr: result.fullAddr.isNotEmpty ? result.fullAddr : result.city,
      addr: result.street,
    );
  }

  // 2-BAND (ENG MUHIM): kamera harakatlanganda pastki panelni shaffof
  // qilish. `reason == gestures && !finished` — foydalanuvchi barmog'i
  // bilan surayotganda (shaffof). `finished` — harakat tugaganda (qo'l
  // qo'yib yuborilishida ham, dastur o'zi kamerani surganda ham) DARHOL
  // o'z holiga qaytadi, kechikishsiz. Pin animatsiyasi (_cameraMovingNotifier)
  // va manzilni geokodlash esa — AVVALGIDEK — 300ms debounce bilan,
  // xarita chindan to'xtaganda birga ishlaydi (4-band: bu debounce
  // ALLAQACHON bor edi, o'zgartirilmadi).
  //
  // "O'zini topish" tugmasi bosilganda (5-band) kamera KOD bilan
  // suriladi — reason bu payt `application` bo'ladi, shuning uchun
  // pastdagi shart (`reason == gestures`) ishga TUSHMAYDI va panel
  // shaffof bo'lib qolmaydi.
  void _onCameraPositionChanged(CameraPosition pos, CameraUpdateReason reason, bool finished) {
    _centerPoint = pos.target;
    if (!finished) {
      _cameraMovingNotifier.value = true;
      if (reason == CameraUpdateReason.gestures) {
        _panelTransparentNotifier.value = true;
      }
      return;
    }
    _panelTransparentNotifier.value = false;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _cameraMovingNotifier.value = false;
      _resolveCenter();
    });
  }

  // Qidiruv — ALLAQACHON 500ms debounce bilan edi (4-band: tekshirildi,
  // qo'shimcha debounce shart emas). setState() endi UMUMAN yo'q.
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _searchNotifier.value = _searchNotifier.value.copyWith(results: [], searching: false);
      return;
    }
    _searchNotifier.value = _searchNotifier.value.copyWith(searching: true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final repo = ref.read(geocodeRepositoryProvider);
      final results = await repo.search(
        query,
        lat: _centerPoint.latitude,
        lng: _centerPoint.longitude,
      );
      if (!mounted) return;
      _searchNotifier.value = _searchNotifier.value.copyWith(
        results: results
            .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
            .toList(),
        searching: false,
      );
    });
  }

  Future<void> _selectSearchResult(Place place) async {
    _searchFocus.unfocus();
    _searchNotifier.value = _searchNotifier.value.copyWith(results: []);
    _searchCtrl.text = place.name;
    final point = Point(latitude: place.lat, longitude: place.lng);
    _centerPoint = point;
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 16)),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
    );
    if (!mounted) return;
    _addressNotifier.value = _AddressResolution(resolving: false, fullAddr: place.name, addr: place.address);
  }

  // 5-BAND: Home ekranidagi _locateMe() bilan AYNAN bir xil mantiq
  // (loyihada mavjud naqsh — yangisi o'ylab topilmadi): xizmat/ruxsat
  // tekshiruvi, getCurrentPosition (8s limit bilan), muvaffaqiyatsiz
  // bo'lsa getLastKnownPosition'ga tushish, so'ng silliq (0.5s)
  // kamera animatsiyasi. Bu KOD bilan (dastur) kamera surilishi —
  // onCameraPositionChanged'da reason == application bo'ladi, shuning
  // uchun 2-banddagi shaffoflik ISHGA TUSHMAYDI.
  Future<void> _locateMe() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) rethrow;
        pos = last;
      }

      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: Point(latitude: pos.latitude, longitude: pos.longitude), zoom: 16),
        ),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
      );
    } catch (_) {
      // Home ekranidagi bilan bir xil — ruxsat/xizmat yo'q bo'lsa jimgina
      // e'tiborsiz qoldiriladi (bu ekranda alohida ogohlantirish banneri
      // yo'q, shuning uchun shovqin qilinmaydi; tugma shunchaki hech
      // narsa qilmaydi).
    }
  }

  void _confirm() {
    final info = _addressNotifier.value;
    Navigator.pop(
      context,
      Place(name: info.fullAddr, address: info.addr, lat: _centerPoint.latitude, lng: _centerPoint.longitude),
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
    final pinColor = widget.isFrom ? AppTheme.primaryColor : AppTheme.successColor;
    final pinIcon = widget.isFrom ? Icons.local_shipping : Icons.flag;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: YandexMap(
              nightModeEnabled: isDark,
              onMapCreated: (controller) {
                _mapController = controller;
                controller.moveCamera(
                  CameraUpdate.newCameraPosition(CameraPosition(target: _centerPoint, zoom: 15)),
                );
                _resolveCenter();
              },
              onCameraPositionChanged: _onCameraPositionChanged,
            ),
          ),

          // Markaziy pin — FAQAT shu qism _cameraMovingNotifier'ga obuna
          // (4-band: avval butun ekranni setState() bilan qayta qurardi).
          IgnorePointer(
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: _cameraMovingNotifier,
                builder: (context, cameraMoving, _) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  margin: EdgeInsets.only(bottom: cameraMoving ? 20 : 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        scale: cameraMoving ? 1.15 : 1.0,
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: pinColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                          ),
                          child: Icon(pinIcon, color: Colors.white, size: 22),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 3,
                        height: cameraMoving ? 26 : 14,
                        decoration: BoxDecoration(
                          color: pinColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tepa panel — orqaga + qidiruv. Yozish/tozalash endi setState()
          // chaqirmaydi (natijalar/hasFocus _searchNotifier orqali), shu
          // sabab bu butun panel ENDI reaktiv o'rash TALAB QILMAYDI.
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: surface.withOpacity(0.97),
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 6,
                left: 4, right: 12, bottom: 10,
              ),
              child: Column(
                children: [
                  Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Icon(pinIcon, color: pinColor, size: 16),
                    const SizedBox(width: 6),
                    Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                  ]),
                  const SizedBox(height: 6),
                  Row(
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
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            onChanged: _onSearchChanged,
                            style: TextStyle(fontSize: 14, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: AppStrings.get('search_address_hint', locale),
                              hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                      _searchClearButton,
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Natijalar ustki qatlami YOKI pastki tasdiqlash paneli — ikkalasi
          // bir vaqtda ko'rinmaydi, shuning uchun BITTA ValueListenableBuilder
          // ikkalasini ham boshqaradi.
          ValueListenableBuilder<_SearchState>(
            valueListenable: _searchNotifier,
            builder: (context, searchState, _) {
              if (searchState.showResults) {
                return Positioned(
                  top: MediaQuery.paddingOf(context).top + 100,
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    color: surface,
                    child: searchState.searching
                        ? const Center(child: AppLoadingIndicator(strokeWidth: 2))
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: searchState.results.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: border),
                            itemBuilder: (ctx, i) {
                              final place = searchState.results[i];
                              return ListTile(
                                leading: const Icon(Icons.location_on_outlined, color: AppTheme.primaryColor),
                                title: Text(place.name,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: place.address.isNotEmpty && place.address != place.name
                                    ? Text(place.address, style: TextStyle(fontSize: 12, color: textSecondary),
                                        maxLines: 1, overflow: TextOverflow.ellipsis)
                                    : null,
                                trailing: place.distanceKm != null
                                    ? Text(
                                        place.distanceKm! < 1
                                            ? '${(place.distanceKm! * 1000).round()} m'
                                            : '${place.distanceKm!.toStringAsFixed(1)} km',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                                      )
                                    : null,
                                onTap: () => _selectSearchResult(place),
                              );
                            },
                          ),
                  ),
                );
              }

              return Positioned(
                bottom: 0, left: 0, right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _panelTransparentNotifier,
                  builder: (context, transparent, child) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    opacity: transparent ? 0.35 : 1.0,
                    child: child,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                    ),
                    padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.paddingOf(context).bottom + 16),
                    child: ValueListenableBuilder<_AddressResolution>(
                      valueListenable: _addressNotifier,
                      builder: (context, info, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(pinIcon, size: 14, color: pinColor),
                            const SizedBox(width: 6),
                            Text(AppStrings.get('selected_address_label', locale), style: TextStyle(fontSize: 11, color: textSecondary)),
                          ]),
                          const SizedBox(height: 6),
                          info.resolving
                              ? Row(children: [
                                  const SizedBox(width: 14, height: 14,
                                      child: AppLoadingIndicator(strokeWidth: 2)),
                                  const SizedBox(width: 8),
                                  Text(AppStrings.get('resolving_label', locale), style: TextStyle(fontSize: 13, color: textSecondary)),
                                ])
                              : Text(info.fullAddr.isNotEmpty ? info.fullAddr : AppStrings.get('address_not_found', locale),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: (!info.resolving && info.fullAddr.isNotEmpty) ? _confirm : null,
                            child: Container(
                              width: double.infinity, height: 50,
                              decoration: BoxDecoration(
                                gradient: (!info.resolving && info.fullAddr.isNotEmpty)
                                    ? const LinearGradient(
                                        colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                                        begin: Alignment.centerLeft, end: Alignment.centerRight,
                                      )
                                    : null,
                                color: (!info.resolving && info.fullAddr.isNotEmpty) ? null : Colors.grey.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(AppStrings.get('confirm', locale),
                                    style: TextStyle(
                                      color: (!info.resolving && info.fullAddr.isNotEmpty) ? Colors.white : Colors.grey,
                                      fontSize: 15, fontWeight: FontWeight.w700,
                                    )),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 5-BAND: "O'zini topish" — Home ekranidagi bilan bir xil
          // komponent (CircleIconButton) va bir xil ikonka/o'lchov/rang.
          // Joylashuv uslubi ham bir xil formula bilan (o'ng chekka,
          // ekran balandligining vertikal o'rtasiga yaqin).
          Positioned(
            right: 16,
            top: MediaQuery.sizeOf(context).height / 2 - 55,
            child: GestureDetector(
              onTap: _locateMe,
              child: const CircleIconButton(icon: Icons.my_location, surface: AppTheme.primaryColor, textColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
