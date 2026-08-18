import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final geoRepositoryProvider = Provider<GeoRepository>((ref) {
  return GeoRepository(ref.watch(dioProvider));
});

class GeoRegion {
  final String id;
  final String name;
  final bool isActive;
  final double? centerLatitude;
  final double? centerLongitude;

  GeoRegion({
    required this.id,
    required this.name,
    required this.isActive,
    this.centerLatitude,
    this.centerLongitude,
  });

  factory GeoRegion.fromJson(Map<String, dynamic> json) {
    return GeoRegion(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? false,
      centerLatitude: json['centerLatitude'] != null
          ? (json['centerLatitude'] as num).toDouble()
          : null,
      centerLongitude: json['centerLongitude'] != null
          ? (json['centerLongitude'] as num).toDouble()
          : null,
    );
  }
}

class GeoDistrict {
  final String id;
  final String name;
  final bool isActive;
  final String type;
  final double? centerLatitude;
  final double? centerLongitude;

  GeoDistrict({
    required this.id,
    required this.name,
    required this.isActive,
    required this.type,
    this.centerLatitude,
    this.centerLongitude,
  });

  factory GeoDistrict.fromJson(Map<String, dynamic> json) {
    return GeoDistrict(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? false,
      type: json['type'] as String? ?? '',
      centerLatitude: json['centerLatitude'] != null
          ? (json['centerLatitude'] as num).toDouble()
          : null,
      centerLongitude: json['centerLongitude'] != null
          ? (json['centerLongitude'] as num).toDouble()
          : null,
    );
  }
}

/// /check-point javobi — bitta nuqta (koordinata/nom) qaysi viloyatga
/// tegishli va u faolmi, backend order-errors.ts/geo.controller.ts bilan
/// bir xil reasonKey qiymatlarini qaytaradi ('location_unresolved' —
/// hech qaysi viloyatga bog'lanmadi, 'region_inactive' — viloyat
/// aniqlandi lekin hali faol emas, active bo'lsa reasonKey null).
class CheckPointResult {
  final bool active;
  final String? regionId;
  final String? regionName;
  final String? reasonKey;

  CheckPointResult({
    required this.active,
    this.regionId,
    this.regionName,
    this.reasonKey,
  });

  factory CheckPointResult.fromJson(Map<String, dynamic> json) => CheckPointResult(
        active: json['active'] as bool? ?? false,
        regionId: json['regionId'] as String?,
        regionName: json['regionName'] as String?,
        reasonKey: json['reasonKey'] as String?,
      );
}

/// Backend'dagi /regions/* endpointlariga murojaat qiluvchi klass —
/// buyurtma yaratishda va haydovchi liniyasini belgilashda viloyat va
/// tuman tanlash bosqichlari uchun ishlatiladi.
class GeoRepository {
  final Dio _dio;
  GeoRepository(this._dio);

  // Manzil tanlangan zahoti (forma to'ldirilayotganda, ikkinchi nuqta
  // hali bo'sh bo'lsa ham) bitta nuqtani darhol tekshiradi — createOrder
  // bilan AYNAN bir xil qaror (backendda bir xil resolveRegion). Tarmoq
  // xatosida null qaytadi — chaqiruvchi taraf shu holatda ogohlantirishni
  // o'tkazib yuboradi, buyurtma yaratishdagi mavjud tekshiruv (400 +
  // reasonKey) baribir ushlab qoladi.
  Future<CheckPointResult?> checkPoint({
    double? latitude,
    double? longitude,
    String? name,
  }) async {
    try {
      final res = await _dio.post('/check-point', data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (name != null) 'name': name,
      });
      return CheckPointResult.fromJson(Map<String, dynamic>.from(res.data['data']));
    } catch (_) {
      return null;
    }
  }

  Future<List<GeoRegion>> getAllRegions() async {
    try {
      final res = await _dio.get('/regions/all');
      final list = res.data['data'] as List? ?? [];
      return list
          .map((e) => GeoRegion.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<GeoDistrict>> getAllDistricts(String regionId) async {
    try {
      final res = await _dio.get('/regions/$regionId/districts/all');
      final list = res.data['data'] as List? ?? [];
      return list
          .map((e) => GeoDistrict.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
