import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../core/theme/app_theme.dart';
import 'app_loading_indicator.dart';
import '../../core/network/geocode_repository.dart';
import '../widgets/place.dart';

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

  Point _centerPoint = const Point(latitude: 0, longitude: 0);
  String _fullAddr = '';
  String _addr = '';
  bool _resolving = true;
  bool _searching = false;
  bool _cameraMoving = false;
  List<Place> _results = [];
  Timer? _debounce;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _centerPoint = Point(latitude: widget.initialLat, longitude: widget.initialLng);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolveCenter() async {
    setState(() => _resolving = true);
    final repo = ref.read(geocodeRepositoryProvider);
    final result = await repo.reverse(_centerPoint.latitude, _centerPoint.longitude);
    if (!mounted) return;
    setState(() {
      _fullAddr = result.fullAddr.isNotEmpty ? result.fullAddr : result.city;
      _addr = result.street;
      _resolving = false;
    });
  }

  void _onCameraPositionChanged(CameraPosition pos, CameraUpdateReason reason, bool finished) {
    _centerPoint = pos.target;
    if (!finished) {
      if (!_cameraMoving) setState(() => _cameraMoving = true);
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _cameraMoving = false);
        _resolveCenter();
      }
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final repo = ref.read(geocodeRepositoryProvider);
      final results = await repo.search(
        query,
        lat: _centerPoint.latitude,
        lng: _centerPoint.longitude,
      );
      if (!mounted) return;
      setState(() {
        _results = results
            .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
            .toList();
        _searching = false;
      });
    });
  }

  Future<void> _selectSearchResult(Place place) async {
    _searchFocus.unfocus();
    setState(() => _results = []);
    _searchCtrl.text = place.name;
    final point = Point(latitude: place.lat, longitude: place.lng);
    _centerPoint = point;
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 16)),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
    );
    if (!mounted) return;
    setState(() {
      _fullAddr = place.name;
      _addr = place.address;
    });
  }

  void _confirm() {
    Navigator.pop(
      context,
      Place(name: _fullAddr, address: _addr, lat: _centerPoint.latitude, lng: _centerPoint.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final pinColor = widget.isFrom ? AppTheme.primaryColor : AppTheme.successColor;
    final pinIcon = widget.isFrom ? Icons.local_shipping : Icons.flag;

    final showResults = _searchFocus.hasFocus && (_results.isNotEmpty || _searching);

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

          // Markaziy pin — Yandex uslubidagi "tayoqcha" effekti bilan:
          // xarita harakatlanayotganda pin sal ko'tariladi va uzayadi,
          // to'xtaganda joyiga (tayoqcha uchi markazga) tushadi.
          IgnorePointer(
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                // Harakatda pin yuqoriroq turadi (go'yo ko'tarilgandek),
                // to'xtaganda pastga tushib, uchi markazga tegadi
                margin: EdgeInsets.only(bottom: _cameraMoving ? 20 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      scale: _cameraMoving ? 1.15 : 1.0,
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
                    // Tayoqcha — pastga cho'ziladigan chiziq, xarita
                    // harakatlanganda uzunroq bo'lib ko'rinadi
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 3,
                      height: _cameraMoving ? 26 : 14,
                      decoration: BoxDecoration(
                        color: pinColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Yerdagi soya/nuqta — pin tagi shu joyga to'g'ri keladi
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

          // Tepa panel — orqaga + qidiruv
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
                  Container(
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
                        hintText: 'Manzil qidirish...',
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
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _results = []);
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (showResults)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 100,
              left: 0, right: 0, bottom: 0,
              child: Container(
                color: surface,
                child: _searching
                    ? const Center(child: AppLoadingIndicator(strokeWidth: 2))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: border),
                        itemBuilder: (ctx, i) {
                          final place = _results[i];
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
            ),

          if (!showResults)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                ),
                padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.paddingOf(context).bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(pinIcon, size: 14, color: pinColor),
                      const SizedBox(width: 6),
                      Text('Tanlangan manzil', style: TextStyle(fontSize: 11, color: textSecondary)),
                    ]),
                    const SizedBox(height: 6),
                    _resolving
                        ? Row(children: [
                            const SizedBox(width: 14, height: 14,
                                child: AppLoadingIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('Aniqlanmoqda...', style: TextStyle(fontSize: 13, color: textSecondary)),
                          ])
                        : Text(_fullAddr.isNotEmpty ? _fullAddr : 'Manzil topilmadi',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: (!_resolving && _fullAddr.isNotEmpty) ? _confirm : null,
                      child: Container(
                        width: double.infinity, height: 50,
                        decoration: BoxDecoration(
                          gradient: (!_resolving && _fullAddr.isNotEmpty)
                              ? const LinearGradient(
                                  colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                                )
                              : null,
                          color: (!_resolving && _fullAddr.isNotEmpty) ? null : Colors.grey.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text('Tasdiqlash',
                              style: TextStyle(
                                color: (!_resolving && _fullAddr.isNotEmpty) ? Colors.white : Colors.grey,
                                fontSize: 15, fontWeight: FontWeight.w700,
                              )),
                        ),
                      ),
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