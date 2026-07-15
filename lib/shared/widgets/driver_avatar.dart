import 'package:flutter/material.dart';

/// Haydovchi avatari — agar avatarUrl mavjud bo'lsa rasmni, aks holda
/// ism bosh harfini ko'rsatadi. Aktiv buyurtma paneli va tafsilotlar
/// sahifasida umumiy ishlatiladi.
class DriverAvatar extends StatelessWidget {
  final Map<String, dynamic> driver;
  final double size;
  const DriverAvatar({super.key, required this.driver, required this.size});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = driver['avatarUrl'] as String?;
    final initials = (driver['fullName'] as String? ?? 'D').isNotEmpty
        ? (driver['fullName'] as String? ?? 'D')[0].toUpperCase()
        : 'D';

    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        shape: BoxShape.circle,
      ),
      child: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? ClipOval(
              child: Image.network(
                avatarUrl,
                width: size, height: size, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(initials, style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w800)),
                ),
              ),
            )
          : Center(child: Text(initials, style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w800))),
    );
  }
}
