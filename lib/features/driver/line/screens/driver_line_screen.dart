import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/geo_repository.dart';
import '../../../../shared/widgets/tutorial_sheet.dart';
import 'region_picker_page.dart';
import 'district_picker_page.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

const _kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
  begin: Alignment.centerLeft, end: Alignment.centerRight,
);

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$d.$m $h:$min';
}

/// Ilovadagi standart "yondan slide" o'tish animatsiyasi — boshqa barcha
/// sahifalar (app_router.dart'dagi _slidePage) qanday ochilsa, viloyat/
/// tuman tanlash sahifalari ham xuddi shunday ochiladi.
Route<T> _slideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}

/// Backend 'bad_request' bilan javob berganda, uning aynan "yo'nalish
/// hozircha faol emas" sababidan rad etilganini xabar matnidan taxmin
/// qiladi (client_repository.dart'dagi bad_request tekshiruviga o'xshash,
/// lekin bu yerda aniq matn signaliga tayanadi — backend boshqa sababdan
/// (masalan noto'g'ri davomiylik) rad etsa, umumiy xato ko'rsatiladi).
bool _looksLikeInactiveRouteError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('faol emas') || lower.contains('inactive') || lower.contains('не актив');
}

/// Bitta haydovchi yo'nalishi — backend'dan (/driver/lines) kelgan xom
/// ma'lumot + Flutter tomonida (viloyat/tuman ro'yxatlaridan) aniqlangan
/// ko'rsatish nomlari (faqat tuman/shahar darajasida, viloyat nomisiz).
class _DriverLineItem {
  final String id;
  final String? fromRegionId;
  final String? fromDistrictId;
  final String? toRegionId;
  final String? toDistrictId;
  final DateTime? expiresAt;
  String fromLabel;
  String toLabel;

  _DriverLineItem({
    required this.id,
    this.fromRegionId, this.fromDistrictId,
    this.toRegionId, this.toDistrictId,
    this.expiresAt,
    this.fromLabel = '', this.toLabel = '',
  });

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory _DriverLineItem.fromJson(Map<String, dynamic> json) {
    final expiresAtStr = json['expiresAt'] as String?;
    return _DriverLineItem(
      id: json['id'].toString(),
      fromRegionId: json['fromRegionId'] as String?,
      fromDistrictId: json['fromDistrictId'] as String?,
      toRegionId: json['toRegionId'] as String?,
      toDistrictId: json['toDistrictId'] as String?,
      expiresAt: expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null,
    );
  }
}

/// Haydovchi xizmat ko'rsatadigan yo'nalishlar ro'yxati sahifasi (ko'p
/// yo'nalishga o'tilgan backend bilan mos). Yuqorida doim ko'rinadigan
/// "Yangi yo'nalish yaratish" tugmasi, ostida ro'yxat: yuklanmoqda
/// (shimmer skelet) / bo'sh / yo'nalishlar kartalari.
class DriverLineScreen extends ConsumerStatefulWidget {
  const DriverLineScreen({super.key});

  @override
  ConsumerState<DriverLineScreen> createState() => _DriverLineScreenState();
}

class _DriverLineScreenState extends ConsumerState<DriverLineScreen> {
  bool _loadingLines = true;
  List<_DriverLineItem> _lines = [];
  List<GeoRegion>? _regionsCache;

  @override
  void initState() {
    super.initState();
    _loadLines();
    _maybeShowRoutesTutorial();
  }

  Future<void> _maybeShowRoutesTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seen_routes_tutorial') == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRoutesTutorial();
    });
    await prefs.setBool('seen_routes_tutorial', true);
  }

  void _showRoutesTutorial() {
    final locale = ref.read(localeProvider).languageCode;
    showTutorialSheet(
      context,
      title: AppStrings.get('tutorial_routes_title', locale),
      bullets: [
        AppStrings.get('tutorial_routes_1', locale),
        AppStrings.get('tutorial_routes_2', locale),
        AppStrings.get('tutorial_routes_3', locale),
        AppStrings.get('tutorial_routes_4', locale),
      ],
      icon: Icons.alt_route,
      locale: locale,
    );
  }

  Future<void> _loadLines() async {
    setState(() => _loadingLines = true);
    try {
      final raw = await ref.read(driverRepositoryProvider).getDriverLines();
      final items = raw.map((e) => _DriverLineItem.fromJson(e)).toList();
      if (!mounted) return;
      setState(() {
        _lines = items;
        _loadingLines = false;
      });
      _resolveLabelsForLines();
    } catch (_) {
      if (mounted) setState(() { _lines = []; _loadingLines = false; });
    }
  }

  GeoRegion? _findRegion(List<GeoRegion> list, String? id) {
    if (id == null) return null;
    for (final r in list) {
      if (r.id == id) return r;
    }
    return null;
  }

  GeoDistrict? _findDistrict(List<GeoDistrict> list, String? id) {
    if (id == null) return null;
    for (final d in list) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _resolveLabelsForLines() async {
    final repo = ref.read(geoRepositoryProvider);
    _regionsCache ??= await repo.getAllRegions();
    final regions = _regionsCache!;
    final districtsCache = <String, List<GeoDistrict>>{};

    for (final line in _lines) {
      if (line.fromDistrictId != null && line.fromRegionId != null) {
        districtsCache[line.fromRegionId!] ??= await repo.getAllDistricts(line.fromRegionId!);
        final d = _findDistrict(districtsCache[line.fromRegionId!]!, line.fromDistrictId);
        line.fromLabel = d?.name ?? _findRegion(regions, line.fromRegionId)?.name ?? '';
      } else {
        line.fromLabel = _findRegion(regions, line.fromRegionId)?.name ?? '';
      }

      if (line.toDistrictId != null && line.toRegionId != null) {
        districtsCache[line.toRegionId!] ??= await repo.getAllDistricts(line.toRegionId!);
        final d = _findDistrict(districtsCache[line.toRegionId!]!, line.toDistrictId);
        line.toLabel = d?.name ?? _findRegion(regions, line.toRegionId)?.name ?? '';
      } else {
        line.toLabel = _findRegion(regions, line.toRegionId)?.name ?? '';
      }
    }

    if (!mounted) return;
    setState(() {});
  }

  // ==== Yangi yo'nalish qo'shish — sahifama-sahifa oqim ====

  // Bitta "viloyat -> tuman" juftligini tanlaydi. Tuman sahifasidan orqaga
  // qaytilsa (natija null), viloyat sahifasi qayta ko'rsatiladi — shu bilan
  // "faqat bitta bosqich orqaga" hissi beriladi, lekin har bir sahifa
  // baribir faqat o'zini yopadi (bitta martalik Navigator.push, hech qanday
  // pushReplacement/popUntil ishlatilmaydi). Viloyat sahifasidan orqaga
  // qaytilsa, butun juftlik null qaytadi va chaqiruvchi oqim to'xtaydi.
  Future<(GeoRegion, GeoDistrict)?> _pickRegionAndDistrict(String title) async {
    while (mounted) {
      final region = await Navigator.push<GeoRegion>(
        context,
        _slideRoute(RegionPickerPage(title: title)),
      );
      if (region == null || !mounted) return null;

      final district = await Navigator.push<GeoDistrict>(
        context,
        _slideRoute(DistrictPickerPage(title: title, region: region)),
      );
      if (district == null) {
        if (!mounted) return null;
        continue;
      }
      return (region, district);
    }
    return null;
  }

  Future<void> _startAddRouteFlow() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool('seen_create_route_tutorial') != true) {
      final tutorialLocale = ref.read(localeProvider).languageCode;
      await showTutorialSheet(
        context,
        title: AppStrings.get('tutorial_create_route_title', tutorialLocale),
        bullets: [
          AppStrings.get('tutorial_create_route_1', tutorialLocale),
          AppStrings.get('tutorial_create_route_2', tutorialLocale),
          AppStrings.get('tutorial_create_route_3', tutorialLocale),
          AppStrings.get('tutorial_create_route_4', tutorialLocale),
        ],
        icon: Icons.add_road,
        locale: tutorialLocale,
      );
      if (!mounted) return;
      await prefs.setBool('seen_create_route_tutorial', true);
    }

    final locale = ref.read(localeProvider).languageCode;

    final fromResult = await _pickRegionAndDistrict(AppStrings.get('from_question', locale));
    if (fromResult == null || !mounted) return;
    final (fromRegion, fromDistrict) = fromResult;

    final toResult = await _pickRegionAndDistrict(AppStrings.get('to_question', locale));
    if (toResult == null || !mounted) return;
    final (toRegion, toDistrict) = toResult;

    final routeName = '${fromDistrict.name} → ${toDistrict.name}';

    final duration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _UpdateDurationSheet(routeName: routeName, initial: 12),
    );
    if (duration == null || !mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _RouteConfirmSheet(routeName: routeName),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(driverRepositoryProvider).createDriverLine(
        fromRegionId: fromRegion.id, fromDistrictId: fromDistrict.id,
        toRegionId: toRegion.id, toDistrictId: toDistrict.id,
        durationHours: duration,
      );
      if (!mounted) return;
      _loadLines();
    } catch (e) {
      if (!mounted) return;
      _handleLineError(e);
    }
  }

  // ==== Mavjud yo'nalish: davomiylikni yangilash / qayta faollashtirish / o'chirish ====

  Future<void> _openDurationSheet(_DriverLineItem line) async {
    var initial = 12;
    if (line.expiresAt != null) {
      final remaining = line.expiresAt!.difference(DateTime.now()).inHours;
      initial = [6, 12, 24].reduce(
        (a, b) => (remaining - a).abs() <= (remaining - b).abs() ? a : b,
      );
    }
    final routeName = '${line.fromLabel}  →  ${line.toLabel}';

    final newDuration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _UpdateDurationSheet(routeName: routeName, initial: initial),
    );
    if (newDuration == null || !mounted) return;

    try {
      await ref.read(driverRepositoryProvider).updateDriverLine(line.id, newDuration);
      if (!mounted) return;
      _loadLines();
    } catch (e) {
      if (!mounted) return;
      _handleLineError(e);
    }
  }

  // Backend 'bad_request' bilan javob berganda, buni har doim "yo'nalish
  // faol emas" deb talqin qilmaydi — faqat backend xabari haqiqatan shu
  // sababni ko'rsatsa, inactive-sheet ko'rsatiladi; aks holda (masalan
  // davomiylik noto'g'ri formatda yoki boshqa tekshiruv xatosi bo'lsa)
  // umumiy xato xabari (generic_error) ko'rsatiladi.
  void _handleLineError(Object e) {
    if (e is DriverLineException && e.reasonKey == 'bad_request') {
      final msg = e.serverMessage;
      if (msg != null && _looksLikeInactiveRouteError(msg)) {
        _showInactiveSheet(message: msg);
        return;
      }
      _showErrorSnack(e);
      return;
    }
    _showErrorSnack(e is DriverLineException ? e : null);
  }

  Future<void> _deleteLine(_DriverLineItem line) async {
    final confirmed = await _showDeleteConfirmSheet();
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(driverRepositoryProvider).deleteDriverLine(line.id);
      if (!mounted) return;
      final locale = ref.read(localeProvider).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('route_deleted', locale)), backgroundColor: AppTheme.successColor),
      );
      _loadLines();
    } catch (_) {}
  }

  Future<bool?> _showDeleteConfirmSheet() {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              const Icon(Icons.delete_outline, size: 40, color: AppTheme.errorColor),
              const SizedBox(height: 12),
              Text(AppStrings.get('delete_route', locale),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: border),
                        foregroundColor: textPrimary,
                      ),
                      child: Text(AppStrings.get('cancel', locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(AppStrings.get('delete_route', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnack(DriverLineException? e) {
    final locale = ref.read(localeProvider).languageCode;
    String msg;
    switch (e?.reasonKey) {
      case 'timeout':
        msg = AppStrings.get('error_timeout', locale);
        break;
      case 'no_connection':
        msg = AppStrings.get('error_no_connection', locale);
        break;
      case 'server_error':
        msg = AppStrings.get('error_server', locale);
        break;
      default:
        msg = AppStrings.get('generic_error', locale);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
    );
  }

  Future<void> _showInactiveSheet({String? message}) async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              Text(
                AppStrings.get('route_inactive_title', locale),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? AppStrings.get('route_inactive_message', locale),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity, height: 50,
                  decoration: BoxDecoration(gradient: _kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: Text(
                      AppStrings.get('close', locale),
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
                    AppStrings.get('my_routes_label', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.help_outline, color: textSecondary, size: 20),
                    onPressed: _showRoutesTutorial,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCreateButton(locale, textPrimary, border, bg),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildBody(locale, isDark, textPrimary, textSecondary, border),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(String locale, Color textPrimary, Color border, Color bg) {
    return GestureDetector(
      onTap: _startAddRouteFlow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: Row(
          children: [
            const Icon(Icons.add_road, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.get('create_new_route', locale),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 13, color: textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String locale, bool isDark, Color textPrimary, Color textSecondary, Color border) {
    if (_loadingLines) {
      return ListView.builder(
        itemCount: 3,
        itemBuilder: (ctx, i) => _SkeletonLineCard(isDark: isDark),
      );
    }
    if (_lines.isEmpty) {
      return _buildEmptyState(locale, textSecondary);
    }
    return RefreshIndicator(
      onRefresh: _loadLines,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: _lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          final line = _lines[i];
          return _LineCard(
            line: line,
            isDark: isDark,
            locale: locale,
            onTapCard: () => _openDurationSheet(line),
            onDelete: () => _deleteLine(line),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String locale, Color textSecondary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signpost_outlined, size: 52, color: textSecondary.withOpacity(0.5)),
          const SizedBox(height: 14),
          Text(
            AppStrings.get('no_route_yet', locale),
            style: TextStyle(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _startAddRouteFlow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(gradient: _kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(AppStrings.get('add_route', locale), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final _DriverLineItem line;
  final bool isDark;
  final String locale;
  final VoidCallback onTapCard;
  final VoidCallback onDelete;

  const _LineCard({
    required this.line, required this.isDark, required this.locale,
    required this.onTapCard, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final expired = line.expired;

    final fromText = line.fromLabel.isNotEmpty ? line.fromLabel : AppStrings.get('resolving_label', locale);
    final toText = line.toLabel.isNotEmpty ? line.toLabel : AppStrings.get('resolving_label', locale);
    final validUntilText = line.expiresAt != null ? _formatDateTime(line.expiresAt!) : '';

    return GestureDetector(
      onTap: onTapCard,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: expired ? AppTheme.errorColor.withOpacity(0.5) : border, width: expired ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.alt_route, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$fromText → $toText',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                _LineMenuButton(locale: locale, isDark: isDark, onDelete: onDelete),
              ],
            ),
            if (expired) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.errorColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppStrings.get('route_expired_title', locale),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.errorColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: onTapCard,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(color: AppTheme.errorColor, borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(
                        AppStrings.get('reactivate_route', locale),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ] else if (validUntilText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 12, color: textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${AppStrings.get('active_until_label', locale)}: $validUntilText',
                    style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineMenuButton extends StatelessWidget {
  final String locale;
  final bool isDark;
  final VoidCallback onDelete;
  const _LineMenuButton({required this.locale, required this.isDark, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    return SizedBox(
      width: 32, height: 32,
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: textSecondary, size: 20),
        padding: EdgeInsets.zero,
        color: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (value) {
          if (value == 'delete') onDelete();
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
              const SizedBox(width: 10),
              Text(
                AppStrings.get('delete_route', locale),
                style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _RouteConfirmSheet extends ConsumerWidget {
  final String routeName;
  const _RouteConfirmSheet({required this.routeName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(gradient: _kPrimaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.get('route_confirm_title', locale),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              routeName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.get('route_confirm_desc', locale),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(gradient: _kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(
                    AppStrings.get('understood', locale),
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

class _UpdateDurationSheet extends ConsumerStatefulWidget {
  final String routeName;
  final int initial;
  const _UpdateDurationSheet({required this.routeName, required this.initial});

  @override
  ConsumerState<_UpdateDurationSheet> createState() => _UpdateDurationSheetState();
}

class _UpdateDurationSheetState extends ConsumerState<_UpdateDurationSheet> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Text(
              widget.routeName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.get('update_duration', locale),
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _DurationChip(label: AppStrings.get('hours_6', locale), selected: _selected == 6, isDark: isDark, onTap: () => setState(() => _selected = 6)),
                const SizedBox(width: 8),
                _DurationChip(label: AppStrings.get('hours_12', locale), selected: _selected == 12, isDark: isDark, onTap: () => setState(() => _selected = 12)),
                const SizedBox(width: 8),
                _DurationChip(label: AppStrings.get('hours_24', locale), selected: _selected == 24, isDark: isDark, onTap: () => setState(() => _selected = 24)),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context, _selected),
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(gradient: _kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(
                    AppStrings.get('save', locale),
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

class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _DurationChip({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppTheme.primaryColor : border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Yo'nalish kartasi o'rnida ko'rinadigan miltillovchi skelet — nom
/// o'rnida keng, sana o'rnida tor to'rtburchak.
class _SkeletonLineCard extends StatelessWidget {
  final bool isDark;
  const _SkeletonLineCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final highlight = isDark ? const Color(0xFF475569) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity, height: 16,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 10),
            Container(
              width: 120, height: 12,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}
