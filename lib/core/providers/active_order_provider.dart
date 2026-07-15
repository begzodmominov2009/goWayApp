import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Client Home ekranidagi joriy faol buyurtma haqidagi qisqacha ma'lumot —
/// Home ekran buni yangilab boradi, Menu (toggle) bottom sheet esa shu
/// yerdan o'qib, "Faol buyurtma" bandini ko'rsatish va tafsilotlar
/// sahifasiga o'tish uchun ishlatadi.
class ActiveOrderInfo {
  final Map<String, dynamic> order;
  final double? distKm;
  final int? timeMin;

  const ActiveOrderInfo({required this.order, this.distKm, this.timeMin});
}

final activeOrderProvider = StateProvider<ActiveOrderInfo?>((ref) => null);
