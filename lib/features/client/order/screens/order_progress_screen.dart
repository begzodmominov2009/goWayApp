import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/utils/address_helper.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/place.dart';
import 'active_order_details_screen.dart';

const List<String> _kFoundStatuses = ['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'];

// order_form_modal.dart dagi _kSheetAnimationStyle bilan bir xil qiymatlar —
// rejalashtirilgan buyurtma tasdiq modali ilova bo'ylab izchil animatsiyada ochilishi uchun.
final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

/// Buyurtma yaratish oqimining oxirgi bosqichi — Order Form Modal'dan
/// "Tasdiqlash" bosilgach ochiladi. Ikkita holatni boshqaradi:
///   1) Preview  (_searching == false) — marshrut xaritada ko'rsatiladi,
///      order hali yaratilmagan, "Buyurtma berish" tugmasi faol.
///   2) Searching (_searching == true) — order backend'da yaratilgan,
///      driver qidirilmoqda (radar animatsiyasi + polling).
/// Driver topilgach, ActiveOrderDetailsScreen'ga pushReplacement orqali
/// o'tkaziladi — tracking/chat/baholash mantig'i shu yerda TAKRORLANMAYDI.
class OrderProgressScreen extends ConsumerStatefulWidget {
  final Place fromPlace;
  final Place toPlace;
  final String truckType;
  final double weight;
  final String? cargoType;
  final String? note;
  final bool isScheduled;
  final DateTime? scheduledFor;
  final double? distKm;
  final int? timeMin;

  const OrderProgressScreen({
    super.key,
    required this.fromPlace,
    required this.toPlace,
    required this.truckType,
    required this.weight,
    this.cargoType,
    this.note,
    required this.isScheduled,
    this.scheduledFor,
    this.distKm,
    this.timeMin,
  });

  @override
  ConsumerState<OrderProgressScreen> createState() => _OrderProgressScreenState();
}

class _OrderProgressScreenState extends ConsumerState<OrderProgressScreen> {
  YandexMapController? _mapController;
  List<MapObject> _mapObjects = [];

  bool _searching = false;
  bool _submittingScheduled = false;
  Map<String, dynamic>? _createdOrder;
  Timer? _pollTimer;

  double? _currentDistKm;
  int? _currentTimeMin;
  Offset? _radarScreenPos;

  @override
  void initState() {
    super.initState();
    _currentDistKm = widget.distKm;
    _currentTimeMin = widget.timeMin;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    final repo = ref.read(geocodeRepositoryProvider);
    final route = await repo.getRoute(
      fromLat: widget.fromPlace.lat, fromLng: widget.fromPlace.lng,
      toLat: widget.toPlace.lat, toLng: widget.toPlace.lng,
    );
    if (!mounted) return;

    final points = route?.points.map((c) => Point(latitude: c[0], longitude: c[1])).toList() ??
        [
          Point(latitude: widget.fromPlace.lat, longitude: widget.fromPlace.lng),
          Point(latitude: widget.toPlace.lat, longitude: widget.toPlace.lng),
        ];

    setState(() {
      _currentDistKm = route?.distanceKm ?? _currentDistKm;
      _currentTimeMin = route?.durationMin ?? _currentTimeMin;
    });
    _rebuildMapObjects(points);
    _fitBounds(points);
  }

  void _rebuildMapObjects(List<Point> points) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final objects = <MapObject>[
      PolylineMapObject(
        mapId: const MapObjectId('order_progress_route'),
        polyline: Polyline(points: points),
        strokeColor: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1d4ed8),
        strokeWidth: 5,
      ),
    ];
    if (MapIconHelper.truckIconReady != null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('order_progress_from_pin'),
        point: Point(latitude: widget.fromPlace.lat, longitude: widget.fromPlace.lng),
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: MapIconHelper.truckIconReady!, scale: 0.17, anchor: const Offset(0.5, 1.0),
        )),
      ));
    }
    if (MapIconHelper.finishIconReady != null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('order_progress_to_pin'),
        point: Point(latitude: widget.toPlace.lat, longitude: widget.toPlace.lng),
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: MapIconHelper.finishIconReady!, scale: 0.17, anchor: const Offset(0.5, 1.0),
        )),
      ));
    }
    setState(() => _mapObjects = objects);
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

  Future<void> _centerOnPickupForSearch() async {
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: Point(latitude: widget.fromPlace.lat, longitude: widget.fromPlace.lng), zoom: 16),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.6),
    );
    await Future.delayed(const Duration(milliseconds: 650));
    await _updateRadarScreenPos();
  }

  Future<void> _updateRadarScreenPos() async {
    if (!_searching || _mapController == null || !mounted) return;
    try {
      final sp = await _mapController!.getScreenPoint(
        Point(latitude: widget.fromPlace.lat, longitude: widget.fromPlace.lng),
      );
      if (sp != null && mounted) {
        setState(() => _radarScreenPos = Offset(sp.x, sp.y));
      }
    } catch (_) {}
  }

  Future<void> _placeOrder() async {
    // Rejalashtirilgan buyurtmada qidiruv (radar/polling) UMUMAN
    // boshlanmasligi kerak — driver backend tomonidan belgilangan vaqtdan
    // 30 daqiqa oldin avtomatik qidiriladi. Shuning uchun _searching faqat
    // ODDIY buyurtmada true qilinadi; rejalashtirilganda so'rov davomida
    // tugmani ikki marta bosishdan saqlash uchun alohida bayroq ishlatiladi.
    if (widget.isScheduled) {
      setState(() => _submittingScheduled = true);
    } else {
      setState(() => _searching = true);
      _centerOnPickupForSearch();
    }
    try {
      final created = await ref.read(clientRepositoryProvider).createOrder(
        fromCity: widget.fromPlace.name, fromAddress: widget.fromPlace.address,
        toCity: widget.toPlace.name, toAddress: widget.toPlace.address,
        fromLatitude: widget.fromPlace.lat, fromLongitude: widget.fromPlace.lng,
        toLatitude: widget.toPlace.lat, toLongitude: widget.toPlace.lng,
        truckType: widget.truckType, weight: widget.weight,
        cargoType: widget.cargoType, note: widget.note,
        priority: 'STANDARD', isScheduled: widget.isScheduled,
        scheduledFor: widget.scheduledFor,
      );
      if (!mounted) return;
      if (widget.isScheduled) {
        setState(() => _submittingScheduled = false);
        await _showScheduledConfirmationSheet(created);
      } else {
        setState(() => _createdOrder = created);
        _startPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _submittingScheduled = false;
      });
      if (e is OrderCreationException && e.reasonKey == 'bad_request') {
        _showInactiveRouteDialog(e.serverMessage);
        return;
      }
      final locale = ref.read(localeProvider).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e, locale)), backgroundColor: AppTheme.errorColor),
      );
    }
  }

  // Rejalashtirilgan buyurtma muvaffaqiyatli yaratilgach ko'rsatiladigan
  // chipta uslubidagi tasdiq modali. Qanday yopilishidan qat'i nazar (tugma,
  // pastga tortish yoki chetiga bosish) — modal yopilgach foydalanuvchi
  // Home ekraniga qaytadi, bo'sh Progress ekranida qolib ketmaydi.
  Future<void> _showScheduledConfirmationSheet(Map<String, dynamic> created) async {
    final locale = ref.read(localeProvider).languageCode;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _ScheduledOrderTicketSheet(
        scheduledFor: widget.scheduledFor!,
        fromPlace: widget.fromPlace,
        toPlace: widget.toPlace,
        truckType: widget.truckType,
        weight: widget.weight,
        distKm: (created['distance'] as num?)?.toDouble() ?? _currentDistKm,
        price: (created['price'] as num?)?.toDouble(),
        locale: locale,
      ),
    );
    if (mounted) Navigator.pop(context);
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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final orders = await ref.read(clientRepositoryProvider).getOrders();
        if (orders.isEmpty) return;
        final latestOrder = orders.first;
        final status = latestOrder['status'] as String? ?? '';
        if (_kFoundStatuses.contains(status)) {
          _pollTimer?.cancel();
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (ctx) => ActiveOrderDetailsScreen(order: latestOrder),
            ));
          }
        } else if (status == 'CANCELLED') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() => _searching = false);
          final locale = ref.read(localeProvider).languageCode;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.get('generic_error', locale)), backgroundColor: AppTheme.errorColor),
          );
        }
      } catch (_) {}
    });
  }

  Future<void> _cancelSearch() async {
    _pollTimer?.cancel();
    final order = _createdOrder;
    if (order != null) {
      final orderId = order['id'] as String? ?? '';
      if (orderId.isNotEmpty) {
        try {
          await ref.read(clientRepositoryProvider).cancelOrder(orderId);
        } catch (_) {}
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmCancelSearch() async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('cancel_search_confirm_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(AppStrings.get('cancel_search_confirm_message', locale),
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
    if (confirmed == true) _cancelSearch();
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

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () {
            if (_searching) {
              _confirmCancelSearch();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: YandexMap(
              nightModeEnabled: isDark,
              onMapCreated: (controller) {
                _mapController = controller;
                final midLat = (widget.fromPlace.lat + widget.toPlace.lat) / 2;
                final midLng = (widget.fromPlace.lng + widget.toPlace.lng) / 2;
                controller.moveCamera(
                  CameraUpdate.newCameraPosition(CameraPosition(target: Point(latitude: midLat, longitude: midLng), zoom: 12)),
                );
                _loadRoute();
              },
              onCameraPositionChanged: (pos, reason, finished) {
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
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 16)],
              ),
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
                  )),
                  const SizedBox(height: 14),

                  if (!_searching) ...[
                    if (_currentDistKm != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: tabBg, borderRadius: BorderRadius.circular(12)),
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
                      ),
                      const SizedBox(height: 14),
                    ],
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
                    const SizedBox(height: 16),
                    _GradBtn(
                      label: AppStrings.get('place_order', locale),
                      onTap: _submittingScheduled ? null : _placeOrder,
                    ),
                  ] else ...[
                    Row(children: [
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
                              '${AddressHelper.shorten(widget.fromPlace.name)} → ${AddressHelper.shorten(widget.toPlace.name)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _confirmCancelSearch,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: BorderSide(color: border),
                          foregroundColor: textSecondary,
                        ),
                        child: Text(AppStrings.get('cancel_search', locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Rejalashtirilgan buyurtma muvaffaqiyatli yaratilgach ko'rsatiladigan
/// chipta (ticket) uslubidagi tasdiq varag'i — driver belgilangan vaqtdan
/// oldin avtomatik qidirilishini tushuntiradi, hech qanday qidiruv/polling
/// mantig'ini o'zida saqlamaydi.
class _ScheduledOrderTicketSheet extends StatelessWidget {
  final DateTime scheduledFor;
  final Place fromPlace;
  final Place toPlace;
  final String truckType;
  final double weight;
  final double? distKm;
  final double? price;
  final String locale;

  const _ScheduledOrderTicketSheet({
    required this.scheduledFor,
    required this.fromPlace,
    required this.toPlace,
    required this.truckType,
    required this.weight,
    required this.distKm,
    required this.price,
    required this.locale,
  });

  String get _dateTimeLabel {
    final now = DateTime.now();
    final date = DateTime(scheduledFor.year, scheduledFor.month, scheduledFor.day);
    final today = DateTime(now.year, now.month, now.day);
    final dayLabel = date == today
        ? AppStrings.get('today', locale)
        : AppStrings.get('order_type_tomorrow', locale);
    final timeLabel =
        '${scheduledFor.hour.toString().padLeft(2, '0')}:${scheduledFor.minute.toString().padLeft(2, '0')}';
    return '$dayLabel, $timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final cardBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 18),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppTheme.successColor.withOpacity(0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle, color: AppTheme.successColor, size: 34),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.get('scheduled_confirm_title', locale),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                ),
                const SizedBox(height: 18),

                // Chipta ko'rinishidagi kartochka — bo'limlar orasida ajratuvchi chiziqlar
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        _dateTimeLabel,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 14),
                      Divider(color: border, height: 1),
                      const SizedBox(height: 14),
                      Row(children: [
                        Column(children: [
                          const Icon(Icons.local_shipping, size: 14, color: AppTheme.primaryColor),
                          Container(width: 1, height: 20, color: border),
                          const Icon(Icons.flag, size: 14, color: AppTheme.successColor),
                        ]),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AddressHelper.shorten(fromPlace.name),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            Text(AddressHelper.shorten(toPlace.name),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        )),
                      ]),
                      const SizedBox(height: 14),
                      Divider(color: border, height: 1),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: _TicketStat(label: AppStrings.get('truck_type', locale), value: truckType)),
                        Expanded(child: _TicketStat(label: AppStrings.get('weight_label', locale), value: '$weight t')),
                      ]),
                      if (distKm != null || price != null) ...[
                        const SizedBox(height: 14),
                        Divider(color: border, height: 1),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (distKm != null)
                            Expanded(child: _TicketStat(label: AppStrings.get('route_distance_label', locale), value: '${distKm!.toStringAsFixed(1)} km')),
                          if (price != null)
                            Expanded(child: _TicketStat(label: AppStrings.get('estimated_price_label', locale), value: '${price!.toStringAsFixed(0)} so\'m')),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('scheduled_confirm_desc', locale),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
                ),
                const SizedBox(height: 18),
                _GradBtn(
                  label: AppStrings.get('understood', locale),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketStat extends StatelessWidget {
  final String label;
  final String value;
  const _TicketStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
