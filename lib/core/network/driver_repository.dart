import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return DriverRepository(dio);
});

class DriverRepository {
  final Dio _dio;
  DriverRepository(this._dio);

  Future<List<Map<String, dynamic>>> getTrucks() async {
    final res = await _dio.get('/trucks');
    final list = res.data['data'] as List;
    return list
        .map((e) => Map<String, dynamic>.from(e))
        .where((t) => t['isActive'] == true)
        .toList();
  }

  Future<Map<String, dynamic>> getProfile() async {
    final res = await _dio.get('/driver/profile');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<void> updateProfile({
    required String fullName,
    required String truckType,
    required String plateNumber,
    required double capacity,
  }) async {
    await _dio.put('/driver/profile', data: {
      'fullName': fullName,
      'truckType': truckType.toUpperCase().replaceAll(' ', '_'),
      'plateNumber': plateNumber,
      'capacity': capacity,
    });
  }

  Future<void> uploadDocuments({
    required Uint8List passportBytes,
    required String passportName,
    required Uint8List licenceFrontBytes,
    required String licenceFrontName,
    required Uint8List licenceBackBytes,
    required String licenceBackName,
    required Uint8List techPassportBytes,
    required String techPassportName,
  }) async {
    final formData = FormData.fromMap({
      'passportUrl': MultipartFile.fromBytes(passportBytes, filename: passportName),
      'licenceFrontUrl': MultipartFile.fromBytes(licenceFrontBytes, filename: licenceFrontName),
      'licenceBackUrl': MultipartFile.fromBytes(licenceBackBytes, filename: licenceBackName),
      'techPassportUrl': MultipartFile.fromBytes(techPassportBytes, filename: techPassportName),
    });
    await _dio.post('/driver/documents', data: formData);
  }

  Future<void> setOnline(bool isOnline) async {
    await _dio.post('/driver/online', data: {'isOnline': isOnline});
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _dio.post('/driver/location', data: {'latitude': lat, 'longitude': lng});
  }

  Future<List<String>> getZones() async {
    final res = await _dio.get('/driver/zones');
    return List<String>.from(res.data['data']);
  }

  Future<void> updateZones(List<String> cities) async {
    await _dio.put('/driver/zones', data: {'cities': cities});
  }

  Future<Map<String, dynamic>> getHistory() async {
    final res = await _dio.get('/driver/history');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<Map<String, dynamic>> getTopupCard() async {
    final res = await _dio.get('/driver/topup/card');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<void> requestProfileUpdate({
    String? plateNumber,
    String? truckType,
    Uint8List? passportBytes,
    String? passportName,
    Uint8List? licFrontBytes,
    String? licFrontName,
    Uint8List? licBackBytes,
    String? licBackName,
    Uint8List? techBytes,
    String? techName,
  }) async {
    final formData = FormData.fromMap({
      if (plateNumber != null && plateNumber.isNotEmpty) 'plateNumber': plateNumber,
      if (truckType != null && truckType.isNotEmpty) 'truckType': truckType,
      if (passportBytes != null && passportBytes.isNotEmpty)
        'passport': MultipartFile.fromBytes(passportBytes, filename: passportName ?? 'passport.jpg'),
      if (licFrontBytes != null && licFrontBytes.isNotEmpty)
        'licFront': MultipartFile.fromBytes(licFrontBytes, filename: licFrontName ?? 'lic_front.jpg'),
      if (licBackBytes != null && licBackBytes.isNotEmpty)
        'licBack': MultipartFile.fromBytes(licBackBytes, filename: licBackName ?? 'lic_back.jpg'),
      if (techBytes != null && techBytes.isNotEmpty)
        'tech': MultipartFile.fromBytes(techBytes, filename: techName ?? 'tech.jpg'),
    });
    await _dio.post('/driver/profile-update-request', data: formData);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _dio.put('/auth/password', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> setPassword(String password) async {
    await _dio.put('/auth/password', data: {
      'oldPassword': '',
      'newPassword': password,
    });
  }

  Future<void> requestTopup({
    required double amount,
    required Uint8List receiptBytes,
    required String receiptName,
  }) async {
    final formData = FormData.fromMap({
      'amount': amount.toString(),
      'receipt': MultipartFile.fromBytes(receiptBytes, filename: receiptName),
    });
    await _dio.post('/driver/topup', data: formData);
  }

  Future<List<Map<String, dynamic>>> getTopupHistory() async {
    final res = await _dio.get('/driver/topup/history');
    final list = res.data['data'] as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> requestPlateChange({
    required String newPlate,
    required Uint8List techPassportBytes,
    required String techPassportName,
  }) async {
    final formData = FormData.fromMap({
      'techPassportUrl': MultipartFile.fromBytes(techPassportBytes, filename: techPassportName),
      'plateNumber': newPlate,
    });
    await _dio.post('/driver/documents', data: formData);
  }

  Future<Map<String, dynamic>> getDriverStatus() async {
    final res = await _dio.get('/driver/profile');
    final data = res.data['data'];
    return {
      'verificationStatus': data['verificationStatus'],
      'rejectionReason': data['rejectionReason'],
    };
  }

  // Aktiv offerlar
  Future<List<Map<String, dynamic>>> getOffers() async {
    final res = await _dio.get('/driver/offers');
    final list = res.data['data'] as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // Taklifni qabul qilish
  Future<void> acceptOffer(String offerId) async {
    await _dio.post('/offers/$offerId/accept');
  }

  // Taklifni rad etish
  Future<void> rejectOffer(String offerId) async {
    await _dio.post('/offers/$offerId/reject');
  }

  // Bitta buyurtma ma'lumotlarini olish (umumiy /orders/:orderId endpointi orqali)
  Future<Map<String, dynamic>> getOrder(String orderId) async {
    final res = await _dio.get('/orders/$orderId');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  // Buyurtma statusini yangilash (masalan LOADING -> IN_TRANSIT -> DELIVERED)
  Future<void> updateOrderStatus(String orderId, String status) async {
    await _dio.put('/orders/$orderId/status', data: {'status': status});
  }
}