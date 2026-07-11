import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(dioProvider));
});

class ChatMessage {
  final String id;
  final String orderId;
  final String senderId;
  final String message;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      senderId: json['senderId'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ChatRepository {
  final Dio _dio;
  ChatRepository(this._dio);

  Future<List<ChatMessage>> getMessages(String orderId) async {
    final res = await _dio.get('/orders/$orderId/messages');
    final list = res.data['data'] as List;
    return list.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<ChatMessage> sendMessage(String orderId, String message) async {
    final res = await _dio.post('/orders/$orderId/messages', data: {'message': message});
    return ChatMessage.fromJson(Map<String, dynamic>.from(res.data['data']));
  }
}