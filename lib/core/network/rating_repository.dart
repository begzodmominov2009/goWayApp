import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  return RatingRepository(ref.watch(dioProvider));
});

class RatingRepository {
  final Dio _dio;
  RatingRepository(this._dio);

  /// Client tomonidan driverni baholash — buyurtma yakunlangач.
  Future<void> rateDriver({
    required String orderId,
    required int score,
    String? note,
  }) async {
    await _dio.post('/orders/$orderId/rating', data: {
      'score': score,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  /// Driver tomonidan clientni baholash — buyurtma yakunlangач.
  Future<void> rateClient({
    required String orderId,
    required int score,
    String? note,
  }) async {
    await _dio.post('/orders/$orderId/rating', data: {
      'score': score,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }
}