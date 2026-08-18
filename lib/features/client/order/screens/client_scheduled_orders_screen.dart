import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../shared/widgets/close_circle_button.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

// Qidiruv inputining fokus animatsiyasi (Telegram uslubida qisqarish/X
// tugmasi paydo bo'lishi) — butun animatsiya shu bitta davomiylik/egri
// chiziqda, silliq va izchil ko'rinishi uchun.
const Duration _kSearchAnimDuration = Duration(milliseconds: 260);
const Curve _kSearchAnimCurve = Curves.easeOutCubic;

/// Client o'zi rejalashtirgan (SCHEDULED holatidagi) buyurtmalari ro'yxati.
/// driver_scheduled_orders_screen.dart namuna sifatida olingan — "Bugun"/
/// "Ertaga" tablari, kartochka ko'rinishi va "Batafsil" bosilganda pastdan
/// chiquvchi tafsilotlar modali xuddi shu uslubda takrorlangan. Yo'nalish
/// filtri (driver sahifasidagi) bu yerda kerak emas — buning o'rniga
/// client_orders_screen.dart dagi shahar bo'yicha qidiruv maydoni
/// takrorlangan (driver sahifasida qidiruv maydoni yo'q).
///
/// Backend'da client buyurtmalari uchun status bo'yicha filtrlash
/// qo'llab-quvvatlamaydigan yagona `/orders/my` endpointi bor — shuning
/// uchun barcha buyurtmalar BIR MARTA yuklanadi, SCHEDULED holati va
/// kun (Bugun/Ertaga) ilovada filtrlanadi (kun almashtirilganda qayta
/// so'rov yuborilmaydi).
class ClientScheduledOrdersScreen extends ConsumerStatefulWidget {
  const ClientScheduledOrdersScreen({super.key});

  @override
  ConsumerState<ClientScheduledOrdersScreen> createState() => _ClientScheduledOrdersScreenState();
}

class _ClientScheduledOrdersScreenState extends ConsumerState<ClientScheduledOrdersScreen> {
  String _day = 'today';
  bool _loading = true;
  List<Map<String, dynamic>> _allOrders = [];
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';
  bool _searchActive = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _searchFocus.addListener(() {
      if (!mounted) return;
      setState(() => _searchActive = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(clientRepositoryProvider).getOrders();
      if (!mounted) return;
      setState(() {
        _allOrders = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ClientScheduledOrdersScreen] Rejalashtirilgan buyurtmalarni yuklashda xatolik: $e');
      if (mounted) setState(() { _allOrders = []; _loading = false; });
    }
  }

  void _switchDay(String day) {
    if (_day == day) return;
    setState(() => _day = day);
  }

  // X tugmasi bosilganda (matn bo'sh bo'lsa ham) — matn tozalanadi (agar
  // bor bo'lsa), fokus olib tashlanadi (klaviatura yopiladi, kursor
  // yo'qoladi). _searchActive holati _searchFocus listener orqali
  // avtomatik yangilanadi, shuning uchun bu yerda alohida setState shart
  // emas.
  void _clearSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
  }

  bool _matchesSearch(Map<String, dynamic> order) {
    if (_searchQuery.isEmpty) return true;
    final from = (order['fromCity'] as String? ?? '').toLowerCase();
    final to = (order['toCity'] as String? ?? '').toLowerCase();
    return from.contains(_searchQuery) || to.contains(_searchQuery);
  }

  List<Map<String, dynamic>> get _orders {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = _day == 'today' ? today : today.add(const Duration(days: 1));

    return _allOrders.where((o) {
      if ((o['status'] as String? ?? '') != 'SCHEDULED') return false;
      final scheduledFor = DateTime.tryParse(o['scheduledFor'] as String? ?? '')?.toLocal();
      if (scheduledFor == null) return false;
      final scheduledDate = DateTime(scheduledFor.year, scheduledFor.month, scheduledFor.day);
      if (scheduledDate != targetDate) return false;
      return _matchesSearch(o);
    }).toList();
  }

  Future<void> _openDetail(Map<String, dynamic> order) async {
    // Qidiruv inputi fokusda bo'lsa (klaviatura ochiq) ham, detail modal
    // ustiga ochilganda orqada osilib qolmasligi uchun oldindan unfocus
    // qilinadi — bottom-sheet o'z ustida yangi TextField so'ramaydi,
    // shuning uchun bu qadam bo'lmasa klaviatura fonda ochiq qolishi mumkin.
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _ClientOrderDetailSheet(
        order: order,
        onCancelled: () {
          _load();
          if (!mounted) return;
          final locale = ref.read(localeProvider).languageCode;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.get('order_cancelled', locale)), backgroundColor: AppTheme.successColor),
          );
        },
        onAlreadyAccepted: () {
          _load();
          if (!mounted) return;
          final locale = ref.read(localeProvider).languageCode;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.get('order_already_accepted_error', locale)), backgroundColor: AppTheme.warningColor),
          );
        },
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
    final closeBtnBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    final orders = _orders;

    return Scaffold(
      backgroundColor: surface,
      // Input tashqarisiga bosilganda ham fokus olib tashlanishi
      // (klaviatura yopilishi, input original holatiga qaytishi) uchun —
      // translucent bo'lgani sababli pastdagi kartochka/tugma taplari
      // to'sqinlik qilmaydi, TextField'ning o'ziga bosilganda esa fokus
      // so'rovi ustunlik qiladi (shuning uchun darhol qayta unfocus
      // bo'lib qolmaydi).
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
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
                    AppStrings.get('scheduled_orders_title', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _DayTab(
                      label: AppStrings.get('today_tab', locale),
                      selected: _day == 'today',
                      isDark: isDark,
                      onTap: () => _switchDay('today'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DayTab(
                      label: AppStrings.get('tomorrow_tab', locale),
                      selected: _day == 'tomorrow',
                      isDark: isDark,
                      onTap: () => _switchDay('tomorrow'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        style: TextStyle(fontSize: 14, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('search_city_hint', locale),
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
                  // X tugmasi — input fokusda bo'lganda "o'ngdan sirg'alib
                  // chiqadi" (widthFactor 0->1 + slide + fade, hammasi bir
                  // xil davomiylikda). ClipRect + AnimatedAlign(widthFactor)
                  // — tugma o'z tabiiy o'lchamini saqlab, faqat ajratilgan
                  // joy silliq o'sib/qisqaradi, shu bilan qo'shni qidiruv
                  // maydoni (Expanded) har kadrda avtomatik moslashadi va
                  // layout sakramaydi.
                  ClipRect(
                    child: AnimatedAlign(
                      duration: _kSearchAnimDuration,
                      curve: _kSearchAnimCurve,
                      alignment: Alignment.centerRight,
                      widthFactor: _searchActive ? 1.0 : 0.0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IgnorePointer(
                          ignoring: !_searchActive,
                          child: AnimatedSlide(
                            duration: _kSearchAnimDuration,
                            curve: _kSearchAnimCurve,
                            offset: _searchActive ? Offset.zero : const Offset(0.4, 0),
                            child: AnimatedOpacity(
                              duration: _kSearchAnimDuration,
                              curve: _kSearchAnimCurve,
                              opacity: _searchActive ? 1 : 0,
                              child: GestureDetector(
                                onTap: _clearSearch,
                                child: Container(
                                  width: 40, height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: closeBtnBg, shape: BoxShape.circle),
                                  child: Icon(Icons.close, size: 18, color: textSecondary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: 4,
                      itemBuilder: (ctx, i) => _SkeletonOrderCard(isDark: isDark),
                    )
                  : orders.isEmpty
                      ? _EmptyState(
                          locale: locale, textSecondary: textSecondary,
                          icon: Icons.event_busy_outlined,
                          text: AppStrings.get('no_scheduled_orders', locale),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: orders.length,
                            itemBuilder: (ctx, i) {
                              final order = orders[i];
                              return _ClientScheduledOrderCard(
                                order: order,
                                isDark: isDark,
                                locale: locale,
                                surface: surface,
                                border: border,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                onDetail: () => _openDetail(order),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

String _formatTime(dynamic iso) {
  if (iso is! String) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// Narxni "1 502 000" uslubida mingliklarga ajratib ko'rsatadi (bo'sh joy
// bilan) — manfiy/kasr qism kutilmaydi (narx doim butun so'm), shuning
// uchun faqat .toInt() qilingan qism formatlanadi.
String _formatPrice(num price) {
  final digits = price.toInt().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

final RegExp _kApostropheRegex = RegExp("['‘’´`ʻʼ]");

// Geokodlangan uzun manzil satrini ("O'zbekiston, Farg'ona viloyati,
// Toshloq tumani, Mustaqillik ko'chasi, 15") qisqartiradi — davlat nomi
// ("O'zbekiston") va viloyat/shahar darajasidagi yuqori segmentlar
// ("... viloyati", "... shahri" bilan tugaydigan qismlar) olib
// tashlanadi, qolgan (tuman, mahalla, ko'cha kabi) aniqroq qismlar
// saqlanadi. Kutilmagan formatda (vergulsiz yoki bo'sh) o'zgarishsiz
// qaytadi — sinmasligi shart.
String _shortenAddress(String? address) {
  if (address == null) return '-';
  final trimmed = address.trim();
  if (trimmed.isEmpty) return '-';
  final parts = trimmed.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length <= 1) return trimmed;

  final filtered = parts.where((p) {
    final normalized = p.toLowerCase().replaceAll(_kApostropheRegex, '');
    if (normalized == 'ozbekiston' || normalized == 'uzbekistan' || normalized == 'узбекистан') {
      return false;
    }
    if (normalized.endsWith('viloyati') || normalized.endsWith('shahri')) return false;
    return true;
  }).toList();

  final result = filtered.isNotEmpty ? filtered : parts;
  return result.join(', ');
}

class _DayTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _DayTab({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.transparent : border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String locale;
  final Color textSecondary;
  final IconData icon;
  final String text;
  const _EmptyState({required this.locale, required this.textSecondary, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: textSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ClientScheduledOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  final String locale;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onDetail;

  const _ClientScheduledOrderCard({
    required this.order, required this.isDark, required this.locale,
    required this.surface, required this.border, required this.textPrimary,
    required this.textSecondary, required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final fromCity = order['fromCity'] as String? ?? '';
    final toCity = order['toCity'] as String? ?? '';
    final price = (order['price'] as num?) ?? 0;
    final timeText = _formatTime(order['scheduledFor']);
    final priceText = price > 0
        ? '${_formatPrice(price)} so\'m'
        : AppStrings.get('price_not_set', locale);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.25 : 0.06), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (timeText.isNotEmpty) ...[
                const Icon(Icons.access_time, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(timeText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
              ],
              const Spacer(),
              Text(priceText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Column(children: [
                const Icon(Icons.local_shipping, size: 14, color: AppTheme.primaryColor),
                Container(width: 1, height: 12, color: border),
                const Icon(Icons.flag, size: 14, color: AppTheme.successColor),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fromCity, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(toCity, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDetail,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: AppTheme.primaryColor),
                foregroundColor: AppTheme.primaryColor,
              ),
              child: Text(AppStrings.get('order_details', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buyurtma kartasi o'rnida ko'rinadigan miltillovchi skelet.
class _SkeletonOrderCard extends StatelessWidget {
  final bool isDark;
  const _SkeletonOrderCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final highlight = isDark ? const Color(0xFF475569) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 60, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              const Spacer(),
              Container(width: 70, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ]),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(width: 140, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}

/// Rejalashtirilgan buyurtmaning to'liq tafsilotlari. Ko'rsatish bilan
/// bir qatorda endi bitta amal ham bor — bekor qilish ("Bekor qilish"
/// pastda, kamtarona matn tugma; bosilganda tasdiq modali so'raladi).
class _ClientOrderDetailSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onCancelled;
  // Backend 'order_already_accepted' bilan rad etsa — buyurtma haqiqatan
  // bekor QILINMAGAN, lekin driver allaqachon biriktirilgani uchun u endi
  // "rejalashtirilgan" holatda emas, shuning uchun bu ham detail modalni
  // yopib, ro'yxatni yangilashni talab qiladi (faqat boshqa xabar bilan).
  final VoidCallback onAlreadyAccepted;
  const _ClientOrderDetailSheet({
    required this.order,
    required this.onCancelled,
    required this.onAlreadyAccepted,
  });

  @override
  ConsumerState<_ClientOrderDetailSheet> createState() => _ClientOrderDetailSheetState();
}

class _ClientOrderDetailSheetState extends ConsumerState<_ClientOrderDetailSheet> {
  // Tasdiq modali o'zi bekor qilish so'rovini yuboradi va faqat aniq bir
  // natija bilan yopiladi: 'cancelled' (muvaffaqiyatli bekor qilindi),
  // 'already_accepted' (driver allaqachon qabul qilgan — baribir ro'yxatdan
  // olib tashlanishi kerak), yoki null (xato ko'rsatilib sheet ochiq
  // qoladi, yoki foydalanuvchi "Yo'q"/tashqariga bosdi — bu holatlarda
  // hech narsa qilinmaydi).
  Future<void> _confirmCancel() async {
    final orderId = widget.order['id'] as String? ?? '';
    if (orderId.isEmpty) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _CancelConfirmSheet(orderId: orderId),
    );
    if (!mounted || result == null) return;
    Navigator.pop(context);
    if (result == 'already_accepted') {
      widget.onAlreadyAccepted();
    } else {
      widget.onCancelled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final bgCard = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);
    final tabBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    final fromAddressRaw = (order['fromAddress'] as String?)?.isNotEmpty == true
        ? order['fromAddress'] as String
        : (order['fromCity'] as String? ?? '-');
    final toAddressRaw = (order['toAddress'] as String?)?.isNotEmpty == true
        ? order['toAddress'] as String
        : (order['toCity'] as String? ?? '-');
    final fromAddress = _shortenAddress(fromAddressRaw);
    final toAddress = _shortenAddress(toAddressRaw);
    final truckType = order['truckType'] as String? ?? '-';
    final weight = order['weight'];
    final loadType = order['loadType'] as String?;
    final loadTypeLabel = loadType == 'TOP'
        ? AppStrings.get('load_from_top', locale)
        : (loadType == 'BACK' ? AppStrings.get('load_from_back', locale) : null);
    final cargoType = order['cargoType'] as String?;
    final price = (order['price'] as num?) ?? 0;
    final distance = order['distance'] as num?;
    final note = order['note'] as String?;
    final timeText = _formatTime(order['scheduledFor']);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(AppStrings.get('order_detail_title', locale),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
                ),
                CloseCircleButton(
                  bg: tabBg, iconColor: textSecondary,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.local_shipping, label: AppStrings.get('from_label', locale), value: fromAddress,
                bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            const SizedBox(height: 12),
            _DetailRow(icon: Icons.flag, label: AppStrings.get('to_label', locale), value: toAddress,
                bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            if (timeText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.access_time, label: AppStrings.get('scheduled_time_label', locale), value: timeText,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            ],
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.local_shipping_outlined,
              label: AppStrings.get('vehicle_type_label', locale),
              value: truckType,
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
              stacked: true,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.scale_outlined,
              label: AppStrings.get('weight_label', locale),
              value: weight != null ? '$weight t' : '-',
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
            ),
            if (loadTypeLabel != null) ...[
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.swap_vert, label: AppStrings.get('load_type_label', locale), value: loadTypeLabel,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            ],
            if (cargoType != null && cargoType.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.inventory_2_outlined, label: AppStrings.get('cargo_type_label', locale), value: cargoType,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            ],
            if (distance != null) ...[
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.route_outlined, label: AppStrings.get('route_distance_label', locale), value: '${distance.toStringAsFixed(1)} km',
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            ],
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.payments_outlined,
              label: AppStrings.get('price_label', locale),
              value: price > 0 ? '${_formatPrice(price)} so\'m' : AppStrings.get('price_not_set', locale),
              bg: bgCard, border: border, textP: textPrimary, textS: textSecondary,
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.notes_outlined, label: AppStrings.get('note_label', locale), value: note,
                  bg: bgCard, border: border, textP: textPrimary, textS: textSecondary),
            ],
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: _confirmCancel,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: Text(
                  AppStrings.get('cancel', locale),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bekor qilishni tasdiqlash — pastdan chiquvchi ogohlantirish modali.
/// So'rovning o'zi shu yerda yuboriladi (Navigator.pop bilan bo'sh bool
/// qaytarish o'rniga), shunda "Ha" tugmasi so'rov ketayotganda o'zining
/// loading holatini ko'rsatadi va modal FAQAT muvaffaqiyatda yopiladi —
/// xato bo'lsa shu yerning o'zida ko'rsatiladi, buyurtma o'z o'rnida
/// qoladi.
class _CancelConfirmSheet extends ConsumerStatefulWidget {
  final String orderId;
  const _CancelConfirmSheet({required this.orderId});

  @override
  ConsumerState<_CancelConfirmSheet> createState() => _CancelConfirmSheetState();
}

class _CancelConfirmSheetState extends ConsumerState<_CancelConfirmSheet> {
  bool _loading = false;
  // Sheet o'zi bottom-sheet ustida chiqadi — ScaffoldMessenger orqali
  // SnackBar chiqarilsa, u aynan shu sheet orqasida yashiringan bo'lib,
  // foydalanuvchiga ko'rinmay qoladi. Shuning uchun xato matni shu
  // yerning o'zida, tugmalar ustida ko'rsatiladi.
  String? _errorMessage;

  Future<void> _confirm() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final locale = ref.read(localeProvider).languageCode;
    try {
      await ref.read(clientRepositoryProvider).cancelScheduledOrder(widget.orderId);
      if (!mounted) return;
      Navigator.pop(context, 'cancelled');
    } on OrderCancelException catch (e) {
      if (!mounted) return;
      if (e.reasonKey == 'order_already_accepted') {
        // Buyurtma bekor qilinmadi, lekin driver allaqachon qabul qilgani
        // uchun u baribir "rejalashtirilgan" ro'yxatida qolmasligi kerak —
        // chaqiruvchi (detail sheet) shu holatni alohida xabar bilan
        // ko'rsatadi, shuning uchun bu yerda xato ko'rsatilmaydi.
        Navigator.pop(context, 'already_accepted');
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = e.reasonKey == 'order_not_cancelable'
            ? AppStrings.get('order_not_cancelable_error', locale)
            : AppStrings.get('generic_error', locale);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = AppStrings.get('generic_error', locale);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return PopScope(
      canPop: !_loading,
      child: SafeArea(
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
                width: 52, height: 52,
                decoration: BoxDecoration(color: AppTheme.errorColor.withOpacity(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.event_busy_outlined, color: AppTheme.errorColor, size: 28),
              ),
              const SizedBox(height: 14),
              Text(AppStrings.get('cancel_order_title', locale),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 8),
              Text(AppStrings.get('cancel_scheduled_order_message', locale),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4)),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.errorColor, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: border),
                        foregroundColor: textPrimary,
                      ),
                      child: Text(AppStrings.get('no_keep_order', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : Text(AppStrings.get('yes_cancel_order', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
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
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color bg;
  final Color border;
  final Color textP;
  final Color textS;
  // true bo'lsa, qiymat sarlavha ostida (kichikroq fontda, unga yaqin)
  // ko'rsatiladi — label bilan qatorda emas. Uzun/kelajakda uzayadigan
  // qiymatlar (masalan mashina turi) uchun, to'liq qator kengligida
  // 2 qatorgacha o'ralishi kerak bo'lganda ishlatiladi.
  final bool stacked;

  const _DetailRow({
    required this.icon, required this.label, required this.value,
    required this.bg, required this.border, required this.textP, required this.textS,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 0.5)),
      child: stacked
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13, color: textS)),
                      const SizedBox(height: 3),
                      Text(value,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textP),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            )
          : Row(children: [
              Icon(icon, size: 18, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: textS))),
              Flexible(
                child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textP),
                    textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ]),
    );
  }
}
