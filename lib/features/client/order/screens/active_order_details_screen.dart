import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/rating_repository.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../core/utils/map_icon_helper.dart';
import '../../../../shared/widgets/rating_dialog.dart';
import '../../../../shared/widgets/driver_avatar.dart';

const List<String> _kLiveTrackedStatuses = ['ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'];

/// Aktiv buyurtma — to'liq tafsilotlar sahifasi. Xarita ustida joriy
/// haydovchi joylashuvi (LIVE) va marshrut, pastda esa haydovchi
/// ma'lumotlari, "Route Summary" va yuk kartochkalari ko'rsatiladi.
///
/// Natija: Navigator.pop(context, true) — buyurtma baholanib
/// yakunlanganda, aks holda false/null (foydalanuvchi orqaga qaytdi).
class ActiveOrderDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final double? distKm;
  final int? timeMin;

  const ActiveOrderDetailsScreen({
    super.key,
    required this.order,
    this.distKm,
    this.timeMin,
  });

  @override
  ConsumerState<ActiveOrderDetailsScreen> createState() => _ActiveOrderDetailsScreenState();
}

class _ActiveOrderDetailsScreenState extends ConsumerState<ActiveOrderDetailsScreen> {
  late Map<String, dynamic> _order;
  double? _liveDistKm;
  int? _liveTimeMin;

  YandexMapController? _mapController;
  List<MapObject> _mapObjects = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _liveDistKm = widget.distKm;
    _liveTimeMin = widget.timeMin;
    _updateMapTracking();
    if (_kLiveTrackedStatuses.contains(_order['status'] as String? ?? '')) {
      _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _pollOrder());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollOrder() async {
    final orderId = _order['id'] as String? ?? '';
    if (orderId.isEmpty) return;
    try {
      final latest = await ref.read(clientRepositoryProvider).getOrder(orderId);
      if (!mounted) return;
      setState(() => _order = latest);
      if (!_kLiveTrackedStatuses.contains(latest['status'] as String? ?? '')) {
        _pollTimer?.cancel();
      }
      await _updateMapTracking();
    } catch (_) {}
  }

  bool _isPickupPhase(String status) => status == 'ACCEPTED' || status == 'DRIVER_ARRIVING';

  Future<void> _updateMapTracking() async {
    final driver = _order['driver'] as Map<String, dynamic>?;
    final status = _order['status'] as String? ?? '';
    final isPickup = _isPickupPhase(status);

    final fromLat = (_order['fromLatitude'] as num?)?.toDouble();
    final fromLng = (_order['fromLongitude'] as num?)?.toDouble();
    final toLat = (_order['toLatitude'] as num?)?.toDouble();
    final toLng = (_order['toLongitude'] as num?)?.toDouble();
    final targetLat = isPickup ? fromLat : toLat;
    final targetLng = isPickup ? fromLng : toLng;

    final driverLat = (driver?['lastLatitude'] as num?)?.toDouble();
    final driverLng = (driver?['lastLongitude'] as num?)?.toDouble();

    List<Point> points = [];

    if (driverLat != null && driverLng != null && targetLat != null && targetLng != null) {
      final route = await ref.read(geocodeRepositoryProvider).getRoute(
            fromLat: driverLat, fromLng: driverLng, toLat: targetLat, toLng: targetLng,
          );
      if (!mounted) return;
      points = route?.points.map((c) => Point(latitude: c[0], longitude: c[1])).toList() ??
          [Point(latitude: driverLat, longitude: driverLng), Point(latitude: targetLat, longitude: targetLng)];
      setState(() {
        _liveDistKm = route?.distanceKm;
        _liveTimeMin = route?.durationMin;
      });
    } else if (fromLat != null && fromLng != null && toLat != null && toLng != null) {
      points = [Point(latitude: fromLat, longitude: fromLng), Point(latitude: toLat, longitude: toLng)];
    }
    if (points.isEmpty || !mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    setState(() {
      _mapObjects = [
        PolylineMapObject(
          mapId: const MapObjectId('client_active_track'),
          polyline: Polyline(points: points),
          strokeColor: isPickup
              ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1d4ed8))
              : (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
          strokeWidth: 5,
        ),
        if (driverLat != null && driverLng != null && MapIconHelper.truckIconReady != null)
          PlacemarkMapObject(
            mapId: const MapObjectId('client_active_driver_pin'),
            point: Point(latitude: driverLat, longitude: driverLng),
            icon: PlacemarkIcon.single(PlacemarkIconStyle(
              image: MapIconHelper.truckIconReady!, scale: 0.17, anchor: const Offset(0.5, 1.0),
            )),
          ),
        if (targetLat != null && targetLng != null && MapIconHelper.finishIconReady != null)
          PlacemarkMapObject(
            mapId: const MapObjectId('client_active_target_pin'),
            point: Point(latitude: targetLat, longitude: targetLng),
            icon: PlacemarkIcon.single(PlacemarkIconStyle(
              image: MapIconHelper.finishIconReady!, scale: 0.17, anchor: const Offset(0.5, 1.0),
            )),
          ),
      ];
    });

    _fitBounds(points);
  }

  void _fitBounds(List<Point> points) {
    if (points.length < 2) {
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: points.first, zoom: 14)),
      );
      return;
    }
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
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.5),
    );
  }

  String _trafficLabel(String locale) {
    if (_liveDistKm == null || _liveTimeMin == null || _liveTimeMin == 0) {
      return AppStrings.get('traffic_light', locale);
    }
    final speedKmh = _liveDistKm! / (_liveTimeMin! / 60.0);
    if (speedKmh >= 35) return AppStrings.get('traffic_light', locale);
    if (speedKmh >= 18) return AppStrings.get('traffic_moderate', locale);
    return AppStrings.get('traffic_heavy', locale);
  }

  String _clockPlusMinutes(int minutes) {
    final t = DateTime.now().add(Duration(minutes: minutes));
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _shortOrderId(String id) => id.isEmpty ? '' : '#${(id.length >= 8 ? id.substring(0, 8) : id).toUpperCase()}';

  Future<void> _confirmAndCall(BuildContext context, WidgetRef ref, String phone) async {
    if (phone.isEmpty) return;
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            child: Text(AppStrings.get('no_keep_order', locale),
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

  Future<void> _openRatingThenComplete(BuildContext context, WidgetRef ref, Map<String, dynamic>? driver, String orderId) async {
    final result = await showModalBottomSheet<bool>(
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
    if (result == true) {
      if (context.mounted) Navigator.pop(context, true);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Baholashni yuborib bo\'lmadi. Qayta urinib ko\'ring.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final textP = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textS = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    final status = _order['status'] as String? ?? '';
    final driver = _order['driver'] as Map<String, dynamic>?;
    final price = (_order['price'] as num?) ?? 0;
    final fromCity = _order['fromCity'] as String? ?? '';
    final toCity = _order['toCity'] as String? ?? '';
    final fromAddress = _order['fromAddress'] as String? ?? '';
    final toAddress = _order['toAddress'] as String? ?? '';
    final orderId = _order['id'] as String? ?? '';
    final isCompleted = status == 'COMPLETED' || status == 'DELIVERED';
    final isPickup = _isPickupPhase(status);
    final phone = driver?['user']?['phone'] as String? ?? '';
    final rating = (driver?['averageRating'] as num?)?.toDouble() ?? 5.0;

    String statusTitle = AppStrings.get('driver_arriving', locale);
    Color statusColor = AppTheme.primaryColor;
    if (status == 'ACCEPTED') { statusTitle = AppStrings.get('driver_assigned', locale); }
    if (status == 'LOADING') { statusTitle = AppStrings.get('loading_cargo', locale); statusColor = Colors.orange; }
    if (status == 'IN_TRANSIT') { statusTitle = AppStrings.get('in_transit', locale); statusColor = AppTheme.successColor; }
    if (status == 'DELIVERED' || status == 'COMPLETED') { statusTitle = AppStrings.get('delivered_msg', locale); statusColor = AppTheme.successColor; }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: textP, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${AppStrings.get('active_order_title', locale)} ${_shortOrderId(orderId)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusTitle,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: textP),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isCompleted && isPickup && _liveTimeMin != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            AppStrings.get('estimated_arrival_label', locale).replaceAll('{min}', '$_liveTimeMin'),
                            style: TextStyle(fontSize: 12, color: textS),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (!isCompleted) ...[
              SizedBox(
                height: 220,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: YandexMap(
                            nightModeEnabled: isDark,
                            onMapCreated: (controller) {
                              _mapController = controller;
                              _updateMapTracking();
                            },
                            mapObjects: _mapObjects,
                          ),
                        ),
                        if (_liveDistKm != null)
                          Positioned(
                            left: 10, right: 10, bottom: 10,
                            child: _LiveTrackingPanel(
                              distKm: _liveDistKm!,
                              trafficLabel: _trafficLabel(locale),
                              isDark: isDark,
                              locale: locale,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                          Text(statusTitle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                        ]),
                      ),
                      const Spacer(),
                      Text('${(price / 1000).toStringAsFixed(0)} 000 so\'m',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textP)),
                    ]),
                    const SizedBox(height: 16),

                    if (driver != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                        child: Column(children: [
                          Row(children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                DriverAvatar(driver: driver, size: 52),
                                Positioned(
                                  bottom: -4, left: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppTheme.darkSurface : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: border, width: 0.5),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                                      const SizedBox(width: 2),
                                      Text(rating.toStringAsFixed(1),
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: textP)),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(driver['fullName'] as String? ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textP)),
                              const SizedBox(height: 3),
                              Row(children: [
                                const Icon(Icons.local_shipping_outlined, size: 13, color: AppTheme.primaryColor),
                                const SizedBox(width: 4),
                                Text('${_order['truckType'] ?? ''} · ${driver['plateNumber'] ?? ''}', style: TextStyle(fontSize: 12, color: textS)),
                              ]),
                            ])),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: phone.isNotEmpty ? () => _confirmAndCall(context, ref, phone) : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppTheme.darkBorder.withOpacity(0.4) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.phone, size: 16, color: textP),
                                    const SizedBox(width: 6),
                                    Text(AppStrings.get('call', locale),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textP)),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/chat/$orderId', extra: driver['fullName'] as String? ?? ''),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF1e3a8a), Color(0xFF2563eb)],
                                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
                                    const SizedBox(width: 6),
                                    const Text('Chat',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ]),
                                ),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppStrings.get('route_summary_label', locale),
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textP)),
                          const SizedBox(height: 14),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Column(children: [
                              Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                              Container(width: 2, height: 40, color: border),
                              Container(width: 9, height: 9, decoration: BoxDecoration(color: border, shape: BoxShape.circle)),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(AppStrings.get('pickup_label', locale),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primaryColor, letterSpacing: 0.6)),
                              const SizedBox(height: 2),
                              Text(fromCity, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                              if (fromAddress.isNotEmpty)
                                Text(fromAddress, style: TextStyle(fontSize: 12, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                isPickup
                                    ? (_liveDistKm != null ? '${_liveDistKm!.toStringAsFixed(1)} km' : '')
                                    : AppStrings.get('arrived_at_label', locale),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textS),
                              ),
                              const SizedBox(height: 20),
                              Text(AppStrings.get('dropoff_label', locale),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: textS, letterSpacing: 0.6)),
                              const SizedBox(height: 2),
                              Text(toCity, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textP)),
                              if (toAddress.isNotEmpty)
                                Text(toAddress, style: TextStyle(fontSize: 12, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (!isPickup && !isCompleted && _liveTimeMin != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '${AppStrings.get('est_label', locale)} ${_clockPlusMinutes(_liveTimeMin!)}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textS),
                                ),
                              ],
                            ])),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _MiniInfoCard(
                          label: AppStrings.get('load_weight_label', locale),
                          value: _order['weight'] != null ? '${_order['weight']} t' : '-',
                          bg: bgCard, border: border, textP: textP, textS: textS,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniInfoCard(
                          label: AppStrings.get('cargo_type_label', locale),
                          value: (_order['cargoType'] as String?) ?? (_order['truckType'] as String?) ?? '-',
                          bg: bgCard, border: border, textP: textP, textS: textS,
                        ),
                      ),
                    ]),
                    if ((_order['note'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
                        child: _InfoRow(label: AppStrings.get('note_label', locale), value: _order['note'] as String, textP: textP, textS: textS),
                      ),
                    ],

                    if (isCompleted) ...[
                      const SizedBox(height: 20),
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

class _LiveTrackingPanel extends StatefulWidget {
  final double distKm;
  final String trafficLabel;
  final bool isDark;
  final String locale;

  const _LiveTrackingPanel({required this.distKm, required this.trafficLabel, required this.isDark, required this.locale});

  @override
  State<_LiveTrackingPanel> createState() => _LiveTrackingPanelState();
}

class _LiveTrackingPanelState extends State<_LiveTrackingPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.isDark ? AppTheme.darkSurface : Colors.white;
    final textP = widget.isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textS = widget.isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

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
              Text('${widget.distKm.toStringAsFixed(1)} km',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textP)),
              Text(widget.trafficLabel, style: TextStyle(fontSize: 11, color: textS), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(
              opacity: _anim,
              child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 5),
            Text(AppStrings.get('live_label', widget.locale),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primaryColor, letterSpacing: 0.4)),
          ]),
        ),
      ]),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: textS)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textP), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textP;
  final Color textS;
  const _InfoRow({required this.label, required this.value, required this.textP, required this.textS});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: textS))),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textP), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}
