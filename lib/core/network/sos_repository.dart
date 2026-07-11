import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final sosRepositoryProvider = Provider<SosRepository>((ref) {
  return SosRepository(ref.watch(dioProvider));
});

class SosRepository {
  final Dio _dio;
  SosRepository(this._dio);

  /// Driver SOS signalini yuboradi — joriy joylashuv bilan birga.
  /// Backend bu signalni admin panelga va (agar mavjud bo'lsa) tegishli
  /// xizmatlarga xabar qiladi.
  Future<void> sendSos({required double lat, required double lng}) async {
    await _dio.post('/sos', data: {
      'latitude': lat,
      'longitude': lng,
    });
  }
}