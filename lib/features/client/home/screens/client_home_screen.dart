import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/network/notification_repository.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/place.dart';
import '../../../../shared/widgets/map_address_picker.dart';
import '../../../../shared/widgets/driver_avatar.dart';
import '../../../../core/providers/active_order_provider.dart';
import '../widgets/client_menu_sheet.dart';

const double _kMinZoom = 3.0;
const double _kMaxZoom = 20.0;

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

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

  DateTime? _lastUserGestureAt;

  bool get _recentlyGestured =>
      _lastUserGestureAt != null && DateTime.now().difference(_lastUserGestureAt!) < const Duration(seconds: 3);

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

  bool _searching = false;
  Map<String, dynamic>? _pendingOrder;
  Offset? _radarScreenPos;

  int _unreadNotifCount = 0;
  Timer? _notifCountTimer;

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _initLocation();
    _checkActiveOrderOnStart();
    _loadUnreadNotifCount();
    _notifCountTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadUnreadNotifCount());
  }

  Future<void> _loadUnreadNotifCount() async {
    try {
      final count = await ref.read(notificationRepositoryProvider).getUnreadCount();
      if (mounted) setState(() => _unreadNotifCount = count);
    } catch (_) {}
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
    _notifCountTimer?.cancel();
    super.dispose();
  }

  @override
  void didPushNext() {
    if (mounted) setState(() => _showTopPanel = false);
  }

  @override
  void didPopNext() {
    if (mounted) setState(() => _showTopPanel = true);
    _loadUnreadNotifCount();
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
      bool ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) {
        if (mounted) _showLocationDeniedNotice();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) _showLocationDeniedNotice();
        return;
      }

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
    if (_recentlyGestured) return;
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

  Future<void> _centerOnPickupForSearch() async {
    if (_fromPlace == null) return;
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: Point(latitude: _fromPlace!.lat, longitude: _fromPlace!.lng), zoom: 16),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.6),
    );
    await Future.delayed(const Duration(milliseconds: 650));
    await _updateRadarScreenPos();
  }

  Future<void> _updateRadarScreenPos() async {
    if (!_searching || _fromPlace == null || _mapController == null || !mounted) return;
    try {
      final sp = await _mapController!.getScreenPoint(
        Point(latitude: _fromPlace!.lat, longitude: _fromPlace!.lng),
      );
      if (sp != null && mounted) {
        setState(() => _radarScreenPos = Offset(sp.x, sp.y));
      }
    } catch (_) {}
  }

  Future<void> _openSelectAddressPage() async {
    final result = await context.push<Map<String, Place>>(
      AppRoutes.clientSelectAddress,
      extra: {
        'initialFrom': _fromPlace,
        'fromLat': _fromLat,
        'fromLng': _fromLng,
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _fromPlace = result['from'];
      _toPlace = result['to'];
    });
    _drawRoute();
  }

  Future<void> _openOrderDetailsPage() async {
    if (_fromPlace == null || _toPlace == null) return;
    final created = await context.push<Map<String, dynamic>>(
      AppRoutes.clientOrderDetails,
      extra: {'fromPlace': _fromPlace, 'toPlace': _toPlace},
    );
    if (created != null && mounted) _showSearching(created);
  }

  // Yangi buyurtma oqimi: to'g'ridan-to'g'ri (agar hali tanlanmagan bo'lsa)
  // manzil tanlash sahifasini ochadi, so'ng OrderDetailsScreenga o'tadi.
  // "Manzil kiriting" va "Buyurtma berish" tugmalari ikkalasi ham shu bitta
  // metodga ulanadi — har bir await natijasi tekshirilib, null bo'lsa oqim
  // shu yerda to'xtaydi va hech qanday keyingi sahifa ochilmaydi.
  Future<void> _startOrderFlow() async {
    // Manzil hali tanlanmagan bo'lsa — tanlash sahifasini och
    if (_fromPlace == null || _toPlace == null) {
      final result = await context.push<Map<String, Place>>(
        AppRoutes.clientSelectAddress,
        extra: {'initialFrom': _fromPlace, 'fromLat': _fromLat, 'fromLng': _fromLng},
      );
      if (result == null || !mounted) return;
      setState(() { _fromPlace = result['from']; _toPlace = result['to']; });
      _drawRoute();
    }

    if (_fromPlace == null || _toPlace == null) return;

    final created = await context.push<Map<String, dynamic>>(
      AppRoutes.clientOrderDetails,
      extra: {
        'fromPlace': _fromPlace, 'toPlace': _toPlace,
        'distKm': _routeDistKm, 'timeMin': _routeTimeMin,
      },
    );
    if (created != null && mounted) _showSearching(created);
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
      sheetAnimationStyle: _kSheetAnimationStyle,
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

    final rawRoutePoints = _activeOrder!['routePoints'] as List?;
    final points = (rawRoutePoints != null && rawRoutePoints.isNotEmpty)
        ? rawRoutePoints
            .map((p) => Point(latitude: (p[0] as num).toDouble(), longitude: (p[1] as num).toDouble()))
            .toList()
        : [
            Point(latitude: driverLat, longitude: driverLng),
            Point(latitude: targetLat, longitude: targetLng),
          ];

    if (!mounted) return;

    setState(() {
      _driverEtaKm = (_activeOrder!['liveDistanceKm'] as num?)?.toDouble();
      _driverEtaMin = (_activeOrder!['liveDurationMin'] as num?)?.toInt();
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

  Future<void> _checkActiveOrderOnStart() async {
    try {
      final orders = await ref.read(clientRepositoryProvider).getOrders();
      if (orders.isEmpty || !mounted) return;
      final latest = orders.first;
      final status = latest['status'] as String;
      if (['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) {
        setState(() => _activeOrder = latest);
        _syncActiveOrderProvider();
        _startTrackingLoop();
      }
    } catch (_) {}
  }

  Future<void> _refreshActiveOrder() async {
    try {
      final orders = await ref.read(clientRepositoryProvider).getOrders();
      if (orders.isEmpty || !mounted) return;
      final latest = orders.first;
      final status = latest['status'] as String;

      if (['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) {
        setState(() => _activeOrder = latest);
        _syncActiveOrderProvider();
        await _updateDriverTracking();
      } else if (status == 'DELIVERED' || status == 'COMPLETED') {
        _trackingTimer?.cancel();
        setState(() => _activeOrder = latest);
        _syncActiveOrderProvider();
      } else if (status == 'CANCELLED') {
        _trackingTimer?.cancel();
        setState(() {
          _activeOrder = null;
          _fromPlace = null;
          _toPlace = null;
        });
        _syncActiveOrderProvider();
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
                if (reason == CameraUpdateReason.gestures) {
                  _lastUserGestureAt = DateTime.now();
                }
                if (finished && (pos.zoom - _currentZoom).abs() > 0.05) {
                  setState(() => _currentZoom = pos.zoom);
                }
                if (_searching && finished) _updateRadarScreenPos();
              },
              mapObjects: _mapObjects,
            ),
          ),

          if (_searching && _radarScreenPos != null)
            Positioned(
              left: _radarScreenPos!.dx - 70,
              top: _radarScreenPos!.dy - 70,
              child: const IgnorePointer(child: _RadarPulse()),
            ),

          Positioned(
            top: 0, left: 0, right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset: _showTopPanel ? Offset.zero : const Offset(0, -1.5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _showTopPanel ? 1 : 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openMenu,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 46, height: 46,
                                decoration: BoxDecoration(
                                  color: surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: border, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.menu, color: textPrimary, size: 23),
                              ),
                              if (_unreadNotifCount > 0)
                                Positioned(
                                  right: -2, top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.errorColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: surface, width: 1.5),
                                    ),
                                    child: Text(
                                      _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: border, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34, height: 34,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.route_rounded, color: Colors.white, size: 17),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        AppStrings.get('current_location_label', locale),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.2),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _currentAddressLabel.isNotEmpty ? _currentAddressLabel : 'GoWay',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
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
                      onTap: _openActiveOrderDetailsPage,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          if (_activeOrder!['driver'] != null) ...[
                            DriverAvatar(driver: _activeOrder!['driver'] as Map<String, dynamic>, size: 36),
                            const SizedBox(width: 10),
                          ] else ...[
                            Container(width: 8, height: 8,
                                decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_activeOrderStatusLabel(locale),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                                if (_activeOrder!['driver'] != null)
                                  Text(
                                    (_activeOrder!['driver'] as Map<String, dynamic>)['fullName'] as String? ?? '',
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.primaryColor),
                        ]),
                      ),
                    ),
                  ] else if (_searching && _pendingOrder != null) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 34, height: 34,
                          child: AppLoadingIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(AppStrings.get('searching_driver', locale),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                              const SizedBox(height: 2),
                              Text(
                                '${AddressHelper.shorten(_fromPlace?.name ?? '')} → ${AddressHelper.shorten(_toPlace?.name ?? '')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelSearching,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(color: border),
                              foregroundColor: textSecondary,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(AppStrings.get('cancel_search', locale), maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showSearchOrderDetails(_pendingOrder!),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: const BorderSide(color: AppTheme.primaryColor),
                              foregroundColor: AppTheme.primaryColor,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(AppStrings.get('order_details', locale), maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_fromPlace != null && _toPlace != null) ...[
                    GestureDetector(
                      onTap: _startOrderFlow,
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
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(color: border),
                              foregroundColor: textSecondary,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                AppStrings.get('cancel_selection', locale),
                                maxLines: 1,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _GradBtn(label: AppStrings.get('place_order', locale), onTap: _startOrderFlow),
                        ),
                      ],
                    ),
                  ] else
                    _GradBtn(label: AppStrings.get('enter_address', locale), onTap: _startOrderFlow),
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

  // Haydovchi qidirilayotgan holat — endi modal emas, ClientHomeScreen
  // ning o'zida (xarita fonida) doimiy pastki panel sifatida ko'rsatiladi,
  // build() metodidagi "_searching && _pendingOrder != null" bo'limiga qarang.
  void _showSearching(Map<String, dynamic> order) {
    setState(() { _searching = true; _pendingOrder = order; });
    _centerOnPickupForSearch();

    _orderTimer?.cancel();
    _orderTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final orders = await ref.read(clientRepositoryProvider).getOrders();
        if (orders.isNotEmpty) {
          final latest = orders.first;
          final status = latest['status'] as String;
          if (['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) {
            _orderTimer?.cancel();
            setState(() { _activeOrder = latest; _searching = false; _pendingOrder = null; });
            _syncActiveOrderProvider();
            if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            _startTrackingLoop();
            _openActiveOrderDetailsPage();
          } else if (status == 'CANCELLED') {
            _orderTimer?.cancel();
            setState(() { _searching = false; _pendingOrder = null; });
          }
        }
      } catch (_) {}
    });
  }

  void _cancelSearching() {
    _orderTimer?.cancel();
    setState(() { _searching = false; _pendingOrder = null; });
  }

  void _showSearchOrderDetails(Map<String, dynamic> order) {
    final isDark = _isDark;
    final locale = ref.read(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    final truckType = order['truckType'] as String? ?? '';
    final weight = order['weight'];
    final price = (order['price'] as num?) ?? 0;
    final note = order['note'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(AppStrings.get('order_details', locale),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 14),
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

  // Aktiv buyurtmaning to'liq tafsilotlar sahifasi — pastdagi kichik
  // doimiy panel bosilganda ochiladi. Sahifa true bilan yopilsa (baholab
  // yakunlangan), tracking to'xtatilib, holat tozalanadi — xuddi avvalgi
  // _ActiveOrderSheet dagi onComplete callback qanday ishlagan bo'lsa shunday.
  // Home ekrandagi _activeOrder o'zgarganda, shu holatni umumiy
  // activeOrderProvider ga ham yozib qo'yadi — Menu (toggle) bottom sheet
  // Home ekranning private state'iga bevosita kira olmagani uchun, "Faol
  // buyurtma" bandini shu provider orqali ko'rsatadi.
  void _syncActiveOrderProvider() {
    ref.read(activeOrderProvider.notifier).state = _activeOrder != null
        ? ActiveOrderInfo(order: _activeOrder!, distKm: _driverEtaKm, timeMin: _driverEtaMin)
        : null;
  }

  Future<void> _openActiveOrderDetailsPage() async {
    if (_activeOrder == null) return;
    final completed = await context.push<bool>(
      AppRoutes.clientActiveOrderDetails,
      extra: {
        'order': _activeOrder,
        'distKm': _driverEtaKm,
        'timeMin': _driverEtaMin,
      },
    );
    if (completed == true && mounted) {
      _trackingTimer?.cancel();
      setState(() {
        _activeOrder = null; _fromPlace = null; _toPlace = null;
        _driverEtaKm = null; _driverEtaMin = null;
      });
      _syncActiveOrderProvider();
      _rebuildMapObjects();
    }
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

// ===== HELPERS =====
class _RadarPulse extends StatefulWidget {
  const _RadarPulse();

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _ring(double delay) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final t = (_ctrl.value + delay) % 1.0;
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0) * 0.55,
          child: Transform.scale(
            scale: 0.3 + t * 1.7,
            child: Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryColor, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140, height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(0),
          _ring(0.33),
          _ring(0.66),
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6)],
            ),
          ),
        ],
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

class _GradBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _GradBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 50,
        decoration: BoxDecoration(
          gradient: enabled ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight) : null,
          color: enabled ? null : Colors.grey.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}