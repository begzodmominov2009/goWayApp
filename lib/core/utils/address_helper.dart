/// Uzun manzil satrini ("Toshkent, Yunusobod tumani, X ko'chasi, 12")
/// faqat ko'cha + uy raqamiga qisqartiradi. Agar uy raqami bo'lmasa,
/// faqat ko'cha nomi ko'rsatiladi.
class AddressHelper {
  static String shorten(String fullAddress) {
    final parts = fullAddress.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return fullAddress;
    // Odatda oxirgi 1-2 qism — ko'cha va uy raqami
    return parts.sublist(parts.length - 2).join(', ');
  }
}