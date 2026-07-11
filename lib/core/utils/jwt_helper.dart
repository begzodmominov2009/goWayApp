import 'dart:convert';

/// JWT token'ning payload qismini (imzoni tekshirmasdan, faqat o'qish
/// uchun) dekod qiladi. Backend token'ni allaqachon tasdiqlaydi —
/// bu yerda faqat ichidagi userId'ni olish uchun ishlatiladi.
class JwtHelper {
  static Map<String, dynamic>? decode(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String? getUserId(String token) {
    final data = decode(token);
    return data?['userId'] as String?;
  }
}