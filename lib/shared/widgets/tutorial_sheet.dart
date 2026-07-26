import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';

/// Uch joyda (rejalashtirilgan buyurtmalar, yo'nalishlar ro'yxati, yangi
/// yo'nalish yaratish oqimi) ishlatiladigan umumiy tushuntiruvchi bottom
/// sheet. Chaqiruvchi ekran uni birinchi marta avtomatik, keyin esa "?"
/// tugmasi orqali istalgan vaqt qayta ochishi mumkin.
Future<void> showTutorialSheet(
  BuildContext context, {
  required String title,
  required List<String> bullets,
  required IconData icon,
  required String locale,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surface = isDark ? AppTheme.darkSurface : Colors.white;
  final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
  final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
  final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: AppTheme.primaryColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 14),
            ...bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6), width: 6, height: 6,
                        decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(b, style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    AppStrings.get('understood', locale),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
