import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/network/notification_repository.dart';
import '../../../../core/router/app_router.dart';

class ClientMenuSheet extends ConsumerStatefulWidget {
  const ClientMenuSheet({super.key});

  @override
  ConsumerState<ClientMenuSheet> createState() => _ClientMenuSheetState();
}

class _ClientMenuSheetState extends ConsumerState<ClientMenuSheet> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await ref.read(notificationRepositoryProvider).getUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final themeMode = ref.watch(themeModeProvider);
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12, top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),

          _MenuTile(
            icon: Icons.receipt_long_outlined,
            label: 'Buyurtmalarim',
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.clientOrders);
            },
          ),
          _MenuTile(
            icon: Icons.notifications_outlined,
            label: 'Bildirishnomalar',
            badgeCount: _unreadCount,
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.notifications);
            },
          ),
          _MenuTile(
            icon: Icons.person_outline,
            label: 'Profil',
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.clientProfile);
            },
          ),
          Divider(height: 1, color: border, indent: 20, endIndent: 20),
          _MenuTile(
            icon: Icons.language_outlined,
            label: 'Til',
            value: locale == 'uz' ? 'O\'zbek' : locale == 'ru' ? 'Русский' : 'English',
            isDark: isDark,
            onTap: () => _showLanguagePicker(context, ref),
          ),
          _MenuTile(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label: 'Tema',
            value: themeMode == ThemeMode.dark
                ? AppStrings.get('theme_dark', locale)
                : themeMode == ThemeMode.light
                    ? AppStrings.get('theme_light', locale)
                    : AppStrings.get('theme_auto', locale),
            isDark: isDark,
            onTap: () => _showThemePicker(context, ref),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final current = ref.read(localeProvider).languageCode;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tilni tanlang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...[('uz', 'O\'zbek', '🇺🇿'), ('ru', 'Русский', '🇷🇺'), ('en', 'English', '🇬🇧')].map((item) =>
                ListTile(
                  leading: Text(item.$3, style: const TextStyle(fontSize: 22)),
                  title: Text(item.$2, style: TextStyle(
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                    fontWeight: current == item.$1 ? FontWeight.w700 : FontWeight.w400,
                  )),
                  trailing: current == item.$1
                      ? const Icon(Icons.check, color: AppTheme.primaryColor, size: 18) : null,
                  onTap: () {
                    ref.read(localeProvider.notifier).setLocale(item.$1);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final current = ref.read(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Temani tanlang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...[
                (ThemeMode.system, AppStrings.get('theme_auto', locale), Icons.brightness_auto_outlined),
                (ThemeMode.light, AppStrings.get('theme_light', locale), Icons.light_mode_outlined),
                (ThemeMode.dark, AppStrings.get('theme_dark', locale), Icons.dark_mode_outlined),
              ].map((item) => ListTile(
                leading: Icon(item.$3, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
                title: Text(item.$2, style: TextStyle(
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                  fontWeight: current == item.$1 ? FontWeight.w700 : FontWeight.w400,
                )),
                trailing: current == item.$1
                    ? const Icon(Icons.check, color: AppTheme.primaryColor, size: 18) : null,
                onTap: () {
                  ref.read(themeModeProvider.notifier).setTheme(item.$1);
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final int? badgeCount;
  final bool isDark;
  final Color? color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon, required this.label, this.value, this.badgeCount,
    required this.isDark, this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = color ?? (isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary);
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final hasBadge = badgeCount != null && badgeCount! > 0;

    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 22, color: color ?? textSecondary),
          if (hasBadge)
            Positioned(
              right: -4, top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  badgeCount! > 9 ? '9+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      title: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary)),
      trailing: value != null
          ? Text(value!, style: TextStyle(fontSize: 13, color: textSecondary))
          : Icon(Icons.chevron_right, size: 18, color: textSecondary),
    );
  }
}