import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/network/rating_repository.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/place.dart';
import '../../../../shared/widgets/address_modal.dart';
import '../../../../shared/widgets/map_address_picker.dart';
import '../../../../shared/widgets/rating_dialog.dart';
import '../widgets/client_menu_sheet.dart';

const double _kMinZoom = 3.0;
const double _kMaxZoom = 20.0;

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> with RouteAware {
  YandexMapController? _mapController;
  bool _isDark = false;
  bool _tiltOn = false;
  double _currentZoom = 14;
  bool _showTopPanel = true;
  String _currentAddressLabel = '';

  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _finishIcon;
  BitmapDescriptor? _myLocationIcon;

  Place? _fromPlace;
  Place? _toPlace;
  double _fromLat = 41.2995;
  double _fromLng = 69.2401;
  double? _routeDistKm;
  int? _routeTimeMin;

  Map<String, dynamic>? _activeOrder;
  Timer? _orderTimer;
  Timer? _trackingTimer;

  double? _driverEtaKm;
  int? _driverEtaMin;

  List<MapObject> _mapObjects = [];

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _initLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newDark = Theme.of(context).brightness == Brightness.dark;
    if (newDark != _isDark) {
      _isDark = newDark;
      if (_fromPlace != null && _toPlace != null) _drawRoute();
    }
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _orderTimer?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  @override
  void didPushNext() {
    if (mounted) setState(() => _showTopPanel = false);
  }

  @override
  void didPopNext() {
    if (mounted) setState(() => _showTopPanel = true);
  }

  Future<void> _loadIcons() async {
    if (MapIconHelper.isPreloaded) {
      setState(() {
        _truckIcon = MapIconHelper.truckIconReady;
        _finishIcon = MapIconHelper.finishIconReady;
        _myLocationIcon = MapIconHelper.myLocationIconReady;
      });
      _rebuildMapObjects();
      return;
    }
    await MapIconHelper.preloadAll();
    if (!mounted) return;
    setState(() {
      _truckIcon = MapIconHelper.truckIconReady;
      _finishIcon = MapIconHelper.finishIconReady;
      _myLocationIcon = MapIconHelper.myLocationIconReady;
    });
    _rebuildMapObjects();
  }

  void _rebuildMapObjects({List<Point>? routePoints}) {
    final objects = <MapObject>[];

    if (routePoints != null && _fromPlace != null && _toPlace != null) {
      objects.add(PolylineMapObject(
        mapId: const MapObjectId('route'),
        polyline: Polyline(points: routePoints),
        strokeColor: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF1d4ed8),
        strokeWidth: 5,
      ));
      if (_truckIcon != null) {
        objects.add(PlacemarkMapObject(
          mapId: const MapObjectId('from_pin'),
          point: Point(latitude: _fromPlace!.lat, longitude: _fromPlace!.lng),
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: _truckIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
          )),
          onTap: (_, __) => _editPinLocation(isFrom: true),
        ));
      }
      if (_finishIcon != null) {
        objects.add(PlacemarkMapObject(
          mapId: const MapObjectId('to_pin'),
          point: Point(latitude: _toPlace!.lat, longitude: _toPlace!.lng),
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: _finishIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
          )),
          onTap: (_, __) => _editPinLocation(isFrom: false),
        ));
      }
    } else if (_myLocationIcon != null && _activeOrder == null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('my_location'),
        point: Point(latitude: _fromLat, longitude: _fromLng),
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: _myLocationIcon!, scale: 0.18, anchor: const Offset(0.5, 0.5),
        )),
      ));
    }

    setState(() => _mapObjects = objects);
  }

  Future<void> _initLocation() async {
    try {
      bool ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          if (mounted) _showLocationDeniedNotice();
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) _showLocationDeniedNotice();
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _fromLat = pos.latitude;
        _fromLng = pos.longitude;
      });
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: Point(latitude: pos.latitude, longitude: pos.longitude), zoom: 14),
        ),
      );
      _rebuildMapObjects();

      final repo = ref.read(geocodeRepositoryProvider);
      final result = await repo.reverse(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentAddressLabel = result.fullAddr.isNotEmpty
              ? AddressHelper.shorten(result.fullAddr)
              : result.city;
        });
        if (_fromPlace == null && result.fullAddr.isNotEmpty) {
          setState(() {
            _fromPlace = Place(
              name: result.fullAddr,
              address: result.street,
              lat: pos.latitude,
              lng: pos.longitude,
            );
          });
        }
      }
    } catch (_) {}
  }

  void _showLocationDeniedNotice() {
    final locale = ref.read(localeProvider).languageCode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.get('location_permission_denied', locale)),
        backgroundColor: AppTheme.warningColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _locateMe() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: Point(latitude: pos.latitude, longitude: pos.longitude), zoom: 15),
        ),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
      );
    } catch (_) {
      if (mounted) _showLocationDeniedNotice();
    }
  }

  void _goToDestination() {
    double? lat;
    double? lng;
    if (_activeOrder != null) {
      final status = _activeOrder!['status'] as String;
      final isPickup = status == 'ACCEPTED' || status == 'DRIVER_ARRIVING';
      lat = isPickup ? _fromLat : (_activeOrder!['toLatitude'] as num?)?.toDouble();
      lng = isPickup ? _fromLng : (_activeOrder!['toLongitude'] as num?)?.toDouble();
    } else if (_toPlace != null) {
      lat = _toPlace!.lat;
      lng = _toPlace!.lng;
    }
    if (lat == null || lng == null) return;
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: Point(latitude: lat, longitude: lng), zoom: 15)),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
    );
  }

  void _toggleTilt() {
    setState(() => _tiltOn = !_tiltOn);
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: Point(latitude: _fromLat, longitude: _fromLng), zoom: _currentZoom, tilt: _tiltOn ? 45 : 0),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.4),
    );
  }

  void _zoomBy(double delta) {
    final newZoom = (_currentZoom + delta).clamp(_kMinZoom, _kMaxZoom);
    _mapController?.moveCamera(
      CameraUpdate.zoomTo(newZoom),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.25),
    );
  }

  Future<void> _editPinLocation({required bool isFrom}) async {
    final current = isFrom ? _fromPlace : _toPlace;
    if (current == null) return;
    final locale = ref.read(localeProvider).languageCode;
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapAddressPicker(
          initialLat: current.lat,
          initialLng: current.lng,
          title: isFrom ? AppStrings.get('from_question', locale) : AppStrings.get('to_question', locale),
          isFrom: isFrom,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isFrom) { _fromPlace = result; } else { _toPlace = result; }
    });
    _drawRoute();
  }

  Future<void> _drawRoute() async {
    if (_fromPlace == null || _toPlace == null) return;
    final repo = ref.read(geocodeRepositoryProvider);

    final route = await repo.getRoute(
      fromLat: _fromPlace!.lat, fromLng: _fromPlace!.lng,
      toLat: _toPlace!.lat, toLng: _toPlace!.lng,
    );

    if (!mounted) return;

    final points = route?.points
            .map((c) => Point(latitude: c[0], longitude: c[1]))
            .toList() ??
        [
          Point(latitude: _fromPlace!.lat, longitude: _fromPlace!.lng),
          Point(latitude: _toPlace!.lat, longitude: _toPlace!.lng),
        ];

    setState(() {
      _routeDistKm = route?.distanceKm;
      _routeTimeMin = route?.durationMin;
    });
    _rebuildMapObjects(routePoints: points);
    _fitBounds(points);
  }

  void _fitBounds(List<Point> points) {
    final lats = points.map((p) => p.latitude).toList();
    final lngs = points.map((p) => p.longitude).toList();
    final latSpan = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
    final lngSpan = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
    final latPad = (latSpan * 0.4).clamp(0.015, 2.0);
    final lngPad = (lngSpan * 0.3).clamp(0.015, 2.0);

    _mapController?.moveCamera(
      CameraUpdate.newBounds(
        BoundingBox(
          northEast: Point(latitude: lats.reduce((a, b) => a > b ? a : b) + latPad,
              longitude: lngs.reduce((a, b) => a > b ? a : b) + lngPad),
          southWest: Point(latitude: lats.reduce((a, b) => a < b ? a : b) - latPad * 1.8,
              longitude: lngs.reduce((a, b) => a < b ? a : b) - lngPad),
        ),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.6),
    );
  }

  void _openAddressModal() {
    final isDark = _isDark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => AddressModal(
        isDark: isDark,
        initialFrom: _fromPlace,
        fromLat: _fromLat,
        fromLng: _fromLng,
        onConfirmed: (from, to) {
          setState(() { _fromPlace = from; _toPlace = to; });
          _drawRoute();
          Future.delayed(const Duration(milliseconds: 280), () {
            if (mounted) _showOrderDetails();
          });
        },
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _fromPlace = null;
      _toPlace = null;
      _routeDistKm = null;
      _routeTimeMin = null;
    });
    _rebuildMapObjects();
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ClientMenuSheet(),
    );
  }

  bool _isPickupPhase(String status) => status == 'ACCEPTED' || status == 'DRIVER_ARRIVING';

  Future<void> _updateDriverTracking() async {
    if (_activeOrder == null) return;
    final driver = _activeOrder!['driver'] as Map<String, dynamic>?;
    if (driver == null) return;

    final driverLat = (driver['lastLatitude'] as num?)?.toDouble();
    final driverLng = (driver['lastLongitude'] as num?)?.toDouble();
    if (driverLat == null || driverLng == null) return;

    final status = _activeOrder!['status'] as String;
    final isPickup = _isPickupPhase(status);

    final targetLat = isPickup ? _fromLat : (_activeOrder!['toLatitude'] as num).toDouble();
    final targetLng = isPickup ? _fromLng : (_activeOrder!['toLongitude'] as num).toDouble();

    final repo = ref.read(geocodeRepositoryProvider);
    final route = await repo.getRoute(fromLat: driverLat, fromLng: driverLng, toLat: targetLat, toLng: targetLng);

    if (!mounted) return;

    final points = route?.points
            .map((c) => Point(latitude: c[0], longitude: c[1]))
            .toList() ??
        [
          Point(latitude: driverLat, longitude: driverLng),
          Point(latitude: targetLat, longitude: targetLng),
        ];

    setState(() {
      _driverEtaKm = route?.distanceKm;
      _driverEtaMin = route?.durationMin;
      _mapObjects = [
        PolylineMapObject(
          mapId: const MapObjectId('driver_track'),
          polyline: Polyline(points: points),
          strokeColor: isPickup
              ? (_isDark ? const Color(0xFF60A5FA) : const Color(0xFF1d4ed8))
              : (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
          strokeWidth: 5,
        ),
        if (_truckIcon != null)
          PlacemarkMapObject(
            mapId: const MapObjectId('driver_pin'),
            point: Point(latitude: driverLat, longitude: driverLng),
            icon: PlacemarkIcon.single(PlacemarkIconStyle(
              image: _truckIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
            )),
          ),
        if (_finishIcon != null)
          PlacemarkMapObject(
            mapId: const MapObjectId('target_pin'),
            point: Point(latitude: targetLat, longitude: targetLng),
            icon: PlacemarkIcon.single(PlacemarkIconStyle(
              image: _finishIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
            )),
          ),
      ];
    });

    _fitBounds(points);
  }

  Future<void> _refreshActiveOrder() async {
    try {
      final orders = await ref.read(clientRepositoryProvider).getOrders();
      if (orders.isEmpty || !mounted) return;
      final latest = orders.first;
      final status = latest['status'] as String;

      if (['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) {
        setState(() => _activeOrder = latest);
        await _updateDriverTracking();
      } else if (status == 'DELIVERED' || status == 'COMPLETED') {
        _trackingTimer?.cancel();
        setState(() => _activeOrder = latest);
      } else if (status == 'CANCELLED') {
        _trackingTimer?.cancel();
        setState(() {
          _activeOrder = null;
          _fromPlace = null;
          _toPlace = null;
        });
        _rebuildMapObjects();
      }
    } catch (_) {}
  }

  int get _zoomPercent =>
      (((_currentZoom - _kMinZoom) / (_kMaxZoom - _kMinZoom)) * 100).round().clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final showDestinationBtn = _activeOrder != null || _toPlace != null;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: YandexMap(
              nightModeEnabled: isDark,
              onMapCreated: (controller) {
                _mapController = controller;
                controller.moveCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: Point(latitude: _fromLat, longitude: _fromLng), zoom: 14),
                  ),
                );
              },
              onCameraPositionChanged: (pos, reason, finished) {
                if (finished && (pos.zoom - _currentZoom).abs() > 0.05) {
                  setState(() => _currentZoom = pos.zoom);
                }
              },
              mapObjects: _mapObjects,
            ),
          ),

          AnimatedSlide(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            offset: _showTopPanel ? Offset.zero : const Offset(0, -1.5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _showTopPanel ? 1 : 0,
              child: Positioned(
                top: 0, left: 0, right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openMenu,
                          child: Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: surface,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
                            ),
                            child: Icon(Icons.menu, color: textPrimary, size: 23),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 22, height: 22,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.local_shipping, color: Colors.white, size: 13),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('GoWay',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                                  ],
                                ),
                                if (_currentAddressLabel.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentAddressLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 16,
            top: screenHeight / 2 - 90,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      IconButton(
                        icon: Icon(Icons.add, color: textPrimary, size: 22),
                        onPressed: () => _zoomBy(1),
                      ),
                      Text('$_zoomPercent%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary)),
                      IconButton(
                        icon: Icon(Icons.remove, color: textPrimary, size: 22),
                        onPressed: () => _zoomBy(-1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _toggleTilt,
                  child: _CircleBtn(
                    icon: Icons.view_in_ar_outlined,
                    surface: _tiltOn ? AppTheme.primaryColor : surface,
                    textColor: _tiltOn ? Colors.white : textPrimary,
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            right: 16,
            top: screenHeight / 2 - 55,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _locateMe,
                  child: _CircleBtn(icon: Icons.my_location, surface: AppTheme.primaryColor, textColor: Colors.white),
                ),
                if (showDestinationBtn) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _goToDestination,
                    child: _CircleBtn(icon: Icons.flag, surface: AppTheme.primaryColor, textColor: Colors.white),
                  ),
                ],
              ],
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 16)],
              ),
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
                  )),
                  const SizedBox(height: 12),

                  if (_activeOrder == null && _routeDistKm != null) ...[
                    _RouteInfoRow(distKm: _routeDistKm!, timeMin: _routeTimeMin, isDark: isDark, locale: locale),
                    const SizedBox(height: 10),
                  ],
                  if (_activeOrder != null && _driverEtaKm != null) ...[
                    _RouteInfoRow(distKm: _driverEtaKm!, timeMin: _driverEtaMin, isDark: isDark, locale: locale, isEta: true),
                    const SizedBox(height: 10),
                  ],

                  if (_activeOrder != null) ...[
                    GestureDetector(
                      onTap: _showActiveOrder,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          Container(width: 8, height: 8,
                              decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_activeOrderStatusLabel(locale),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor))),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.primaryColor),
                        ]),
                      ),
                    ),
                  ] else if (_fromPlace != null && _toPlace != null) ...[
                    GestureDetector(
                      onTap: _openAddressModal,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            Column(children: [
                              const Icon(Icons.local_shipping, size: 14, color: AppTheme.primaryColor),
                              Container(width: 1, height: 12, color: border),
                              const Icon(Icons.flag, size: 14, color: AppTheme.successColor),
                            ]),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AddressHelper.shorten(_fromPlace!.name),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(AddressHelper.shorten(_toPlace!.name),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primaryColor),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _clearSelection,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(color: border),
                              foregroundColor: textSecondary,
                            ),
                            child: Text(AppStrings.get('cancel_selection', locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _GradBtn(label: AppStrings.get('place_order', locale), onTap: _showOrderDetails),
                        ),
                      ],
                    ),
                  ] else
                    _GradBtn(label: AppStrings.get('enter_address', locale), onTap: _openAddressModal),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _activeOrderStatusLabel(String locale) {
    final status = _activeOrder!['status'] as String? ?? '';
    switch (status) {
      case 'ACCEPTED': return AppStrings.get('driver_assigned', locale);
      case 'DRIVER_ARRIVING': return AppStrings.get('driver_arriving', locale);
      case 'LOADING': return AppStrings.get('loading_cargo', locale);
      case 'IN_TRANSIT': return AppStrings.get('in_transit', locale);
      case 'DELIVERED': return AppStrings.get('delivered_msg', locale);
      default: return AppStrings.get('order_active', locale);
    }
  }

  void _showOrderDetails() {
    final isDark = _isDark;
    final locale = ref.read(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;

    final weightCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? selectedTruck;
    List<Map<String, dynamic>> trucks = [];
    bool loading = false;
    bool trucksLoading = true;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          if (trucksLoading) {
            ref.read(clientRepositoryProvider).getTrucks().then((t) {
              trucksLoading = false;
              setSt(() => trucks = t);
            });
          }

          return Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

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
                      Text(AddressHelper.shorten(_fromPlace?.name ?? ''),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(AddressHelper.shorten(_toPlace?.name ?? ''),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                ]),
                const SizedBox(height: 18),

                Text(AppStrings.get('select_vehicle', locale),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 10),

                trucksLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    : SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: trucks.fold<Map<String, Map<String, dynamic>>>({}, (map, t) {
                            final key = t['type'] as String;
                            if (!map.containsKey(key)) map[key] = t;
                            return map;
                          }).values.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (ctx2, i) {
                            final uniqueTrucks = trucks.fold<Map<String, Map<String, dynamic>>>({}, (map, t) {
                              final key = t['type'] as String;
                              if (!map.containsKey(key)) map[key] = t;
                              return map;
                            }).values.toList();
                            final t = uniqueTrucks[i];
                            final selected = selectedTruck == t['type'];
                            return GestureDetector(
                              onTap: () => setSt(() => selectedTruck = t['type'] as String),
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
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(hintText: '1.5', hintStyle: TextStyle(color: textSecondary), suffixText: 't'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(hintText: AppStrings.get('note_optional', locale), hintStyle: TextStyle(color: textSecondary)),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                _GradBtn(
                  label: AppStrings.get('place_order', locale),
                  loading: loading,
                  onTap: (selectedTruck == null) ? null : () async {
                    if (weightCtrl.text.isEmpty) { setSt(() => error = AppStrings.get('enter_weight_error', locale)); return; }
                    setSt(() { loading = true; error = null; });
                    try {
                      await ref.read(clientRepositoryProvider).createOrder(
                        fromCity: _fromPlace!.name,
                        fromAddress: _fromPlace!.address,
                        toCity: _toPlace!.name,
                        toAddress: _toPlace!.address,
                        fromLatitude: _fromPlace!.lat,
                        fromLongitude: _fromPlace!.lng,
                        toLatitude: _toPlace!.lat,
                        toLongitude: _toPlace!.lng,
                        truckType: selectedTruck!,
                        weight: double.parse(weightCtrl.text),
                        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                      );
                      if (mounted) { Navigator.pop(ctx); _showSearching(); }
                    } catch (e) {
                      setSt(() { loading = false; error = AppStrings.get('generic_error', locale); });
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSearching() {
    final isDark = _isDark;
    final locale = ref.read(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    _orderTimer?.cancel();
    _orderTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final orders = await ref.read(clientRepositoryProvider).getOrders();
        if (orders.isNotEmpty) {
          final latest = orders.first;
          final status = latest['status'] as String;
          if (['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) {
            _orderTimer?.cancel();
            setState(() => _activeOrder = latest);
            if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            _startTrackingLoop();
            _showActiveOrder();
          } else if (status == 'CANCELLED') {
            _orderTimer?.cancel();
            if (mounted) Navigator.pop(context);
          }
        }
      } catch (_) {}
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.1),
              duration: const Duration(milliseconds: 900),
              builder: (ctx, val, child) => Transform.scale(scale: val, child: child),
              child: Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            Text(AppStrings.get('searching_driver', locale), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 6),
            Text('${AddressHelper.shorten(_fromPlace?.name ?? '')} → ${AddressHelper.shorten(_toPlace?.name ?? '')}',
                style: const TextStyle(fontSize: 13, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              backgroundColor: border,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
              borderRadius: BorderRadius.circular(4),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: () { _orderTimer?.cancel(); Navigator.pop(ctx); },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: border),
                foregroundColor: textSecondary,
              ),
              child: Text(AppStrings.get('cancel_search', locale)),
            ),
          ],
        ),
      ),
    );
  }

  void _startTrackingLoop() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _refreshActiveOrder());
    _updateDriverTracking();
  }

  void _showActiveOrder() {
    if (_activeOrder == null) return;
    final locale = ref.read(localeProvider).languageCode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: _isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _ActiveOrderSheet(
        order: _activeOrder!,
        isDark: _isDark,
        locale: locale,
        distKm: _driverEtaKm,
        timeMin: _driverEtaMin,
        onComplete: () {
          _trackingTimer?.cancel();
          Navigator.pop(ctx);
          setState(() {
            _activeOrder = null; _fromPlace = null; _toPlace = null;
            _driverEtaKm = null; _driverEtaMin = null;
          });
          _rebuildMapObjects();
        },
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color surface;
  final Color textColor;
  const _CircleBtn({required this.icon, required this.surface, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Icon(icon, color: textColor, size: 23),
    );
  }
}

class _RouteInfoRow extends StatelessWidget {
  final double distKm;
  final int? timeMin;
  final bool isDark;
  final String locale;
  final bool isEta;

  const _RouteInfoRow({required this.distKm, this.timeMin, required this.isDark, required this.locale, this.isEta = false});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(isEta ? Icons.local_shipping : Icons.route, size: 16, color: AppTheme.primaryColor),
        const SizedBox(width: 7),
        Text('${distKm.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
        if (timeMin != null) ...[
          Container(margin: const EdgeInsets.symmetric(horizontal: 10), width: 1, height: 14, color: textSecondary.withOpacity(0.3)),
          Icon(Icons.access_time, size: 14, color: textSecondary),
          const SizedBox(width: 5),
          Text(
            timeMin! >= 60
                ? '${timeMin! ~/ 60}${AppStrings.get('route_time_hour', locale)} ${timeMin! % 60}${AppStrings.get('route_time_min', locale)}'
                : '$timeMin ${AppStrings.get('route_time_min', locale)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
          ),
        ],
      ]),
    );
  }
}

// ===== AKTIV BUYURTMA SHEET — endi ConsumerWidget (baholash uchun ref kerak) =====
class _ActiveOrderSheet extends ConsumerWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final double? distKm;
  final int? timeMin;
  final VoidCallback onComplete;

  const _ActiveOrderSheet({
    required this.order, required this.isDark, required this.locale,
    this.distKm, this.timeMin, required this.onComplete,
  });

  Future<void> _openRatingThenComplete(BuildContext context, WidgetRef ref, Map<String, dynamic>? driver, String orderId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => RatingDialog(
        title: 'Haydovchini baholang',
        subtitle: driver != null ? (driver['fullName'] as String? ?? '') : '',
        onSubmit: (score, note) async {
          await ref.read(ratingRepositoryProvider).rateDriver(
            orderId: orderId,
            score: score,
            note: note,
          );
        },
      ),
    );
    onComplete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textP = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textS = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    final status = order['status'] as String? ?? '';
    final driver = order['driver'] as Map<String, dynamic>?;
    final price = (order['price'] as num?) ?? 0;
    final fromCity = order['fromCity'] as String? ?? '';
    final toCity = order['toCity'] as String? ?? '';
    final orderId = order['id'] as String? ?? '';
    final isCompleted = status == 'COMPLETED' || status == 'DELIVERED';

    String statusLabel = AppStrings.get('driver_arriving', locale);
    Color statusColor = AppTheme.primaryColor;
    if (status == 'LOADING') { statusLabel = AppStrings.get('loading_cargo', locale); statusColor = Colors.orange; }
    if (status == 'IN_TRANSIT') { statusLabel = AppStrings.get('in_transit', locale); statusColor = AppTheme.successColor; }
    if (status == 'DELIVERED') { statusLabel = AppStrings.get('delivered_msg', locale); statusColor = AppTheme.successColor; }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.12), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                    ]),
                  ),
                  const Spacer(),
                  Text('${(price / 1000).toStringAsFixed(0)} 000 so\'m',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textP)),
                ]),
                if (distKm != null && !isCompleted) ...[
                  const SizedBox(height: 10),
                  _RouteInfoRow(distKm: distKm!, timeMin: timeMin, isDark: isDark, locale: locale, isEta: true),
                ],
                const SizedBox(height: 14),
                if (driver != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text((driver['fullName'] as String? ?? 'D')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(driver['fullName'] as String? ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textP)),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.local_shipping_outlined, size: 12, color: AppTheme.primaryColor),
                          const SizedBox(width: 4),
                          Text('${order['truckType'] ?? ''} · ${driver['plateNumber'] ?? ''}', style: TextStyle(fontSize: 12, color: textS)),
                        ]),
                      ])),
                      GestureDetector(
                        onTap: () {
                          context.push('/chat/$orderId', extra: driver['fullName'] as String? ?? '');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.chat_bubble_outline, size: 18, color: AppTheme.primaryColor),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Column(children: [
                      const Icon(Icons.local_shipping, size: 16, color: AppTheme.primaryColor),
                      Container(width: 2, height: 20, color: border),
                      const Icon(Icons.flag, size: 16, color: AppTheme.successColor),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fromCity, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                      const SizedBox(height: 12),
                      Text(toCity, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
                if (isCompleted)
                  GestureDetector(
                    onTap: () => _openRatingThenComplete(context, ref, driver, orderId),
                    child: Container(
                      width: double.infinity, height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF065f46), Color(0xFF059669)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: Center(child: Text('✅  ${AppStrings.get('complete_order', locale)}',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
                    ),
                  ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== HELPERS =====
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
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}