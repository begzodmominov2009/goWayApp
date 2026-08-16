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
import '../../../../core/network/notification_repository.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/place.dart';
import '../../../../shared/widgets/driver_avatar.dart';
import '../../../../core/providers/active_order_provider.dart';
import '../widgets/client_menu_sheet.dart';
import '../../order/widgets/order_form_modal.dart';
import '../../order/screens/order_progress_screen.dart';

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

  double _fromLat = 41.2995;
  double _fromLng = 69.2401;

  Map<String, dynamic>? _activeOrder;
  Timer? _trackingTimer;

  double? _driverEtaKm;
  int? _driverEtaMin;

  List<MapObject> _mapObjects = [];

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
    }
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
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

  void _rebuildMapObjects() {
    final objects = <MapObject>[];

    if (_myLocationIcon != null && _activeOrder == null) {
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

  Future<void> _startOrderFlow() async {
    final result = await showOrderFormModal(
      context,
      initialFrom: null,
      initialTo: null,
      fromLat: _fromLat,
      fromLng: _fromLng,
    );
    if (result == null || !mounted) return;
    final progressResult = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => OrderProgressScreen(
          fromPlace: result['fromPlace'] as Place,
          toPlace: result['toPlace'] as Place,
          truckType: result['truckType'] as String,
          weight: result['weight'] as double,
          loadType: result['loadType'] as String?,
          cargoType: result['cargoType'] as String?,
          note: result['note'] as String?,
          isScheduled: result['isScheduled'] as bool,
          scheduledFor: result['scheduledFor'] as DateTime?,
          distKm: result['distKm'] as double?,
          timeMin: result['timeMin'] as int?,
        ),
      ),
    );
    // OrderProgressScreen ActiveOrderDetailsScreen'ga o'tib, u yerdan
    // pop(true) bilan qaytishi mumkin (baholab yakunlangach) — bu holda
    // aktiv buyurtma holatini yangilaymiz.
    if (progressResult == true && mounted) {
      _checkActiveOrderOnStart();
    }
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
        setState(() => _activeOrder = null);
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
    final showDestinationBtn = _activeOrder != null;
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
              },
              mapObjects: _mapObjects,
            ),
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
                          child: Container(
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
                        ),
                        const SizedBox(width: 10),
                        // Joriy manzil — Yandex Go uslubida: kartochka/tugma
                        // emas, xarita ustida o'qilishi uchun juda yengil
                        // fon bilan sof matn. Bosilganda hech narsa
                        // bo'lmaydi (gesture handleri yo'q).
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: surface.withOpacity(isDark ? 0.55 : 0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 15),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    _currentAddressLabel.isNotEmpty ? _currentAddressLabel : 'GoWay',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () async {
                            await context.push(AppRoutes.notifications);
                            if (mounted) _loadUnreadNotifCount();
                          },
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
                                child: Icon(Icons.notifications_outlined, color: textPrimary, size: 22),
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
                                      _unreadNotifCount > 99 ? '99+' : '$_unreadNotifCount',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                            ],
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
        _activeOrder = null;
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