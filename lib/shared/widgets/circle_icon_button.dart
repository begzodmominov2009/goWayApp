import 'package:flutter/material.dart';

/// Xarita ustidagi dumaloq harakat tugmalari uchun umumiy ko'rinish —
/// zoom, tilt, "o'zini topish", manzilga o'tish kabi. Avval
/// client_home_screen.dart ichida shu nomdagi private vidjet (_CircleBtn)
/// sifatida edi; map_address_picker.dart ham AYNAN bir xil ko'rinishdagi
/// "o'zini topish" tugmasini talab qilgani sabab shu yerga (umumiy
/// joyga) chiqarildi — endi ikkalasi ham shu BITTA vidjetni ishlatadi.
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color surface;
  final Color textColor;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.surface,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Icon(icon, color: textColor, size: 23),
    );
  }
}
