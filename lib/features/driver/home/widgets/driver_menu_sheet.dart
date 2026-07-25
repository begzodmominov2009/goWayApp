import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/network/notification_repository.dart';
import '../../../../core/router/app_router.dart';

class DriverMenuSheet extends ConsumerStatefulWidget {
  const DriverMenuSheet({super.key});

  @override
  ConsumerState<DriverMenuSheet> createState() => _DriverMenuSheetState();
}

class _DriverMenuSheetState extends ConsumerState<DriverMenuSheet> {
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
            icon: Icons.account_balance_wallet_outlined,
            label: AppStrings.get('wallet', locale),
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.driverWallet);
            },
          ),
          _MenuTile(
            icon: Icons.receipt_long_outlined,
            label: AppStrings.get('order_history_title', locale),
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.driverHistory);
            },
          ),
          _MenuTile(
            icon: Icons.alt_route,
            label: AppStrings.get('my_line', locale),
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push('/driver/line');
            },
          ),
          _MenuTile(
            icon: Icons.event_note,
            label: 'Rejalashtirilgan buyurtmalar',
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push('/driver/scheduled-orders');
            },
          ),
          _MenuTile(
            icon: Icons.notifications_outlined,
            label: AppStrings.get('notifications', locale),
            badgeCount: _unreadCount,
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.notifications);
            },
          ),
          _MenuTile(
            icon: Icons.person_outline,
            label: AppStrings.get('profile', locale),
            isDark: isDark,
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.driverProfile);
            },
          ),
        ],
      ),
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
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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