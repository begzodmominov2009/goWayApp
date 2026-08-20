import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/driver_repository.dart';
import '../network/geo_repository.dart';

// ============================================================================
// Driver "Cache Provider" arxitekturasi
// ----------------------------------------------------------------------------
// Har bir Driver ma'lumot turi (profil, hamyon, buyurtmalar tarixi, balans
// to'ldirish so'rovlari) uchun ALOHIDA AsyncNotifierProvider. Bularning
// hammasi `autoDispose` EMAS — ya'ni bir marta yuklangandan keyin, xotirada
// saqlanadi (keepAlive). Shu sabab sahifadan chiqib qayta kirilganda,
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
// ============================================================================

/// Kesh muddati — shu vaqt ichida sahifa qayta ochilsa, yangi so'rov
/// yuborilmaydi.
const Duration kDriverCacheDuration = Duration(minutes: 5);

/// Barcha Driver kesh-provider'lari uchun umumiy asos. Konkret provider'lar
/// faqat [fetch] metodini (qaysi repository chaqiruvi ekanini) belgilaydi.
abstract class _CachedDriverNotifier<T> extends AsyncNotifier<T> {
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
      DateTime.now().difference(_lastFetched!) > kDriverCacheDuration;

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
// Profil (+ mashina turlari). Profil sahifasi mashina turi dropdown'i uchun
// `getTrucks()` ni ham ishlatadi, shuning uchun ikkalasi birga (parallel)
// yuklanadi va birga keshlanadi.
// ---------------------------------------------------------------------------
class DriverProfileNotifier extends _CachedDriverNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> fetch() async {
    final repo = ref.read(driverRepositoryProvider);
    final profileFuture = repo.getProfile();
    final trucksFuture = repo.getTrucks();
    return {
      'profile': await profileFuture,
      'trucks': await trucksFuture,
    };
  }
}

final driverProfileCacheProvider =
    AsyncNotifierProvider<DriverProfileNotifier, Map<String, dynamic>>(
  DriverProfileNotifier.new,
);

// ---------------------------------------------------------------------------
// Hamyon oilasi (balans + statistika + tranzaksiyalar). Backend'da alohida
// "wallet" endpoint YO'Q — `getHistory()` stats/transactions/orders larni
// birga qaytaradi. Hamyon va Tranzaksiyalar tarixi sahifalari shu keshdan
// foydalanadi (biridan ikkinchisiga o'tilganda yangi so'rov ketmaydi).
// ---------------------------------------------------------------------------
class DriverWalletNotifier extends _CachedDriverNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> fetch() =>
      ref.read(driverRepositoryProvider).getHistory();
}

final driverWalletCacheProvider =
    AsyncNotifierProvider<DriverWalletNotifier, Map<String, dynamic>>(
  DriverWalletNotifier.new,
);

// ---------------------------------------------------------------------------
// Buyurtmalar tarixi oilasi. `getHistory()` dan 'orders' ishlatiladi. Hamyon
// bilan bir xil endpoint, ammo buyurtma tarixi alohida bo'lim bo'lgani uchun
// o'z keshiga ega (Tarix va To'liq tarix sahifalari shu keshni ulashadi).
// ---------------------------------------------------------------------------
class DriverHistoryNotifier extends _CachedDriverNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> fetch() =>
      ref.read(driverRepositoryProvider).getHistory();
}

final driverHistoryCacheProvider =
    AsyncNotifierProvider<DriverHistoryNotifier, Map<String, dynamic>>(
  DriverHistoryNotifier.new,
);

// ---------------------------------------------------------------------------
// Balans to'ldirish so'rovlari tarixi.
// ---------------------------------------------------------------------------
class DriverTopupHistoryNotifier
    extends _CachedDriverNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() =>
      ref.read(driverRepositoryProvider).getTopupHistory();
}

final driverTopupHistoryCacheProvider = AsyncNotifierProvider<
    DriverTopupHistoryNotifier, List<Map<String, dynamic>>>(
  DriverTopupHistoryNotifier.new,
);

// ---------------------------------------------------------------------------
// Barcha viloyatlar ro'yxati (GET /regions/all) — region_picker_page.dart
// (RegionPickerPage) shu keshdan foydalanadi. client_cache_providers.dart
// dagi clientRegionsCacheProvider bilan bir xil ma'lumot/endpoint — ammo
// bu yerda Driver'ning o'z kesh naqshi (_CachedDriverNotifier) ishlatiladi,
// chunki u shu faylga xos (private) va Client'niki bilan ulashilmaydi.
// ---------------------------------------------------------------------------
class DriverRegionsNotifier extends _CachedDriverNotifier<List<GeoRegion>> {
  @override
  Future<List<GeoRegion>> fetch() => ref.read(geoRepositoryProvider).getAllRegions();
}

final driverRegionsCacheProvider =
    AsyncNotifierProvider<DriverRegionsNotifier, List<GeoRegion>>(
  DriverRegionsNotifier.new,
);

// ---------------------------------------------------------------------------
// Bitta buyurtma tafsiloti (orderId bo'yicha). Yuqoridagilardan farqli —
// bu FAMILY: har bir orderId o'zining ALOHIDA keshiga ega (parametrsiz
// _CachedDriverNotifier naqshiga sig'maydi, chunki u parametr qabul qilmaydi).
// Muddatli eskirish tekshiruvi yo'q (buyurtma statusi o'zgarishi mumkinligi
// sabab) — yangilash uchun pull-to-refresh'da ref.invalidate() ishlatiladi.
// ---------------------------------------------------------------------------
final driverOrderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) {
  return ref.read(driverRepositoryProvider).getOrder(orderId);
});

/// Chiqishda (logout) barcha Driver kesh'larini tozalash — keyingi (boshqa)
/// foydalanuvchi kirganida eski ma'lumot ko'rinib qolmasligi uchun.
void invalidateDriverCaches(WidgetRef ref) {
  ref.invalidate(driverProfileCacheProvider);
  ref.invalidate(driverWalletCacheProvider);
  ref.invalidate(driverHistoryCacheProvider);
  ref.invalidate(driverTopupHistoryCacheProvider);
  ref.invalidate(driverRegionsCacheProvider);
  ref.invalidate(driverOrderDetailProvider);
}
