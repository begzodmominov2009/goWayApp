import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(dioProvider));
});

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String createdAt;
  final String? date;
  final String? time;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.date,
    this.time,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'SYSTEM',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
      date: json['date'] as String?,
      time: json['time'] as String?,
    );
  }
}

class NotificationRepository {
  final Dio _dio;
  NotificationRepository(this._dio);

  Future<void> saveFcmToken(String token) async {
    try {
      await _dio.post('/notifications/fcm-token', data: {'fcmToken': token});
    } catch (_) {}
  }

  Future<List<AppNotification>> getNotifications() async {
    final res = await _dio.get('/notifications');
    final list = res.data['data'] as List;
    return list.map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<int> getUnreadCount() async {
    try {
      final res = await _dio.get('/notifications/unread-count');
      return res.data['data']['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAsRead(String notificationId) async {
    await _dio.put('/notifications/$notificationId/read');
  }

  Future<void> markAllAsRead() async {
    await _dio.put('/notifications/read-all');
  }
}