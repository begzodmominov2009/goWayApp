import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/jwt_helper.dart';
import 'api_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});

class AuthRepository {
  final Dio _dio;
  final _storage = const FlutterSecureStorage();

  AuthRepository(this._dio);

  Future<void> saveToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
    } else {
      await _storage.write(key: 'token', value: token);
    }
  }

  Future<String?> getToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('token');
    } else {
      return await _storage.read(key: 'token');
    }
  }

  // Refresh token — accessToken muddati tugaganda, foydalanuvchini
  // qayta login qildirmasdan yangi accessToken olish uchun ishlatiladi.
  // Backend /auth/verify-otp va /auth/login javobida "refreshToken"
  // maydonini qaytaradi (JWT_REFRESH_EXPIRES_IN="30d").
  Future<void> saveRefreshToken(String refreshToken) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('refresh_token', refreshToken);
    } else {
      await _storage.write(key: 'refresh_token', value: refreshToken);
    }
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('refresh_token');
    } else {
      return await _storage.read(key: 'refresh_token');
    }
  }

  Future<void> saveRole(String role) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('role', role);
    } else {
      await _storage.write(key: 'role', value: role);
    }
  }

  Future<String?> getRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('role');
    } else {
      return await _storage.read(key: 'role');
    }
  }

  // Token ichidan joriy foydalanuvchi ID'sini olish — chat, va boshqa
  // "bu men yozdimmi" degan holatlarni aniqlash uchun kerak.
  Future<String?> getUserId() async {
    final token = await getToken();
    if (token == null) return null;
    return JwtHelper.getUserId(token);
  }

  Future<void> logout() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('refresh_token');
      await prefs.remove('role');
    } else {
      await _storage.deleteAll();
    }
  }

  Future<Map<String, dynamic>> loginWithPassword({
    required String phone,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    return res.data;
  }

  Future<void> sendOtp(String phone, String role) async {
    await _dio.post('/auth/send-otp', data: {'phone': phone, 'role': role});
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
    required String role,
  }) async {
    final res = await _dio.post('/auth/verify-otp', data: {
      'phone': phone,
      'code': code,
      'role': role,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> getDriverStatus() async {
    final res = await _dio.get('/driver/profile');
    final data = res.data['data'];
    return {
      'verificationStatus': data['verificationStatus'],
      'rejectionReason': data['rejectionReason'],
    };
  }

  Future<void> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    await _dio.post('/auth/reset-password', data: {
      'phone': phone,
      'code': code,
      'newPassword': newPassword,
    });
  }

  Future<void> verifyResetOtp(String phone, String code) async {
    await _dio.post('/auth/verify-reset-otp', data: {'phone': phone, 'code': code});
  }

  Future<void> requestPhoneChange(String newPhone) async {
    await _dio.post('/auth/change-phone/request', data: {'newPhone': newPhone});
  }

  Future<void> verifyPhoneChange(String newPhone, String code) async {
    await _dio.post('/auth/change-phone/verify', data: {'newPhone': newPhone, 'code': code});
  }

  // Refresh token orqali yangi accessToken olish. Bu — asosiy Dio
  // instansiyasidan FOYDALANMAYDI (chunki u interceptor orqali eski
  // token bilan ishlaydi va cheksiz tsiklga tushishi mumkin) — o'z
  // Dio nusxasi bilan, to'g'ridan-to'g'ri so'rov yuboradi.
  Future<String?> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final plainDio = Dio(BaseOptions(baseUrl: baseUrl));
      final res = await plainDio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      if (res.data['success'] == true) {
        final newAccessToken = res.data['data']['accessToken'] as String;
        await saveToken(newAccessToken);
        return newAccessToken;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}