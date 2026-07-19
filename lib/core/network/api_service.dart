import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';


const String baseUrl = 'http://192.168.1.4:3000/api/v1';

// Bir vaqtda bir nechta so'rov 401 olsa, ularning barchasi BIR MARTA
// refresh so'rasin (parallel, ortiqcha refresh so'rovlarining oldini
// olish uchun) — quyidagi ikkita o'zgaruvchi shuni boshqaradi.
bool _isRefreshing = false;
final List<void Function(String? newToken)> _refreshSubscribers = [];

void _onRefreshed(String? newToken) {
  for (final callback in _refreshSubscribers) {
    callback(newToken);
  }
  _refreshSubscribers.clear();
}

Future<String?> _getStoredToken() async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  } else {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'token');
  }
}

Future<String?> _getStoredRefreshToken() async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  } else {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'refresh_token');
  }
}

Future<void> _saveToken(String token) async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  } else {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'token', value: token);
  }
}

Future<void> _clearAuthData() async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    await prefs.remove('role');
  } else {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await _getStoredToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      final isUnauthorized = error.response?.statusCode == 401;
      // /auth/refresh yoki /auth/login so'rovlarining o'zi 401 bersa,
      // qayta refresh urinib, cheksiz tsiklga tushmaslik kerak.
      final isAuthEndpoint = error.requestOptions.path.contains('/auth/');

      if (!isUnauthorized || isAuthEndpoint) {
        handler.next(error);
        return;
      }

      final refreshToken = await _getStoredRefreshToken();
      if (refreshToken == null) {
        // Refresh token yo'q — foydalanuvchi haqiqatan qayta login
        // qilishi kerak. Auth ma'lumotlarini tozalab, xatoni davom ettir.
        await _clearAuthData();
        handler.next(error);
        return;
      }

      // Agar allaqachon boshqa so'rov refresh qilayotgan bo'lsa, shu
      // so'rovni navbatga qo'yib, refresh tugashini kutamiz — bir
      // vaqtda bir nechta /auth/refresh so'rovi yuborilmasligi uchun.
      if (_isRefreshing) {
        final completer = Completer<String?>();
        _refreshSubscribers.add((newToken) => completer.complete(newToken));
        final newToken = await completer.future;
        if (newToken == null) {
          handler.next(error);
          return;
        }
        try {
          final retryOptions = error.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await dio.fetch(retryOptions);
          handler.resolve(response);
        } catch (_) {
          handler.next(error);
        }
        return;
      }

      _isRefreshing = true;
      try {
        final plainDio = Dio(BaseOptions(baseUrl: baseUrl));
        final res = await plainDio.post('/auth/refresh', data: {
          'refreshToken': refreshToken,
        });

        if (res.data['success'] == true) {
          final newToken = res.data['data']['accessToken'] as String;
          await _saveToken(newToken);
          _isRefreshing = false;
          _onRefreshed(newToken);

          // Muvaffaqiyatsiz bo'lgan asl so'rovni yangi token bilan
          // qayta yuboramiz.
          final retryOptions = error.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await dio.fetch(retryOptions);
          handler.resolve(response);
        } else {
          _isRefreshing = false;
          _onRefreshed(null);
          await _clearAuthData();
          handler.next(error);
        }
      } catch (_) {
        _isRefreshing = false;
        _onRefreshed(null);
        await _clearAuthData();
        handler.next(error);
      }
    },
  ));

  return dio;
});