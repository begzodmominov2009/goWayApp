import 'package:flutter/material.dart';

/// Doira ichidagi fonli yopish (X) tugmasi — bottom-sheet modallarning
/// header qismida bir xil ko'rinishda ishlatish uchun umumiy widget.
/// Ranglar hardcode qilinmaydi — chaqiruvchi taraf `Theme.of(context)`
/// asosida `bg`/`iconColor` ni uzatadi, shu bois dark/light temada to'g'ri
/// ishlaydi.
class CloseCircleButton extends StatelessWidget {
  final Color bg;
  final Color iconColor;
  final VoidCallback onTap;
  const CloseCircleButton({super.key, required this.bg, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 32, height: 32,
            child: Icon(Icons.close, color: iconColor, size: 18),
          ),
        ),
      );
}
