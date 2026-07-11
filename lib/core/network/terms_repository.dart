import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final termsRepositoryProvider = Provider<TermsRepository>((ref) {
  return TermsRepository(ref.watch(dioProvider));
});

class TermsRepository {
  final Dio _dio;
  TermsRepository(this._dio);

  Future<Map<String, dynamic>> getActiveTerms() async {
    final res = await _dio.get('/terms');
    return Map<String, dynamic>.from(res.data['data']);
  }
}