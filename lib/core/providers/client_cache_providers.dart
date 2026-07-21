import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/client_repository.dart';

// ============================================================================
// Client "Cache Provider" arxitekturasi
// ----------------------------------------------------------------------------
// driver_cache_providers.dart dagi bilan AYNAN BIR XIL naqsh — Client uchun.
// Har bir statik/kamdan-kam o'zgaradigan ma'lumot turi (profil, buyurtmalar
// tarixi, saqlangan manzillar, truck turlari) uchun ALOHIDA AsyncNotifierProvider.
// Bularning hammasi `autoDispose` EMAS — ya'ni bir marta yuklangandan keyin,
// xotirada saqlanadi (keepAlive). Shu sabab sahifadan chiqib qayta kirilganda,
// `build()` QAYTA ishlamaydi va yangi so'rov YUBORILMAYDI — keshdagi
// ma'lumot ko'rsatiladi.
//
// Yangilash mantig'i:
//   * refreshIfStale() — sahifa ochilganda (initState) chaqiriladi. Faqat
//     kesh muddati o'tgan (yoki avvalgi urinish xato bo'lgan) bo'lsa YANGI
//     so'rov yuboradi; aks holda hech narsa qilmaydi.
//   * forceRefresh()   — "pull to refresh" yoki ma'lumot o'zgargandan keyin
//     (masalan profil tahrirlangach) — DOIM yangilaydi. Eski ma'lumot yangisi
//     kelguncha ekranda qoladi (UI sakramaydi, RefreshIndicator o'z spinnerini
//     ko'rsatadi).
//
// Real-vaqt ekranlarga (client_home_screen.dart dagi faol buyurtma kuzatuvi,
// active_order_details_screen.dart dagi live tracking) ATAYLAB TEGILMAGAN —
// ular tez-tez o'zgaradigan holatni kuzatadi, 5 daqiqalik kesh ularni
// eskirtirib qo'yar edi.
// ============================================================================

/// Kesh muddati — shu vaqt ichida sahifa qayta ochilsa, yangi so'rov
/// yuborilmaydi.
const Duration kClientCacheDuration = Duration(minutes: 5);

/// Barcha Client kesh-provider'lari uchun umumiy asos. Konkret provider'lar
/// faqat [fetch] metodini (qaysi repository chaqiruvi ekanini) belgilaydi.
abstract class _CachedClientNotifier<T> extends AsyncNotifier<T> {
  DateTime? _lastFetched;

  /// Konkret ma'lumotni backend'dan olish — har bir provider o'zi belgilaydi.
  Future<T> fetch();

  @override
  Future<T> build() => _fetchAndStamp();

  Future<T> _fetchAndStamp() async {
    final data = await fetch();
    _lastFetched = DateTime.now();
    return data;
  }

  bool get _isStale =>
      _lastFetched == null ||
      DateTime.now().difference(_lastFetched!) > kClientCacheDuration;

  /// Sahifa ochilganda chaqiriladi. Dastlabki yuklash `build()` orqali bir
  /// marta ishlaydi; bu yerda faqat kesh eskirgan bo'lsa qayta yuklaymiz.
  Future<void> refreshIfStale() async {
    if (state.isLoading) return; // dastlabki yuklash hali davom etyapti
    if (_isStale) {
      state = await AsyncValue.guard(_fetchAndStamp);
    }
  }

  /// Majburiy yangilash (pull-to-refresh / ma'lumot o'zgargach). Eski
  /// ma'lumotni o'chirmaymiz — yangisi kelguncha ekranda ko'rinib turadi.
  Future<void> forceRefresh() async {
    state = await AsyncValue.guard(_fetchAndStamp);
  }
}

// ---------------------------------------------------------------------------
// Profil.
// ---------------------------------------------------------------------------
class ClientProfileNotifier extends _CachedClientNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> fetch() =>
      ref.read(clientRepositoryProvider).getProfile();
}

final clientProfileCacheProvider =
    AsyncNotifierProvider<ClientProfileNotifier, Map<String, dynamic>>(
  ClientProfileNotifier.new,
);

// ---------------------------------------------------------------------------
// Buyurtmalar tarixi (ClientOrdersScreen shu keshdan foydalanadi).
// ---------------------------------------------------------------------------
class ClientOrdersHistoryNotifier
    extends _CachedClientNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() =>
      ref.read(clientRepositoryProvider).getOrders();
}

final clientOrdersHistoryCacheProvider = AsyncNotifierProvider<
    ClientOrdersHistoryNotifier, List<Map<String, dynamic>>>(
  ClientOrdersHistoryNotifier.new,
);

// ---------------------------------------------------------------------------
// Saqlangan manzillar. SavedAddressesScreen (to'liq boshqaruv) va
// SelectAddressScreen (tezkor tanlash ro'yxati) shu keshni ulashadi.
// ---------------------------------------------------------------------------
class ClientSavedAddressesNotifier
    extends _CachedClientNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() =>
      ref.read(clientRepositoryProvider).getSavedAddresses();
}

final clientSavedAddressesCacheProvider = AsyncNotifierProvider<
    ClientSavedAddressesNotifier, List<Map<String, dynamic>>>(
  ClientSavedAddressesNotifier.new,
);

// ---------------------------------------------------------------------------
// Mashina turlari (truck types) — buyurtma yaratish formasida (OrderDetailsScreen)
// mashina turi tanlash uchun ishlatiladi. Global/statik konfiguratsiya
// ma'lumoti, kamdan-kam o'zgaradi.
// ---------------------------------------------------------------------------
class ClientTrucksNotifier
    extends _CachedClientNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() =>
      ref.read(clientRepositoryProvider).getTrucks();
}

final clientTrucksCacheProvider =
    AsyncNotifierProvider<ClientTrucksNotifier, List<Map<String, dynamic>>>(
  ClientTrucksNotifier.new,
);

// ---------------------------------------------------------------------------
// Bitta buyurtma tafsiloti (orderId bo'yicha). Yuqoridagilardan farqli —
// bu FAMILY: har bir orderId o'zining ALOHIDA keshiga ega (parametrsiz
// _CachedClientNotifier naqshiga sig'maydi, chunki u parametr qabul qilmaydi).
// Muddatli eskirish tekshiruvi yo'q (buyurtma statusi o'zgarishi mumkinligi
// sabab) — yangilash uchun pull-to-refresh'da ref.invalidate() ishlatiladi.
// driver_cache_providers.dart dagi driverOrderDetailProvider bilan bir xil naqsh.
// ---------------------------------------------------------------------------
final clientOrderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) {
  return ref.read(clientRepositoryProvider).getOrder(orderId);
});

/// Chiqishda (logout) barcha Client kesh'larini tozalash — keyingi (boshqa)
/// foydalanuvchi kirganida eski ma'lumot ko'rinib qolmasligi uchun.
void invalidateClientCaches(WidgetRef ref) {
  ref.invalidate(clientProfileCacheProvider);
  ref.invalidate(clientOrdersHistoryCacheProvider);
  ref.invalidate(clientSavedAddressesCacheProvider);
  ref.invalidate(clientTrucksCacheProvider);
  ref.invalidate(clientOrderDetailProvider);
}
