import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/network/notification_repository.dart';
import '../../../../core/network/rating_repository.dart';
import '../../../../core/network/sos_repository.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/rating_dialog.dart';
import '../../../../shared/widgets/tutorial_sheet.dart';
import '../widgets/driver_menu_sheet.dart';

const double _kMinZoom = 3.0;
const double _kMaxZoom = 20.0;

// Heading-up navigatsiyada, kamera markazini driver joylashuvidan biroz
// oldinga (yo'l yo'nalishi bo'yicha) siljitish uchun — natijada driver
// ekran markazidan pastroqda, yo'lning oldingi qismi esa tepada ko'proq
// ko'rinadi (Yandex/Google Maps navigatsiyasidagi standart uslub).
// CameraPosition (newCameraPosition) uchun focusRect parametri
// YandexMapKit'da mavjud emas (faqat newGeometry/newBounds kabi "bounds"
// operatsiyalarida bor), shuning uchun kamera nishonini shu masofaga
// siljitib hisoblaymiz.
const double _kNavForwardOffsetMeters = 70.0;

// Berilgan nuqtadan bearing yo'nalishi bo'yicha distanceMeters masofaga
// siljigan yangi geografik nuqtani hisoblaydi (destination point formula).
Point _offsetPoint(double lat, double lng, double bearingDeg, double distanceMeters) {
  const earthRadius = 6371000.0;
  final bearingRad = bearingDeg * (math.pi / 180);
  final latRad = lat * (math.pi / 180);
  final lngRad = lng * (math.pi / 180);
  final angularDistance = distanceMeters / earthRadius;

  final newLatRad = math.asin(
    math.sin(latRad) * math.cos(angularDistance) +
        math.cos(latRad) * math.sin(angularDistance) * math.cos(bearingRad),
  );
  final newLngRad = lngRad +
      math.atan2(
        math.sin(bearingRad) * math.sin(angularDistance) * math.cos(latRad),
        math.cos(angularDistance) - math.sin(latRad) * math.sin(newLatRad),
      );

  return Point(latitude: newLatRad * (180 / math.pi), longitude: newLngRad * (180 / math.pi));
}

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

// Ikki koordinata orasidagi kompas yo'nalishini (0-360 gradus) hisoblaydi.
double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = (lon2 - lon1) * (math.pi / 180);
  final lat1Rad = lat1 * (math.pi / 180);
  final lat2Rad = lat2 * (math.pi / 180);
  final y = math.sin(dLon) * math.cos(lat2Rad);
  final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
      math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
  final bearing = math.atan2(y, x) * (180 / math.pi);
  return (bearing + 360) % 360;
}

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> with RouteAware, WidgetsBindingObserver {
  YandexMapController? _mapController;
  bool _isDark = false;
  bool _tiltOn = false;
  double _currentZoom = 14;
  double _currentBearing = 0;
  bool _showTopPanel = true;
  String _currentAddressLabel = '';

  // Foydalanuvchi xaritani qo'lda oxirgi marta qachon harakatlantirganini
  // saqlaydi — dasturiy kamera surish (_followCamera) shu bilan
  // to'qnashib, gesture'ni "qotib qolgandek" his qildirmasligi uchun.
  DateTime? _lastUserGestureAt;

  bool get _recentlyGestured =>
      _lastUserGestureAt != null && DateTime.now().difference(_lastUserGestureAt!) < const Duration(seconds: 3);

  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _finishIcon;
  BitmapDescriptor? _myLocationIcon;

  bool _isOnline = false;
  bool _onlineLoading = false;
  Position? _currentPosition;
  Timer? _locationTimer;
  bool _gpsServiceWasEnabled = true;
  Timer? _offerTimer;
  Timer? _trackingTimer;

  bool _hasOrder = false;
  Map<String, dynamic>? _currentOrder;
  String? _currentOfferId;

  Map<String, dynamic>? _activeOrder;
  double? _routeDistKm;
  int? _routeTimeMin;
  double? _initialDistanceKm;
  List<Point>? _savedRoutePoints;
  List<Map<String, dynamic>> _currentSteps = [];
  int _currentStepIndex = 0;
  double _currentStepRemainingMeters = 0;
  final ValueNotifier<List<MapObject>> _mapObjectsNotifier = ValueNotifier([]);
  bool _activeSheetExpanded = false;

  final FlutterTts _tts = FlutterTts();
  int? _lastAnnouncedStepIndex;
  bool _announced250 = false;
  bool _announced50 = false;
  bool _announcedTurnPoint = false;
  String? _ttsLastLocale;

  int _unreadNotifCount = 0;
  Timer? _notifCountTimer;

  double get _routeProgress {
    final initial = _initialDistanceKm;
    final current = _routeDistKm;
    if (initial == null || current == null || initial <= 0) return 0.0;
    return (1 - (current / initial)).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadIcons();
    _initLocation();
    _syncOnlineStatus();
    _checkActiveOrderOnStart();
    _loadUnreadNotifCount();
    _notifCountTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadUnreadNotifCount());
    _maybeShowHomeTutorial();
    _initSocket();
  }

  // Socket ulanishi — offer va notification'lar uchun tezkor (real-time)
  // yo'l. REST polling (_startOfferPolling, _notifCountTimer) zaxira
  // sifatida davom etadi, shuning uchun socket ulanmasa yoki xato bersa
  // ham ilova buzilmaydi.
  Future<void> _initSocket() async {
    try {
      await ref.read(socketServiceProvider).connect();
      if (!mounted) return;
      ref.read(socketServiceProvider).onNewOffer((offer) {
        if (!mounted || !_isOnline || _hasOrder || _activeOrder != null) return;
        setState(() {
          _currentOfferId = offer['offerId'] as String;
          _currentOrder = {
            'id': offer['orderId'],
            'fromCity': offer['fromCity'],
            'toCity': offer['toCity'],
            'price': offer['price'],
            'truckType': offer['truckType'],
            'weight': offer['weight'],
          };
          _hasOrder = true;
        });
      });
      ref.read(socketServiceProvider).onNotification((data) {
        if (!mounted) return;
        _loadUnreadNotifCount();
      });
    } catch (_) {}
  }

  Future<void> _maybeShowHomeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seen_home_tutorial') == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showHomeTutorial();
    });
    await prefs.setBool('seen_home_tutorial', true);
  }

  void _showHomeTutorial() {
    final locale = ref.read(localeProvider).languageCode;
    showTutorialSheet(
      context,
      title: AppStrings.get('tutorial_home_title', locale),
      bullets: [
        AppStrings.get('tutorial_home_1', locale),
        AppStrings.get('tutorial_home_2', locale),
        AppStrings.get('tutorial_home_3', locale),
        AppStrings.get('tutorial_home_4', locale),
      ],
      icon: Icons.explore_outlined,
      locale: locale,
    );
  }

  Future<void> _loadUnreadNotifCount() async {
    try {
      final count = await ref.read(notificationRepositoryProvider).getUnreadCount();
      if (mounted) setState(() => _unreadNotifCount = count);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncOnlineStatus();
  }

  // Backend'dagi haqiqiy online holatini o'qib, mahalliy _isOnline
  // state'ini sinxronlaydi (masalan, boshqa qurilmadan yoki sessiya
  // tugashi sabab backend offline bo'lib qolgan bo'lishi mumkin).
  Future<void> _syncOnlineStatus() async {
    try {
      final profile = await ref.read(driverRepositoryProvider).getProfile();
      final backendOnline = profile['isOnline'] == true;
      if (!mounted || backendOnline == _isOnline) return;
      final wentAutoOffline = _isOnline && !backendOnline;
      setState(() {
        _isOnline = backendOnline;
        if (!_isOnline) {
          _hasOrder = false;
          _currentOrder = null;
          _currentOfferId = null;
          _offerTimer?.cancel();
        }
      });
      if (_isOnline) _startOfferPolling();
      if (wentAutoOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('auto_offline_notice', ref.read(localeProvider).languageCode)),
            backgroundColor: AppTheme.warningColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (_) {}
  }

  // O'zini-o'zi tekshirish: backend'da driverga ACCEPTED (yoki keyingi
  // bosqich) holatida biriktirilgan buyurtma bo'lsa-yu, ilova hali
  // "bo'sh/qidiruv" holatida tursa (masalan ilova qayta ochilganda yoki
  // tarmoq/holat nomuvofiqligi natijasida) — ilova holatini shu buyurtmaga
  // moslab, xuddi hozirgina qabul qilingandek davom ettiradi. Backend'da
  // dedicated "/driver/active-order" endpointi yo'q, shuning uchun driverga
  // biriktirilgan buyurtmalar ro'yxatining (eng yangisi birinchi) birinchi
  // elementi va uning status'i orqali aniqlanadi — xuddi client tomonidagi
  // ClientHomeScreen._checkActiveOrderOnStart() bilan bir xil naqsh.
  // Hech qanday bildirishnoma ko'rsatilmaydi — muvofiqlik jimgina tiklanadi.
  Future<void> _checkActiveOrderOnStart() async {
    try {
      final orders = await ref.read(driverRepositoryProvider).getDriverOrders();
      if (orders.isEmpty || !mounted) return;
      if (_activeOrder != null || _hasOrder) return;
      final latest = orders.first;
      final status = latest['status'] as String? ?? '';
      if (!['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status)) return;

      setState(() {
        _hasOrder = false;
        _currentOrder = null;
        _currentOfferId = null;
        _activeOrder = latest;
        _initialDistanceKm = null;
        _savedRoutePoints = null;
        _activeSheetExpanded = false;
      });
      _restartLocationTimer();

      await _updateTracking(fitToBounds: true);
      _trackingTimer?.cancel();
      _trackingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _updateTracking());
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newDark = Theme.of(context).brightness == Brightness.dark;
    if (newDark != _isDark) {
      _isDark = newDark;
      if (_activeOrder != null) _updateTracking();
    }
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _locationTimer?.cancel();
    _offerTimer?.cancel();
    _trackingTimer?.cancel();
    _notifCountTimer?.cancel();
    _mapObjectsNotifier.dispose();
    ref.read(socketServiceProvider).disconnect();
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
      _updateMyLocationPin();
      return;
    }
    await MapIconHelper.preloadAll();
    if (!mounted) return;
    setState(() {
      _truckIcon = MapIconHelper.truckIconReady;
      _finishIcon = MapIconHelper.finishIconReady;
      _myLocationIcon = MapIconHelper.myLocationIconReady;
    });
    _updateMyLocationPin();
  }

  void _updateMyLocationPin() {
    if (_myLocationIcon == null || _currentPosition == null || _activeOrder != null) return;
    _mapObjectsNotifier.value = [
      PlacemarkMapObject(
        mapId: const MapObjectId('my_location'),
        point: Point(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude),
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: _myLocationIcon!, scale: 0.18, anchor: const Offset(0.5, 0.5),
        )),
      ),
    ];
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) _showLocationDeniedNotice();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) _showLocationDeniedNotice();
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = position);
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: Point(latitude: position.latitude, longitude: position.longitude), zoom: 14),
        ),
      );
      _updateMyLocationPin();

      final repo = ref.read(geocodeRepositoryProvider);
      final result = await repo.reverse(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentAddressLabel = result.fullAddr.isNotEmpty
              ? AddressHelper.shorten(result.fullAddr)
              : result.city;
        });
      }

      _restartLocationTimer();
    } catch (_) {}
  }

  void _restartLocationTimer() {
    _locationTimer?.cancel();
    final interval = _activeOrder != null
        ? const Duration(seconds: 4)
        : const Duration(seconds: 16);
    _locationTimer = Timer.periodic(interval, (_) async {
      if (!_isOnline) return;
      try {
        final gpsServiceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!gpsServiceEnabled) {
          if (_gpsServiceWasEnabled && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.get('gps_service_disabled_notice', ref.read(localeProvider).languageCode)),
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
          _gpsServiceWasEnabled = false;
          return;
        }
        _gpsServiceWasEnabled = true;
        final pos = await Geolocator.getCurrentPosition();
        if (!mounted) return;
        final prevPosition = _currentPosition;
        if (prevPosition != null) {
          final movedMeters = Geolocator.distanceBetween(
            prevPosition.latitude, prevPosition.longitude, pos.latitude, pos.longitude,
          );
          if (movedMeters > 5) {
            _currentBearing = _calculateBearing(
              prevPosition.latitude, prevPosition.longitude, pos.latitude, pos.longitude,
            );
          }
        }
        _currentPosition = pos;
        await ref.read(driverRepositoryProvider).updateLocation(pos.latitude, pos.longitude);
        ref.read(socketServiceProvider).sendLocation(pos.latitude, pos.longitude);
        if (_activeOrder != null) {
          _updateTracking();
          if (_savedRoutePoints != null && _currentSteps.isNotEmpty) {
            final traveled = _distanceAlongPolyline(
              Point(latitude: pos.latitude, longitude: pos.longitude),
              _savedRoutePoints!,
            );
           final info = _stepInfoForDistance(traveled);
            final stepChanged = info.stepIndex != _currentStepIndex;
            if (mounted && (stepChanged || info.remainingMeters != _currentStepRemainingMeters)) {
              setState(() {
                _currentStepIndex = info.stepIndex;
                _currentStepRemainingMeters = info.remainingMeters;
              });
            }
            if (stepChanged) {
              unawaited(_announceStraightSegment(info.stepIndex));
            }
            unawaited(_announceNavigation(info.stepIndex, info.remainingMeters));
          }
        } else {
          _updateMyLocationPin();
        }
      } catch (_) {}
    });
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
    if (_activeOrder == null) return;
    final status = _activeOrder!['status'] as String;
    final isPickup = _isPickupPhase(status);
    final lat = isPickup
        ? (_activeOrder!['fromLatitude'] as num).toDouble()
        : (_activeOrder!['toLatitude'] as num).toDouble();
    final lng = isPickup
        ? (_activeOrder!['fromLongitude'] as num).toDouble()
        : (_activeOrder!['toLongitude'] as num).toDouble();
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: Point(latitude: lat, longitude: lng), zoom: 15)),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
    );
  }

  void _toggleTilt() {
    if (_currentPosition == null) return;
    setState(() => _tiltOn = !_tiltOn);
    final target = _offsetPoint(
      _currentPosition!.latitude, _currentPosition!.longitude, _currentBearing, _kNavForwardOffsetMeters,
    );
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: _currentZoom,
          tilt: _tiltOn ? 45 : 0,
          azimuth: _currentBearing,
        ),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.4),
    );
  }

  // Driver harakat yo'nalishiga (bearing) qarab kamerani, joriy zoom
  // darajasini saqlagan holda, yangi joylashuvga siljitadi (heading-up).
  // Kamera nishoni driver joylashuvidan bearing bo'yicha biroz oldinga
  // siljitiladi — natijada driver ekran markazidan pastroqda ko'rinadi.
  void _followCamera(double lat, double lng) {
    if (_recentlyGestured) return;
    final target = _offsetPoint(lat, lng, _currentBearing, _kNavForwardOffsetMeters);
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: _currentZoom,
          tilt: _tiltOn ? 45 : 0,
          azimuth: _currentBearing,
        ),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.8),
    );
  }

  void _zoomBy(double delta) {
    final newZoom = (_currentZoom + delta).clamp(_kMinZoom, _kMaxZoom);
    _mapController?.moveCamera(
      CameraUpdate.zoomTo(newZoom),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.25),
    );
  }

  Future<void> _toggleOnline() async {
    if (_onlineLoading) return;
    setState(() => _onlineLoading = true);
    try {
      await ref.read(driverRepositoryProvider).setOnline(!_isOnline);
      setState(() {
        _isOnline = !_isOnline;
        if (!_isOnline) {
          _hasOrder = false;
          _currentOrder = null;
          _currentOfferId = null;
          _offerTimer?.cancel();
        }
      });
      if (_isOnline) _startOfferPolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('generic_error', ref.read(localeProvider).languageCode)}: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) setState(() => _onlineLoading = false);
    }
  }

  void _startOfferPolling() {
    _offerTimer?.cancel();
    _offerTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_isOnline || _hasOrder || _activeOrder != null) return;
      try {
        final offers = await ref.read(driverRepositoryProvider).getOffers();
        if (offers.isNotEmpty && mounted && !_hasOrder) {
          final offer = offers.first;
          setState(() {
            _currentOfferId = offer['id'] as String;
            _currentOrder = Map<String, dynamic>.from(offer['order'] as Map);
            _hasOrder = true;
          });
        }
      } catch (_) {}
    });
  }

  bool _isPickupPhase(String status) => status == 'ACCEPTED' || status == 'DRIVER_ARRIVING';

  // Nuqta va segment (a-b oralig'i) orasidagi taxminiy masofa — segment
  // boshi/oxiriga bo'lgan eng yaqin masofani oladi (aniq perpendikulyar
  // masofa emas, lekin amaliy jihatdan yetarli aniqlikda ishlaydi).
  double _distanceToSegment(Point p, Point a, Point b) {
    final d1 = Geolocator.distanceBetween(p.latitude, p.longitude, a.latitude, a.longitude);
    final d2 = Geolocator.distanceBetween(p.latitude, p.longitude, b.latitude, b.longitude);
    return d1 < d2 ? d1 : d2;
  }

  double _distanceToPolyline(Point point, List<Point> polyline) {
    if (polyline.isEmpty) return double.infinity;
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final segStart = polyline[i];
      final segEnd = polyline[i + 1];
      final dist = _distanceToSegment(point, segStart, segEnd);
      if (dist < minDistance) minDistance = dist;
    }
    return minDistance;
  }

  // Driverning marshrut bo'ylab necha metr bosib o'tganini topadi: eng
  // yaqin segmentni (_distanceToPolyline bilan bir xil mantiq) aniqlab,
  // marshrut boshidan o'sha segmentgacha bo'lgan masofalarni yig'indilaydi.
  double _distanceAlongPolyline(Point point, List<Point> polyline) {
    if (polyline.length < 2) return 0;
    int bestIndex = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final dist = _distanceToSegment(point, polyline[i], polyline[i + 1]);
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    double traveled = 0;
    for (int i = 0; i < bestIndex; i++) {
      traveled += Geolocator.distanceBetween(
        polyline[i].latitude, polyline[i].longitude,
        polyline[i + 1].latitude, polyline[i + 1].longitude,
      );
    }
    traveled += Geolocator.distanceBetween(
      polyline[bestIndex].latitude, polyline[bestIndex].longitude,
      point.latitude, point.longitude,
    );
    return traveled;
  }

// Driver bosib o'tgan masofaga qarab, HOZIRGI step ichida qolgan
  // (keyingi burilishgacha bo'lgan) masofani, va o'sha KEYINGI step'ning
  // ko'rsatmasini birga qaytaradi — masalan "150m dan keyin o'ngga
  // buriling" kabi, OLDINDAN ogohlantirish uchun.
  ({int stepIndex, double remainingMeters}) _stepInfoForDistance(double traveledMeters) {
    double cumulative = 0;
    for (int i = 0; i < _currentSteps.length; i++) {
      final stepDist = (_currentSteps[i]['distanceMeters'] as num?)?.toDouble() ?? 0;
      final stepEnd = cumulative + stepDist;
      if (traveledMeters < stepEnd) {
        final remaining = stepEnd - traveledMeters;
        final nextStepIdx = (i + 1 < _currentSteps.length) ? i + 1 : i;
        return (stepIndex: nextStepIdx, remainingMeters: remaining);
      }
      cumulative = stepEnd;
    }
    final lastIdx = _currentSteps.isEmpty ? 0 : _currentSteps.length - 1;
    return (stepIndex: lastIdx, remainingMeters: 0);
  }

  // TTS ovoz tilini, ilova joriy tiliga mos DINAMIK sozlaydi (faqat til
  // o'zgarganda yoki birinchi ishlatishda amalga oshiriladi).
  Future<void> _configureTtsForLocale(String locale) async {
    if (_ttsLastLocale == locale) return;
    _ttsLastLocale = locale;

    String ttsLanguage;
    switch (locale) {
      case 'ru':
        ttsLanguage = 'ru-RU';
        break;
      case 'en':
        ttsLanguage = 'en-US';
        break;
      default:
        ttsLanguage = 'uz-UZ';
    }

    try {
      // Avval, so'ralgan tilni sinab ko'r. Agar telefon TTS mexanizmi
      // shu tilni QO'LLAB-QUVVATLAMASA (masalan uz-UZ ba'zi qurilmalarda
      // yo'q bo'lishi mumkin), inglizchaga zaxira qilamiz.
      final isAvailable = await _tts.isLanguageAvailable(ttsLanguage);
      await _tts.setLanguage(isAvailable == true ? ttsLanguage : 'en-US');

      // Ayol ovozini tanlash — mavjud ovozlar ro'yxatidan, "female" so'zi
      // bor yoki standart ayol ovozi hisoblangan birini tanlashga harakat
      // qilamiz. Agar aniq topib bo'lmasa, standart ovozda qoldiramiz
      // (xato bermaydi, faqat ayol ovozi kafolatlanmaydi).
      try {
        final voices = await _tts.getVoices as List?;
        if (voices != null) {
          final femaleVoice = voices.firstWhere(
            (v) =>
                (v['locale']?.toString().startsWith(ttsLanguage.split('-')[0]) ?? false) &&
                (v['name']?.toString().toLowerCase().contains('female') ?? false),
            orElse: () => null,
          );
          if (femaleVoice != null) {
            await _tts.setVoice({'name': femaleVoice['name'], 'locale': femaleVoice['locale']});
          }
        }
      } catch (_) {}

      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.1); // Biroz balandroq pitch, ayol ovoziga yaqinroq
    } catch (_) {}
  }

  Future<void> _announceNavigation(int stepIndex, double remainingMeters) async {
    if (_currentSteps.isEmpty || stepIndex >= _currentSteps.length) return;
    final locale = ref.read(localeProvider).languageCode;
    await _configureTtsForLocale(locale);

    final instruction = (_currentSteps[stepIndex]['instruction'] as String? ?? '').toLowerCase();

    String direction;
    if (instruction.contains('left')) {
      direction = AppStrings.get('voice_turn_left', locale);
    } else if (instruction.contains('right')) {
      direction = AppStrings.get('voice_turn_right', locale);
    } else {
      direction = AppStrings.get('voice_continue', locale);
    }

    if (_lastAnnouncedStepIndex != stepIndex) {
      _lastAnnouncedStepIndex = stepIndex;
      _announced250 = false;
      _announced50 = false;
      _announcedTurnPoint = false;
    }

    try {
      if (remainingMeters <= 20 && !_announcedTurnPoint) {
        _announcedTurnPoint = true;
        await _tts.speak(direction);
      } else if (remainingMeters <= 50 && remainingMeters > 20 && !_announced50) {
        _announced50 = true;
        final text = AppStrings.get('voice_distance_then_turn', locale)
            .replaceAll('{dist}', '50')
            .replaceAll('{direction}', direction);
        await _tts.speak(text);
      } else if (remainingMeters <= 250 && remainingMeters > 50 && !_announced250) {
        _announced250 = true;
        final text = AppStrings.get('voice_distance_then_turn', locale)
            .replaceAll('{dist}', '250')
            .replaceAll('{direction}', direction);
        await _tts.speak(text);
      }
    } catch (_) {}
  }

  Future<void> _announceStraightSegment(int stepIndex) async {
    if (_currentSteps.isEmpty || stepIndex >= _currentSteps.length) return;
    final stepDist = (_currentSteps[stepIndex]['distanceMeters'] as num?)?.toDouble() ?? 0;
    if (stepDist < 500) return;

    final locale = ref.read(localeProvider).languageCode;
    await _configureTtsForLocale(locale);

    final km = stepDist / 1000;
    final distText = km >= 1
        ? '${km.toStringAsFixed(1)} km'
        : '${stepDist.round()} m';
    final text = AppStrings.get('voice_go_straight', locale).replaceAll('{dist}', distText);
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  List<MapObject> _buildTrackingMapObjects({
    required List<Point> points,
    required double driverLat,
    required double driverLng,
    required double targetLat,
    required double targetLng,
    required bool isPickup,
  }) {
    return [
      PolylineMapObject(
        mapId: const MapObjectId('driver_route'),
        polyline: Polyline(points: points),
        strokeColor: isPickup
            ? (_isDark ? const Color(0xFF60A5FA) : const Color(0xFF1e3a8a))
            : (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
        strokeWidth: 5,
      ),
      if (_truckIcon != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('driver_pos'),
          point: Point(latitude: driverLat, longitude: driverLng),
          // rotationType.noRotation — truck belgisi kamera (xarita) bilan
          // birga AYLANMAYDI, ekranga nisbatan doim tepaga qarab turadi
          // (heading-up navigatsiya uslubi, YandexMapKit standart qiymati
          // ham shu, lekin bu yerda niyatni aniq ko'rsatish uchun yozilgan).
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: _truckIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
            rotationType: RotationType.noRotation,
          )),
        ),
      if (_finishIcon != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('target_pos'),
          point: Point(latitude: targetLat, longitude: targetLng),
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: _finishIcon!, scale: 0.17, anchor: const Offset(0.5, 1.0),
          )),
        ),
    ];
  }

  Future<void> _updateTracking({bool fitToBounds = false}) async {
    if (_activeOrder == null || _currentPosition == null) return;
    final status = _activeOrder!['status'] as String;
    final isPickup = _isPickupPhase(status);

    final targetLat = isPickup
        ? (_activeOrder!['fromLatitude'] as num).toDouble()
        : (_activeOrder!['toLatitude'] as num).toDouble();
    final targetLng = isPickup
        ? (_activeOrder!['fromLongitude'] as num).toDouble()
        : (_activeOrder!['toLongitude'] as num).toDouble();

    final driverLat = _currentPosition!.latitude;
    final driverLng = _currentPosition!.longitude;
    final driverPoint = Point(latitude: driverLat, longitude: driverLng);

    final needsFreshRoute = _savedRoutePoints == null ||
        _distanceToPolyline(driverPoint, _savedRoutePoints!) > 150;

    List<Point> points;

    if (needsFreshRoute) {
      final repo = ref.read(geocodeRepositoryProvider);
      final route = await repo.getRoute(fromLat: driverLat, fromLng: driverLng, toLat: targetLat, toLng: targetLng);

      if (!mounted) return;

      points = route?.points
              .map((c) => Point(latitude: c[0], longitude: c[1]))
              .toList() ??
          [
            driverPoint,
            Point(latitude: targetLat, longitude: targetLng),
          ];
      _savedRoutePoints = points;

      final orderId = _activeOrder!['id'] as String;
      unawaited(
        ref.read(driverRepositoryProvider).updateOrderRoute(
              orderId,
              points.map((p) => [p.latitude, p.longitude]).toList(),
              distanceKm: _routeDistKm,
              durationMin: _routeTimeMin,
            ).catchError((_) {}),
      );

      setState(() {
        _routeDistKm = route?.distanceKm;
        _routeTimeMin = route?.durationMin;
        _initialDistanceKm ??= route?.distanceKm;
        _currentSteps = route?.steps ?? [];
        _currentStepIndex = 0;
      });
      _mapObjectsNotifier.value = _buildTrackingMapObjects(
        points: points,
        driverLat: driverLat,
        driverLng: driverLng,
        targetLat: targetLat,
        targetLng: targetLng,
        isPickup: isPickup,
      );
    } else {
      points = _savedRoutePoints!;
      _mapObjectsNotifier.value = _buildTrackingMapObjects(
        points: points,
        driverLat: driverLat,
        driverLng: driverLng,
        targetLat: targetLat,
        targetLng: targetLng,
        isPickup: isPickup,
      );
    }

    if (fitToBounds) {
      _fitBounds(points);
    } else {
      _followCamera(driverLat, driverLng);
    }
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

  Future<void> _onAccept() async {
    if (_currentOfferId == null) return;
    try {
      await ref.read(driverRepositoryProvider).acceptOffer(_currentOfferId!);
      final acceptedOrder = Map<String, dynamic>.from(_currentOrder!);
      acceptedOrder['status'] = 'ACCEPTED';

      setState(() {
        _hasOrder = false;
        _currentOrder = null;
        _currentOfferId = null;
        _activeOrder = acceptedOrder;
        _initialDistanceKm = null;
        _savedRoutePoints = null;
        _activeSheetExpanded = false;
      });
      _restartLocationTimer();

      await _updateTracking(fitToBounds: true);
      _trackingTimer?.cancel();
      _trackingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _updateTracking());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('generic_error', ref.read(localeProvider).languageCode)}: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _onReject() async {
    if (_currentOfferId == null) return;
    try {
      await ref.read(driverRepositoryProvider).rejectOffer(_currentOfferId!);
    } catch (_) {}
    setState(() { _hasOrder = false; _currentOrder = null; _currentOfferId = null; });
  }

  Future<void> _onAdvance() async {
    if (_activeOrder == null) return;
    final orderId = _activeOrder!['id'] as String;
    final status = _activeOrder!['status'] as String;
    final isPickup = _isPickupPhase(status);
    final nextStatus = isPickup ? 'IN_TRANSIT' : 'COMPLETED';

    try {
      await ref.read(driverRepositoryProvider).updateOrderStatus(orderId, nextStatus);
      if (!mounted) return;

      if (nextStatus == 'COMPLETED') {
        _trackingTimer?.cancel();
        setState(() {
          _activeOrder = null;
          _routeDistKm = null;
          _routeTimeMin = null;
          _initialDistanceKm = null;
          _activeSheetExpanded = false;
        });
        _mapObjectsNotifier.value = [];
        _restartLocationTimer();
        _updateMyLocationPin();
        if (_isOnline) _startOfferPolling();
      } else {
        setState(() {
          _activeOrder!['status'] = nextStatus;
          _initialDistanceKm = null;
          _savedRoutePoints = null;
        });
        await _updateTracking(fitToBounds: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('generic_error', ref.read(localeProvider).languageCode)}: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // Driver buyurtmani bekor qilganda (faqat yuk olinmagan bosqichda) —
  // aktiv buyurtmani tozalab, qayta taklif kutish holatiga qaytaramiz.
  void _clearActiveOrder() {
    _trackingTimer?.cancel();
    setState(() {
      _activeOrder = null;
      _routeDistKm = null;
      _routeTimeMin = null;
      _initialDistanceKm = null;
      _savedRoutePoints = null;
      _activeSheetExpanded = false;
    });
    _mapObjectsNotifier.value = [];
    _restartLocationTimer();
    _updateMyLocationPin();
    if (_isOnline) _startOfferPolling();
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => const DriverMenuSheet(),
    );
  }

  int get _zoomPercent =>
      (((_currentZoom - _kMinZoom) / (_kMaxZoom - _kMinZoom)) * 100).round().clamp(0, 100);

  String _trafficLabel(String locale) {
    if (_routeDistKm == null || _routeTimeMin == null || _routeTimeMin == 0) {
      return AppStrings.get('traffic_light', locale);
    }
    final speedKmh = _routeDistKm! / (_routeTimeMin! / 60.0);
    if (speedKmh >= 35) return AppStrings.get('traffic_light', locale);
    if (speedKmh >= 18) return AppStrings.get('traffic_moderate', locale);
    return AppStrings.get('traffic_heavy', locale);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final surface = _isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = _isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = _isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<List<MapObject>>(
              valueListenable: _mapObjectsNotifier,
              builder: (context, mapObjects, _) => YandexMap(
                nightModeEnabled: _isDark,
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (_currentPosition != null) {
                    controller.moveCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: Point(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude),
                          zoom: 14,
                        ),
                      ),
                    );
                  }
                },
                onCameraPositionChanged: (pos, reason, finished) {
                  if (reason == CameraUpdateReason.gestures) {
                    _lastUserGestureAt = DateTime.now();
                  }
                  if (finished && (pos.zoom - _currentZoom).abs() > 0.05) {
                    setState(() => _currentZoom = pos.zoom);
                  }
                },
                mapObjects: mapObjects,
              ),
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
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 46, height: 46,
                                decoration: BoxDecoration(
                                  color: surface,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
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
                        const Spacer(),
                        GestureDetector(
                          onTap: _showHomeTutorial,
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: surface,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
                            ),
                            child: Icon(Icons.help_outline, color: textPrimary, size: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _toggleOnline,
                          child: _StatusBadge(isOnline: _isOnline, loading: _onlineLoading, locale: locale),
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
                if (_activeOrder != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _goToDestination,
                    child: _CircleBtn(icon: Icons.flag, surface: AppTheme.primaryColor, textColor: Colors.white),
                  ),
                ],
              ],
            ),
          ),

          if (_activeOrder != null && _activeSheetExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _activeSheetExpanded = false),
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),

          if (_activeOrder != null && _currentSteps.isNotEmpty && !_activeSheetExpanded)
            Positioned(
              left: 16, right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 74,
              child: _TurnByTurnPanel(
                step: _currentSteps[_currentStepIndex.clamp(0, _currentSteps.length - 1)],
                stepIndex: _currentStepIndex,
                locale: locale,
                overrideDistanceMeters: _currentStepRemainingMeters,

              ),
            ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                    .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _activeOrder != null
                  ? (_activeSheetExpanded
                      ? _ActiveOrderSheet(
                          key: ValueKey('active_full_${_activeOrder!['status']}'),
                          order: _activeOrder!,
                          isDark: _isDark,
                          locale: locale,
                          distKm: _routeDistKm,
                          timeMin: _routeTimeMin,
                          routeProgress: _routeProgress,
                          onAdvance: _onAdvance,
                          onCancelled: _clearActiveOrder,
                          onCollapse: () => setState(() => _activeSheetExpanded = false),
                        )
                      : _ActiveOrderMiniPanel(
                          key: ValueKey('active_mini_${_activeOrder!['status']}'),
                          distKm: _routeDistKm,
                          timeMin: _routeTimeMin,
                          routeProgress: _routeProgress,
                          isDark: _isDark,
                          locale: locale,
                          onDetail: () => setState(() => _activeSheetExpanded = true),
                        ))
                  : _hasOrder && _currentOrder != null
                  ? _OrderSheet(
                      key: const ValueKey('order'),
                      order: _currentOrder!,
                      isDark: _isDark,
                      locale: locale,
                      onAccept: _onAccept,
                      onReject: _onReject,
                    )
                  : _EmptySheet(
                      key: ValueKey('empty_$_isOnline'),
                      isOnline: _isOnline,
                      onlineLoading: _onlineLoading,
                      onToggle: _toggleOnline,
                      isDark: _isDark,
                      locale: locale,
                    ),
            ),
          ),
        ],
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

class _TurnByTurnPanel extends StatelessWidget {
  final Map<String, dynamic> step;
  final int stepIndex;
  final String locale;

  final double? overrideDistanceMeters;
  const _TurnByTurnPanel({
    required this.step,
    required this.stepIndex,
    required this.locale,
    this.overrideDistanceMeters,
  });
  static String _formatStepDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    final instruction = (step['instruction'] as String? ?? '').toLowerCase();
    final distanceMeters = overrideDistanceMeters ?? (step['distanceMeters'] as num?)?.toDouble() ?? 0;
    final IconData icon;
    final String textKey;
    if (instruction.contains('left')) {
      icon = Icons.turn_left;
      textKey = 'turn_left_hint';
    } else if (instruction.contains('right')) {
      icon = Icons.turn_right;
      textKey = 'turn_right_hint';
    } else {
      icon = Icons.straight;
      textKey = 'turn_straight_hint';
    }

    final text = AppStrings.get(textKey, locale).replaceAll('{dist}', _formatStepDistance(distanceMeters));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Row(
            key: ValueKey(stepIndex),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveTrackingPanel extends StatelessWidget {
  final double distKm;
  final String trafficLabel;
  final bool isDark;

  const _LiveTrackingPanel({required this.distKm, required this.trafficLabel, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textP = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textS = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Row(children: [
        const Icon(Icons.local_shipping, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${distKm.toStringAsFixed(1)} km',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textP)),
              Text(trafficLabel, style: TextStyle(fontSize: 11, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

String _formatDuration(int minutes, String locale) {
  if (minutes < 60) {
    return '$minutes ${AppStrings.get('route_time_min', locale)}';
  }
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) {
    return '$hours ${AppStrings.get('route_time_hour', locale)}';
  }
  return '$hours ${AppStrings.get('route_time_hour', locale)} $mins ${AppStrings.get('route_time_min', locale)}';
}

class _RouteInfoRow extends StatelessWidget {
  final double distKm;
  final int? timeMin;
  final bool isDark;
  final String locale;

  const _RouteInfoRow({required this.distKm, this.timeMin, required this.isDark, required this.locale});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.route, size: 16, color: AppTheme.primaryColor),
        const SizedBox(width: 7),
        Text('${distKm.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
        if (timeMin != null) ...[
          Container(margin: const EdgeInsets.symmetric(horizontal: 10), width: 1, height: 14, color: textSecondary.withOpacity(0.3)),
          Icon(Icons.access_time, size: 14, color: textSecondary),
          const SizedBox(width: 5),
          Text(
            _formatDuration(timeMin!, locale),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
          ),
        ],
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOnline;
  final bool loading;
  final String locale;
  const _StatusBadge({required this.isOnline, this.loading = false, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
              ? [const Color(0xFF1e3a8a), const Color(0xFF2563eb)]
              : [const Color(0xFF7f1d1d), const Color(0xFFdc2626)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(width: 10, height: 10,
                child: AppLoadingIndicator(strokeWidth: 2, color: Colors.white))
          else
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(isOnline ? AppStrings.get('online', locale) : AppStrings.get('offline', locale),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _EmptySheet extends StatelessWidget {
  final bool isOnline;
  final bool onlineLoading;
  final bool isDark;
  final String locale;
  final VoidCallback onToggle;

  const _EmptySheet({
    super.key,
    required this.isOnline,
    required this.onlineLoading,
    required this.onToggle,
    required this.isDark,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final handleColor = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 20)],
        ),
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            if (isOnline) ...[
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.local_shipping_outlined, color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppStrings.get('order_waiting', locale),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                        const SizedBox(height: 2),
                        Text(AppStrings.get('you_are_online', locale),
                            style: TextStyle(fontSize: 12, color: textSecondary)),
                      ],
                    ),
                  ),
                  _PulsingDot(),
                ],
              ),
            ] else ...[
              Icon(Icons.local_shipping_outlined, size: 40, color: textSecondary),
              const SizedBox(height: 12),
              Text(AppStrings.get('you_are_offline', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
              const SizedBox(height: 4),
              Text(AppStrings.get('go_online_hint', locale),
                  style: TextStyle(fontSize: 13, color: textSecondary)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onlineLoading ? null : onToggle,
                child: Container(
                  width: double.infinity, height: 48,
                  decoration: BoxDecoration(
                    gradient: onlineLoading ? null : const LinearGradient(
                      colors: [Color(0xFF1e3a8a), Color(0xFF2563eb), Color(0xFF3b82f6)],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    color: onlineLoading ? (isDark ? AppTheme.darkBorder : AppTheme.borderColor) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: onlineLoading
                        ? const SizedBox(width: 20, height: 20,
                            child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(AppStrings.get('go_online', locale),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _OrderSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OrderSheet({
    super.key,
    required this.order,
    required this.isDark,
    required this.locale,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final handleColor = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 20)],
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(AppStrings.get('new_order_label', locale),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Icon(Icons.local_shipping, size: 16, color: AppTheme.primaryColor),
                  Container(width: 1.5, height: 32, color: handleColor),
                  const Icon(Icons.flag, size: 16, color: AppTheme.successColor),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AddressHelper.shorten(order['fromCity'] as String),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    Text(order['fromAddress'] as String,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    const SizedBox(height: 10),
                    Text(AddressHelper.shorten(order['toCity'] as String),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    Text(order['toAddress'] as String,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                  ],
                ),
              ),
              Text('${order['price']} so\'m',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Chip(label: order['truckType'] as String, icon: Icons.local_shipping_outlined, isDark: isDark),
              const SizedBox(width: 8),
              _Chip(label: '${order['weight']} t', icon: Icons.scale_outlined, isDark: isDark),
            ],
          ),
          const SizedBox(height: 10),
          _SlideToAcceptButton(
            label: AppStrings.get('slide_to_accept', locale),
            onComplete: onAccept,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _SlideToAcceptButton extends StatefulWidget {
  final String label;
  final VoidCallback onComplete;
  final bool isDark;

  const _SlideToAcceptButton({
    required this.label,
    required this.onComplete,
    required this.isDark,
  });

  @override
  State<_SlideToAcceptButton> createState() => _SlideToAcceptButtonState();
}

class _SlideToAcceptButtonState extends State<_SlideToAcceptButton> with SingleTickerProviderStateMixin {
  static const double _handleSize = 48;
  static const double _trackPadding = 4;
  static const double _completeThreshold = 0.85;

  late final AnimationController _resetController;
  double _dragX = 0;
  double _maxDrag = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
      ..addListener(() => setState(() => _dragX = _resetController.value * _maxDrag));
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_completed) return;
    setState(() => _dragX = (_dragX + details.delta.dx).clamp(0, _maxDrag));
  }

  void _onDragEnd(DragEndDetails details) {
    if (_completed) return;
    final progress = _maxDrag <= 0 ? 0.0 : (_dragX / _maxDrag).clamp(0.0, 1.0);
    if (progress >= _completeThreshold) {
      setState(() {
        _completed = true;
        _dragX = _maxDrag;
      });
      widget.onComplete();
    } else {
      _resetController.value = progress;
      _resetController.animateTo(0, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = widget.isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final borderColor = widget.isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textColor = widget.isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    const trackHeight = _handleSize + _trackPadding * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = (constraints.maxWidth - trackHeight).clamp(0, double.infinity);
        final progress = _maxDrag <= 0 ? 0.0 : (_dragX / _maxDrag).clamp(0.0, 1.0);

        return Container(
          height: trackHeight,
          padding: const EdgeInsets.all(_trackPadding),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(trackHeight / 2),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                width: _handleSize + _dragX,
                height: _handleSize,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(_handleSize / 2)),
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor, Color(0xFF1E3A8A)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color.lerp(textColor, Colors.white, progress),
                  ),
                ),
              ),
              Positioned(
                left: _dragX,
                child: GestureDetector(
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    width: _handleSize,
                    height: _handleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.arrow_forward, color: AppTheme.primaryColor),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  const _Chip({required this.label, required this.icon, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          )),
        ],
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color border;
  final Color textP;
  final Color textS;

  const _MiniInfoCard({
    required this.label, required this.value,
    required this.bg, required this.border, required this.textP, required this.textS,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: textS)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textP), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(width: 10, height: 10,
          decoration: const BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle)),
    );
  }
}

// ===== AKTIV BUYURTMA SHEET (Driver) — ConsumerWidget, baholash uchun =====
class _ActiveOrderSheet extends ConsumerWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final double? distKm;
  final int? timeMin;
  final double routeProgress;
  final VoidCallback onAdvance;
  final VoidCallback onCancelled;
  final VoidCallback onCollapse;

  const _ActiveOrderSheet({
    super.key,
    required this.order,
    required this.isDark,
    required this.locale,
    this.distKm,
    this.timeMin,
    this.routeProgress = 0.0,
    required this.onAdvance,
    required this.onCancelled,
    required this.onCollapse,
  });

  // Telefon raqamiga qo'ng'iroq qilishdan oldin tasdiqlash so'raladi.
  Future<void> _confirmAndCall(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('call_confirm_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('$phone\n${AppStrings.get('call_confirm_message', locale)}',
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale),
                style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get('call', locale),
                style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('call_failed', locale)), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('call_failed', locale)), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // Buyurtmani bekor qilishdan oldin tasdiqlash so'raladi — faqat yuk hali
  // olinmagan bosqichda (ACCEPTED / DRIVER_ARRIVING) chaqiriladi.
  Future<void> _confirmAndCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('cancel_order_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(AppStrings.get('cancel_order_message', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('no_keep_order', locale),
                style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get('yes_cancel_order', locale),
                style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final orderId = order['id'] as String? ?? '';
    try {
      await ref.read(driverRepositoryProvider).cancelOrder(orderId);
      onCancelled();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('generic_error', locale)}: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // Favqulodda yordam (SOS) — tasdiqlash dialogi orqali, joriy
  // joylashuv bilan birga backend'ga yuboriladi.
  Future<void> _sendSos(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 24),
          const SizedBox(width: 8),
          Text(AppStrings.get('emergency_support_label', locale),
              style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'SOS signal yuborilganda, sizning joriy joylashuvingiz admin panelga darhol yuboriladi. Faqat favqulodda holatlarda ishlating.',
          style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale),
                style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SOS', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await ref.read(sosRepositoryProvider).sendSos(lat: position.latitude, lng: position.longitude);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS signal yuborildi. Yordam yo\'lda.'), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('generic_error', locale)}: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // Yetkazish yakunlanganda — avval clientni baholash so'raladi,
  // keyin buyurtma yopiladi (onAdvance chaqiriladi)
  Future<void> _openRatingThenAdvance(BuildContext context, WidgetRef ref) async {
    final client = order['client'] as Map<String, dynamic>?;
    final orderId = order['id'] as String? ?? '';
    final navigatorContext = Navigator.of(context).context;

    onCollapse();
    await Future.delayed(const Duration(milliseconds: 380));
    if (!navigatorContext.mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: navigatorContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => RatingDialog(
        title: 'Mijozni baholang',
        subtitle: client != null ? (client['fullName'] as String? ?? '') : '',
        onSubmit: (score, note) async {
          await ref.read(ratingRepositoryProvider).rateClient(
            orderId: orderId,
            score: score,
            note: note,
          );
        },
      ),
    );
    if (result == true) {
      onAdvance();
    } else if (navigatorContext.mounted) {
      final locale = ref.read(localeProvider).languageCode;
      ScaffoldMessenger.of(navigatorContext).showSnackBar(
        SnackBar(content: Text(AppStrings.get('rating_submit_error', locale))),
      );
    }
  }

  // Yuk olinganda (ACCEPTED/DRIVER_ARRIVING -> IN_TRANSIT) — avval sheet'ni
  // "collapse" qilib (mini panelga yig'ib) uning animatsiyasi tugashini
  // kutamiz, KEYIN statusni yangilaymiz. Aks holda, sheet ochiq turgan
  // holatda bir vaqtning o'zida ham _activeSheetExpanded, ham order status
  // (demak AnimatedSwitcher key'i) o'zgarib, ikkala o'zgarish bitta
  // freym ichida chalkashib, animatsiya ko'rinmay qolar edi (xuddi
  // _openRatingThenAdvance dagi onCollapse() + kutish naqshiga o'xshab).
  Future<void> _collapseThenAdvance() async {
    onCollapse();
    await Future.delayed(const Duration(milliseconds: 380));
    onAdvance();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textP = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textS = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    final status = order['status'] as String? ?? 'ACCEPTED';
    final client = order['client'] as Map<String, dynamic>?;
    final clientPhone = client?['user']?['phone'] as String? ?? '';
    final price = (order['price'] as num?) ?? 0;
    final fromCity = order['fromCity'] as String? ?? '';
    final toCity = order['toCity'] as String? ?? '';
    final fromAddress = order['fromAddress'] as String? ?? '';
    final toAddress = order['toAddress'] as String? ?? '';

    final isPickup = status == 'ACCEPTED' || status == 'DRIVER_ARRIVING';
    final rating = (client?['averageRating'] as num?)?.toDouble() ?? 5.0;
    final weight = order['weight'];
    final cargoType = (order['cargoType'] as String?) ?? (order['truckType'] as String?) ?? '-';

    double dragDownAccum = 0;
    bool dragCollapsed = false;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.66),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.12), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onCollapse,
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              if (dragCollapsed) return;
              dragDownAccum = (dragDownAccum + details.delta.dy).clamp(0, double.infinity);
              if (dragDownAccum > 40) {
                dragCollapsed = true;
                onCollapse();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPickup
                      ? AppTheme.primaryColor.withOpacity(0.1)
                      : AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: isPickup ? AppTheme.primaryColor : AppTheme.successColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPickup ? AppStrings.get('going_to_client', locale) : AppStrings.get('cargo_on_way', locale),
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: isPickup ? AppTheme.primaryColor : AppTheme.successColor,
                    ),
                  ),
                ]),
              ),
              const Spacer(),
              if (clientPhone.isNotEmpty)
                GestureDetector(
                  onTap: () => _confirmAndCall(context, clientPhone),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_outlined, size: 18, color: AppTheme.primaryColor),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  final clientName = order['client']?['fullName'] as String? ?? '';
                  context.push('/chat/${order['id']}', extra: clientName);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 18, color: AppTheme.primaryColor),
                ),
              ),
              Text(
                '${(price / 1000).toStringAsFixed(0)} 000 so\'m',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textP),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (distKm != null) _RouteInfoRow(distKm: distKm!, timeMin: timeMin, isDark: isDark, locale: locale),
                  if (client != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                      child: Row(children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.person, color: AppTheme.primaryColor, size: 20),
                            ),
                            Positioned(
                              bottom: -4, left: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: border, width: 0.5),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                                  const SizedBox(width: 2),
                                  Text(rating.toStringAsFixed(1),
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: textP)),
                                ]),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(client['fullName'] as String? ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                            if (clientPhone.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () => _confirmAndCall(context, clientPhone),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.phone_outlined, size: 12, color: AppTheme.primaryColor),
                                  const SizedBox(width: 4),
                                  Text(clientPhone, style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppStrings.get('route_summary_label', locale),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textP)),
                        const SizedBox(height: 10),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Column(children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(width: 2, height: 30, color: border),
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 650),
                                    curve: Curves.easeInOut,
                                    width: 2,
                                    height: (routeProgress * (30 - 16)) + 8,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 650),
                                  curve: Curves.easeInOut,
                                  top: routeProgress * (30 - 16),
                                  left: (2 - 16) / 2,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.primaryColor,
                                      border: Border.all(color: isDark ? AppTheme.darkSurface : Colors.white, width: 2),
                                    ),
                                    child: Transform.rotate(
                                      angle: math.pi,
                                      child: const Icon(Icons.navigation, size: 8, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: border, shape: BoxShape.circle)),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(AppStrings.get('pickup_label', locale),
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.primaryColor, letterSpacing: 0.5)),
                              Text(AddressHelper.shorten(fromCity), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                              if (fromAddress.isNotEmpty)
                                Text(fromAddress, style: TextStyle(fontSize: 11, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 14),
                              Text(AppStrings.get('dropoff_label', locale),
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: textS, letterSpacing: 0.5)),
                              Text(AddressHelper.shorten(toCity), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                              if (toAddress.isNotEmpty)
                                Text(toAddress, style: TextStyle(fontSize: 11, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _MiniInfoCard(
                        label: AppStrings.get('load_weight_label', locale),
                        value: weight != null ? '$weight t' : '-',
                        bg: bgCard, border: border, textP: textP, textS: textS,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniInfoCard(
                        label: AppStrings.get('cargo_type_label', locale),
                        value: cargoType,
                        bg: bgCard, border: border, textP: textP, textS: textS,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _sendSos(context, ref),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.errorColor.withOpacity(0.15) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.emergency_share_outlined, size: 16, color: AppTheme.errorColor),
                        const SizedBox(width: 6),
                        Text(AppStrings.get('emergency_support_label', locale),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: isPickup
                ? Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _confirmAndCancel(context, ref),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.errorColor),
                          foregroundColor: AppTheme.errorColor,
                          minimumSize: const Size(0, 52),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(AppStrings.get('cancel', locale),
                              maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _DriverBtn(
                        label: AppStrings.get('picked_up_continue', locale),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1e3a8a), Color(0xFF2563eb)],
                          begin: Alignment.centerLeft, end: Alignment.centerRight,
                        ),
                        onTap: _collapseThenAdvance,
                      ),
                    ),
                  ])
                : _SlideToAcceptButton(
                    label: AppStrings.get('delivered_finish', locale),
                    onComplete: () => _openRatingThenAdvance(context, ref),
                    isDark: isDark,
                  ),
          ),
        ],
      ),
    );
  }
}

// ===== KICHIK, DOIMIY AKTIV BUYURTMA PANELI (Driver) =====
class _ActiveOrderMiniPanel extends StatelessWidget {
  final double? distKm;
  final int? timeMin;
  final double routeProgress;
  final bool isDark;
  final String locale;
  final VoidCallback onDetail;

  const _ActiveOrderMiniPanel({
    super.key,
    this.distKm,
    this.timeMin,
    required this.routeProgress,
    required this.isDark,
    required this.locale,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textP = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final distLabel = distKm != null ? distKm!.toStringAsFixed(1) : '--';
    final timeLabel = timeMin != null
        ? _formatDuration(timeMin!, locale)
        : '-- ${AppStrings.get('route_time_min', locale)}';

    return GestureDetector(
      onTap: onDetail,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.1), blurRadius: 20)],
        ),
        padding: EdgeInsets.only(
          left: 18, right: 12, top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$distLabel km · $timeLabel',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textP),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _MiniProgressTrack(progress: routeProgress, isDark: isDark, border: border),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                AppStrings.get('order_details', locale),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgressTrack extends StatelessWidget {
  final double progress;
  final bool isDark;
  final Color border;

  const _MiniProgressTrack({required this.progress, required this.isDark, required this.border});

  @override
  Widget build(BuildContext context) {
    const dot = 14.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = (constraints.maxWidth - dot).clamp(0.0, double.infinity);
        return SizedBox(
          height: dot,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 3,
                width: double.infinity,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOut,
                height: 3,
                width: (progress * travel) + dot / 2,
                decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(2)),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOut,
                left: progress * travel,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor,
                    border: Border.all(color: isDark ? AppTheme.darkSurface : Colors.white, width: 2),
                  ),
                  child: Transform.rotate(
                    angle: math.pi / 2,
                    child: const Icon(Icons.navigation, size: 7, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DriverBtn extends StatelessWidget {
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _DriverBtn({required this.label, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ),
  );
}