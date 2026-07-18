import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final faqRepositoryProvider = Provider<FaqRepository>((ref) {
  return FaqRepository(ref.watch(dioProvider));
});

class FaqRepository {
  final Dio _dio;
  FaqRepository(this._dio);

  Future<List<Map<String, dynamic>>> getFaqs(String role, String locale) async {
    final res = await _dio.get('/faq', queryParameters: {'role': role, 'locale': locale});
    final list = res.data['data'] as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
