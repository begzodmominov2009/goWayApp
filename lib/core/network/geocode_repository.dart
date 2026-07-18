import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final geocodeRepositoryProvider = Provider<GeocodeRepository>((ref) {
  return GeocodeRepository(ref.watch(dioProvider));
});

class GeocodeResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double? distanceKm;

  GeocodeResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.distanceKm,
  });

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      distanceKm: json['distanceKm'] != null
          ? (json['distanceKm'] as num).toDouble()
          : null,
    );
  }
}

class ReverseGeocodeResult {
  final String city;
  final String street;
  final String fullAddr;

  ReverseGeocodeResult({
    required this.city,
    required this.street,
    required this.fullAddr,
  });

  factory ReverseGeocodeResult.fromJson(Map<String, dynamic> json) {
    return ReverseGeocodeResult(
      city: json['city'] as String? ?? '',
      street: json['street'] as String? ?? '',
      fullAddr: json['fullAddr'] as String? ?? '',
    );
  }
}

class RouteResult {
  final double distanceKm;
  final int durationMin;
  final String durationText;
  final List<List<double>> points;

  RouteResult({
    required this.distanceKm,
    required this.durationMin,
    required this.durationText,
    required this.points,
  });
}

/// Backend'dagi /geocode/* endpointlariga native (Dio) orqali murojaat
/// qiluvchi klass. Bu — veb versiyadagi JS (Yandex JS API) o'rniga,
/// Android/iOS uchun to'g'ridan-to'g'ri REST chaqiruvlar orqali ishlaydi.
class GeocodeRepository {
  final Dio _dio;
  GeocodeRepository(this._dio);

  /// Koordinatdan manzil nomini olish (reverse geocoding)
  Future<ReverseGeocodeResult> reverse(double lat, double lng) async {
    try {
      final res = await _dio.get('/geocode/reverse', queryParameters: {
        'lat': lat,
        'lng': lng,
      });
      return ReverseGeocodeResult.fromJson(res.data);
    } catch (_) {
      return ReverseGeocodeResult(city: '', street: '', fullAddr: '');
    }
  }

  /// Matn orqali manzil qidirish
  Future<List<GeocodeResult>> search(
    String query, {
    double? lat,
    double? lng,
    int limit = 5,
  }) async {
    try {
      final res = await _dio.get('/geocode/search', queryParameters: {
        'q': query,
        'limit': limit,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      final list = res.data['results'] as List? ?? [];
      return list
          .map((e) => GeocodeResult.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Ikki nuqta orasidagi haqiqiy yo'l chizig'i, masofa va vaqtni
  /// backend orqali (OpenRouteService asosida) oladi. API kalit
  /// xavfsizlik uchun faqat backend'da saqlanadi — Flutter'dan
  /// tashqi xizmatga to'g'ridan-to'g'ri so'rov yuborilmaydi.
  Future<RouteResult?> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    try {
      final res = await _dio.get('/geocode/route', queryParameters: {
        'fromLat': fromLat,
        'fromLng': fromLng,
        'toLat': toLat,
        'toLng': toLng,
      });
      final data = res.data;

      if (data['success'] == false || data['points'] == null) return null;

      final pointsRaw = data['points'] as List;
      final points = pointsRaw
          .map<List<double>>((p) => [
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ])
          .toList();

      final distanceKm = (data['distanceKm'] as num).toDouble();
      final durationMin = (data['durationMin'] as num).toInt();

      final h = durationMin ~/ 60;
      final m = durationMin % 60;
      final durationText = h > 0 ? '$h soat $m daqiqa' : '$m daqiqa';

      return RouteResult(
        distanceKm: distanceKm,
        durationMin: durationMin,
        durationText: durationText,
        points: points,
      );
    } catch (_) {
      return null;
    }
  }
}