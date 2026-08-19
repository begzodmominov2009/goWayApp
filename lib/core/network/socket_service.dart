import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = 'http://167.233.217.124:3000';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

class SocketService {
  IO.Socket? _socket;
  final _storage = const FlutterSecureStorage();

  IO.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected ?? false;

  // AuthRepository saqlagan kalit bilan bir xil bo'lishi kerak — 'token'
  Future<String?> _getToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('token');
    } else {
      return await _storage.read(key: 'token');
    }
  }

  Future<void> connect() async {
    if (isConnected) return;

    final token = await _getToken();
    if (token == null) return;

    _socket = IO.io(
      _baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      print('✅ Socket ulandi');
    });

    _socket!.onDisconnect((_) {
      print('❌ Socket uzildi');
    });

    _socket!.onError((err) {
      print('Socket xato: $err');
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  // Order room ga qo'shilish
  void joinOrder(String orderId) {
    _socket?.emit('order:join', orderId);
  }

  // Driver GPS yuborish
  void sendLocation(double lat, double lng) {
    _socket?.emit('driver:location', {'latitude': lat, 'longitude': lng});
  }

  // Driver online
  void setDriverOnline() {
    _socket?.emit('driver:online');
  }

  // Driver location update tingla
  void onDriverLocation(void Function(double lat, double lng) callback) {
    _socket?.on('driver:location:update', (data) {
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      callback(lat, lng);
    });
  }

  // Order status update tingla
  void onOrderStatus(void Function(String status) callback) {
    _socket?.on('order:status:update', (data) {
      callback(data['status'] as String);
    });
  }

  // Offer keldi tingla
  void onNewOffer(void Function(Map<String, dynamic> offer) callback) {
    _socket?.on('offer:new', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Yangi bildirishnoma keldi tingla
  void onNotification(void Function(Map<String, dynamic> data) callback) {
    _socket?.on('notification:new', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // Buyurtma bekor qilinganda tingla (client tomonidan yoki tizim
  // tomonidan — masalan haydovchi topilmagani uchun). Backend faqat
  // { orderId } yuboradi. Ro'yxatdan chiqarilgan handler referensini
  // qaytaradi — bir nechta ekran (masalan driver_home_screen.dart va
  // driver_scheduled_orders_screen.dart) mustaqil obuna bo'lishi mumkin,
  // shuning uchun off() chaqirilganda FAQAT shu handler o'chirilishi
  // kerak (boshqa ekranning tinglovchisiga tegmasligi uchun).
  dynamic Function(dynamic) onOrderCancelled(void Function(String orderId) callback) {
    void handler(dynamic data) {
      final orderId = data is Map ? data['orderId'] as String? : null;
      if (orderId != null) callback(orderId);
    }
    _socket?.on('order:cancelled', handler);
    return handler;
  }

  // `handler` berilsa — faqat o'sha bitta tinglovchi olib tashlanadi
  // (masalan onOrderCancelled() qaytargan referens). Berilmasa — shu
  // event uchun BARCHA tinglovchilar olib tashlanadi (eski xatti-harakat).
  void off(String event, [dynamic Function(dynamic)? handler]) {
    _socket?.off(event, handler);
  }
}