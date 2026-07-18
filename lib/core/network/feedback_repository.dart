import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(ref.watch(dioProvider));
});

class FeedbackRepository {
  final Dio _dio;
  FeedbackRepository(this._dio);

  Future<void> sendFeedback({
    required String message,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    final formData = FormData.fromMap({
      'message': message,
      if (imageBytes != null)
        'image': MultipartFile.fromBytes(imageBytes, filename: imageName),
    });
    await _dio.post('/feedback', data: formData);
  }
}
