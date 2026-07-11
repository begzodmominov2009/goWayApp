import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  return ClientRepository(ref.watch(dioProvider));
});

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
  }) async {
    final res = await _dio.post('/orders', data: {
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
    });
    return Map<String, dynamic>.from(res.data['data']);
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
}