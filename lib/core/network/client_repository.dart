import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  return ClientRepository(ref.watch(dioProvider));
});

/// Buyurtma yaratishda xato yuz berganda aniq sabab bilan tashlanadi —
/// chaqiruvchi taraf (UI) shu asosda foydalanuvchiga tushunarli xabar
/// ko'rsatishi mumkin. `reasonKey` — AppStrings kalitiga mos keladigan
/// tur (masalan 'no_connection', 'timeout', 'server_error').
class OrderCreationException implements Exception {
  final String reasonKey;
  final String debugMessage;
  // Backend 'bad_request' (masalan yo'nalish hozircha faol emas) qaytarganda
  // javob tanasidagi aniq 'message' matni — UI shu matnni to'g'ridan-to'g'ri
  // ko'rsatishi mumkin (masalan "Toshkent yo'nalishingiz hali faol emas").
  final String? serverMessage;
  OrderCreationException(this.reasonKey, this.debugMessage, {this.serverMessage});

  @override
  String toString() => 'OrderCreationException($reasonKey): $debugMessage';
}

class ClientRepository {
  final Dio _dio;
  ClientRepository(this._dio);

  // Trucklar
  Future<List<Map<String, dynamic>>> getTrucks() async {
    final res = await _dio.get('/trucks');
    final list = res.data['data'] as List;
    return list
        .map((e) => Map<String, dynamic>.from(e))
        .where((t) => t['isActive'] == true)
        .toList();
  }

  // Buyurtma yaratish
  Future<Map<String, dynamic>> createOrder({
    required String fromCity,
    required String toCity,
    String? fromAddress,
    String? toAddress,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    required String truckType,
    required double weight,
    String? cargoType,
    String? note,
    String priority = 'STANDARD',
    bool isScheduled = false,
    DateTime? scheduledFor,
  }) async {
    debugPrint('[ClientRepository] Order so\'rovi yuborilmoqda... (truckType=$truckType, weight=$weight)');
    try {
      final res = await _dio.post(
        '/orders',
        data: {
          'fromCity': fromCity,
          'toCity': toCity,
          'fromAddress': fromAddress ?? '',
          'toAddress': toAddress ?? '',
          if (fromLatitude != null) 'fromLatitude': fromLatitude,
          if (fromLongitude != null) 'fromLongitude': fromLongitude,
          if (toLatitude != null) 'toLatitude': toLatitude,
          if (toLongitude != null) 'toLongitude': toLongitude,
          'truckType': truckType,
          'weight': weight,
          if (cargoType != null && cargoType.isNotEmpty) 'cargoType': cargoType,
          if (note != null && note.isNotEmpty) 'note': note,
          'priority': priority,
          'isScheduled': isScheduled,
          if (scheduledFor != null) 'scheduledFor': scheduledFor.toIso8601String(),
        },
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      debugPrint('[ClientRepository] Order so\'rovi javob berdi: ${res.statusCode}');
      return Map<String, dynamic>.from(res.data['data']);
    } on DioException catch (e) {
      debugPrint('[ClientRepository] Order so\'rovi xato bilan yakunlandi: ${e.type} — ${e.message}');
      throw _mapOrderError(e);
    }
  }

  // Buyurtma yaratishdan oldin taxminiy narxni hisoblash
  Future<double?> calculatePrice({
    required String truckType,
    required double distance,
    required double weight,
    String priority = 'STANDARD',
  }) async {
    try {
      final res = await _dio.get('/orders/calculate-price', queryParameters: {
        'truckType': truckType,
        'distance': distance.toString(),
        'weight': weight.toString(),
        'priority': priority,
      });
      return (res.data['data']['price'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  OrderCreationException _mapOrderError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return OrderCreationException('timeout', e.message ?? 'Timeout');
      case DioExceptionType.connectionError:
        return OrderCreationException('no_connection', e.message ?? 'Connection error');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status != null && status >= 500) {
          return OrderCreationException('server_error', 'HTTP $status');
        }
        final data = e.response?.data;
        final serverMsg = (data is Map && data['message'] is String) ? data['message'] as String : null;
        return OrderCreationException('bad_request', 'HTTP $status', serverMessage: serverMsg);
      default:
        return OrderCreationException('unknown', e.message ?? e.toString());
    }
  }

  // Buyurtmalar tarixi
  Future<List<Map<String, dynamic>>> getOrders() async {
    final res = await _dio.get('/orders/my');
    final list = res.data['data'] as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // Buyurtma detail
  Future<Map<String, dynamic>> getOrder(String orderId) async {
    final res = await _dio.get('/orders/$orderId');
    return Map<String, dynamic>.from(res.data['data']);
  }

  // Buyurtmani bekor qilish
  Future<void> cancelOrder(String orderId) async {
    await _dio.post('/orders/$orderId/cancel');
  }

  // Profil
  Future<Map<String, dynamic>> getProfile() async {
    final res = await _dio.get('/client/profile');
    return Map<String, dynamic>.from(res.data['data']);
  }

  // Profil yangilash
  Future<void> updateProfile({required String fullName}) async {
    await _dio.put('/client/profile', data: {'fullName': fullName});
  }

  // Parol o'rnatish
  Future<void> setPassword(String password) async {
    await _dio.put('/auth/password', data: {
      'oldPassword': '',
      'newPassword': password,
    });
  }

  // Saqlangan manzillar
  Future<List<Map<String, dynamic>>> getSavedAddresses() async {
    final res = await _dio.get('/client/saved-addresses');
    final list = res.data['data'] as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> saveSavedAddress({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final res = await _dio.post('/client/saved-addresses', data: {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    });
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<void> updateSavedAddress(
    String id, {
    required String name,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    await _dio.put('/client/saved-addresses/$id', data: {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> deleteSavedAddress(String id) async {
    await _dio.delete('/client/saved-addresses/$id');
  }

  // Profil rasmini (avatar) yuklash
  Future<void> updateAvatar(Uint8List bytes, String fileName) async {
    final formData = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    await _dio.post('/client/avatar', data: formData);
  }
}