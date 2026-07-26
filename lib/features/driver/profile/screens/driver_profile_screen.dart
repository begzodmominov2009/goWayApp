import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/providers/driver_cache_providers.dart';
import '../../../../core/router/app_router.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  ConsumerState<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  // Profil + mashina turlari endi keshdan (driverProfileCacheProvider) o'qiladi.
  // Quyidagi getter'lar orqali eski kod ('_profile', '_trucks') o'zgarishsiz
  // ishlayveradi.
  Map<String, dynamic>? get _profile =>
      ref.read(driverProfileCacheProvider).valueOrNull?['profile'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get _trucks =>
      (((ref.read(driverProfileCacheProvider).valueOrNull?['trucks']) as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Uint8List? _avatarBytes;
  bool _avatarUploading = false;

  @override
  void initState() {
    super.initState();
    // Sahifa ochilganda: kesh eskirgan (yoki avval xato bo'lgan) bo'lsa
    // yangilaydi, aks holda keshdan ko'rsatiladi (yangi so'rov ketmaydi).
    ref.read(driverProfileCacheProvider.notifier).refreshIfStale();
  }

  // Profil rasmini (avatar) tanlash — ixtiyoriy, tanlanmasa hech narsa
  // yuborilmaydi va standart (harf) avatar ko'rsatilaveradi. Xato bo'lsa,
  // tanlangan (hali saqlanmagan) rasm bekor qilinib, foydalanuvchiga
  // SnackBar orqali xabar beriladi.
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (!mounted) return;
    setState(() { _avatarBytes = bytes; _avatarUploading = true; });
    final locale = ref.read(localeProvider).languageCode;
    try {
      await ref.read(driverRepositoryProvider).uploadAvatar(bytes, img.name);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _avatarBytes = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('avatar_upload_failed', locale)), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Widget _avatarContent(double size, {required Color initialsColor}) {
    if (_avatarBytes != null) {
      return ClipOval(child: Image.memory(_avatarBytes!, width: size, height: size, fit: BoxFit.cover));
    }
    final url = _profile?['avatarUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Text(_initials(), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: initialsColor)),
          ),
        ),
      );
    }
    return Center(
      child: Text(_initials(), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: initialsColor)),
    );
  }

  // Majburiy yangilash — avatar/profil o'zgargandan keyin va boshqa joylarda
  // ishlatiladi. Keshni yangilaydi; watch qilingan build avtomatik yangilanadi.
  Future<void> _load() async {
    await ref.read(driverProfileCacheProvider.notifier).forceRefresh();
  }

  String _initials() {
    final name = _profile?['fullName'] as String? ?? '';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'D';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final themeMode = ref.watch(themeModeProvider);
    // Profilni kuzatamiz — ma'lumot kelganda/yangilanganda ekran qayta chiziladi.
    final profileAsync = ref.watch(driverProfileCacheProvider);
    final loading = profileAsync.isLoading && !profileAsync.hasValue;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    // Dark mode — to'q navy gradient. Light mode — och, yumshoq ko'k.
    final headerGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF2563eb)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.get('profile', locale),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: AppTheme.primaryColor, size: 22),
            onPressed: _showEditNameSheet,
          ),
        ],
      ),
      body: loading
          ? const Center(child: AppLoadingIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Gradient header
                Container(
                  decoration: BoxDecoration(
                    gradient: headerGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _avatarUploading ? null : _pickAvatar,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                              ),
                              child: _avatarContent(56, initialsColor: Colors.white),
                            ),
                            Positioned(
                              right: -2, bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: bg, width: 2),
                                ),
                                child: _avatarUploading
                                    ? const SizedBox(width: 10, height: 10,
                                        child: AppLoadingIndicator(strokeWidth: 1.5, color: Colors.white))
                                    : const Icon(Icons.edit, size: 10, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_profile?['fullName'] ?? 'Driver',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                final shortId = _profile?['user']?['shortId'] ?? '';
                                Clipboard.setData(ClipboardData(text: shortId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ID nusxalandi!'),
                                    backgroundColor: AppTheme.successColor,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('#${_profile?['user']?['shortId'] ?? ''}',
                                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85))),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy, size: 12, color: Colors.white.withOpacity(0.7)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              _StatChip(label: '⭐ ${(_profile?['averageRating'] ?? 5.0).toStringAsFixed(1)}'),
                              const SizedBox(width: 6),
                              _StatChip(label: '${_profile?['totalAccepted'] ?? 0} reys'),
                              const SizedBox(width: 6),
                              _StatChip(label: '${(_profile?['acceptanceRate'] ?? 100).toStringAsFixed(0)}%'),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Otish yo'llari — Hamyon, Buyurtmalar tarixi, Bildirishnomalar
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(children: [
                    _MenuItem(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      label: AppStrings.get('wallet', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.driverWallet),
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppTheme.primaryColor,
                      label: AppStrings.get('order_history_title', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.driverHistory),
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.notifications_outlined,
                      iconColor: AppTheme.successColor,
                      label: AppStrings.get('notifications', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.notifications),
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.event_note,
                      iconColor: AppTheme.warningColor,
                      label: AppStrings.get('scheduled_orders_title', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.driverScheduledOrders),
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.alt_route,
                      iconColor: const Color(0xFF0EA5E9),
                      label: AppStrings.get('my_line', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.driverLine),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Mashina card
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(AppStrings.get('vehicle_info', locale),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: textSecondary, letterSpacing: 0.6)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _showVehicleEditSheet,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8, right: 4),
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 13, color: AppTheme.primaryColor),
                          const SizedBox(width: 3),
                          Text(AppStrings.get('edit', locale),
                              style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(children: [
                    _MenuItem(icon: Icons.local_shipping_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('truck_type', locale),
                        value: _profile?['truckType'] ?? '—', isDark: isDark),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.pin_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('plate_number', locale),
                        value: _profile?['plateNumber'] ?? '—', isDark: isDark),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.scale_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('capacity', locale),
                        value: '${_profile?['capacity'] ?? '—'} t', isDark: isDark),
                  ]),
                ),
                const SizedBox(height: 12),

                // Sozlamalar
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(AppStrings.get('app_settings', locale),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: textSecondary, letterSpacing: 0.6)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(children: [
                    _MenuItem(icon: Icons.language_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('language', locale),
                        value: locale == 'uz' ? 'O\'zbek' : locale == 'ru' ? 'Русский' : 'English',
                        isDark: isDark, onTap: _showLanguageSheet),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                        icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('theme', locale),
                        value: themeMode == ThemeMode.dark
                            ? AppStrings.get('theme_dark', locale)
                            : themeMode == ThemeMode.light
                                ? AppStrings.get('theme_light', locale)
                                : AppStrings.get('theme_auto', locale),
                        isDark: isDark, onTap: _showThemeSheet),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.lock_outline,
                        iconColor: textSecondary,
                        label: AppStrings.get('change_password', locale),
                        isDark: isDark, onTap: _showChangePasswordSheet),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.phone_iphone_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('phone_number_label', locale),
                        value: _profile?['user']?['phone'] ?? '',
                        isDark: isDark, onTap: _showChangePhoneSheet),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.description_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('terms', locale),
                        isDark: isDark, onTap: () => context.push(AppRoutes.terms)),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.feedback_outlined,
                        iconColor: textSecondary,
                        label: AppStrings.get('feedback', locale),
                        isDark: isDark, onTap: () => context.push(AppRoutes.feedback)),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(icon: Icons.help_outline,
                        iconColor: textSecondary,
                        label: AppStrings.get('faq', locale),
                        isDark: isDark, onTap: () => context.push(AppRoutes.faq)),
                  ]),
                ),
                const SizedBox(height: 12),

                // Chiqish
                GestureDetector(
                  onTap: _showLogoutDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFdc2626).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFdc2626).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFdc2626).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.logout_outlined, color: Color(0xFFdc2626), size: 16),
                        ),
                        const SizedBox(width: 12),
                        Text(AppStrings.get('logout', locale),
                            style: const TextStyle(color: Color(0xFFdc2626),
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        const Spacer(),
                        const Icon(Icons.chevron_right, color: Color(0xFFdc2626), size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  void _showVehicleEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _VehicleEditSheet(
        profile: _profile,
        trucks: _trucks,
        onDone: _load,
      ),
    );
  }

  void _showEditNameSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    final ctrl = TextEditingController(text: _profile?['fullName'] ?? '');
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) {
        bool saving = false;
        final originalName = _profile?['fullName'] ?? '';
        bool hasChanged = false;
        return StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: AppTheme.borderColor,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(AppStrings.get('edit_profile', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
                  decoration: InputDecoration(labelText: AppStrings.get('full_name', locale)),
                  onChanged: (val) => setSt(() => hasChanged = val.trim() != originalName.trim()),
                ),
                const SizedBox(height: 16),
                hasChanged
                    ? _GradientButton(
                        loading: saving,
                        label: AppStrings.get('save', locale),
                        onTap: () async {
                          setSt(() => saving = true);
                          try {
                            await ref.read(driverRepositoryProvider).updateProfile(
                              fullName: ctrl.text.trim(),
                              truckType: _profile?['truckType'] ?? 'BONGO',
                              plateNumber: _profile?['plateNumber'] ?? '',
                              capacity: (_profile?['capacity'] as num?)?.toDouble() ?? 1.5,
                            );
                            await _load();
                            if (mounted) Navigator.pop(ctx);
                          } catch (_) {
                            setSt(() => saving = false);
                          }
                        },
                      )
                    : OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: BorderSide(color: border),
                          foregroundColor: textSecondary,
                        ),
                        child: Text(AppStrings.get('close', locale),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChangePasswordSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _ChangePasswordSheet(
        isDark: isDark, locale: locale,
        driverPhone: _profile?['user']?['phone'] ?? '',
      ),
    );
  }

  void _showChangePhoneSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _ChangePhoneSheet(
        isDark: isDark, locale: locale, onDone: _load,
        currentPhone: _profile?['user']?['phone'] ?? '',
      ),
    );
  }

  void _showLanguageSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) {
        final current = ref.read(localeProvider).languageCode;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tilni tanlang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...([('uz', 'O\'zbek', '🇺🇿'), ('ru', 'Русский', '🇷🇺'), ('en', 'English', '🇬🇧')].map((item) =>
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
                )
              )),
            ],
          ),
        );
      },
    );
  }

  void _showThemeSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) {
        final current = ref.read(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Temani tanlang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...([
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
              ))),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showLogoutDialog() async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) {
        final surface = isDark ? AppTheme.darkSurface : Colors.white;
        final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
        final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
        final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: border,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.logout_outlined,
                    color: AppTheme.errorColor, size: 26),
              ),
              const SizedBox(height: 16),
              Text(AppStrings.get('logout_confirm_title', locale),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: textPrimary)),
              const SizedBox(height: 8),
              Text(AppStrings.get('logout_confirm_message', locale),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: border),
                        foregroundColor: textSecondary,
                      ),
                      child: Text(AppStrings.get('cancel', locale),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _logout();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(AppStrings.get('confirm_logout', locale),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    // Keyingi (boshqa) foydalanuvchi kirganda eski keshdan ma'lumot
    // ko'rinmasligi uchun barcha Driver kesh'larini tozalaymiz.
    invalidateDriverCaches(ref);
    if (mounted) context.go(AppRoutes.onboarding);
  }
}

// ===== MASHINA TAHRIRLASH =====
class _VehicleEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> trucks;
  final VoidCallback onDone;
  const _VehicleEditSheet({
    required this.profile, required this.trucks, required this.onDone,
  });
  @override
  ConsumerState<_VehicleEditSheet> createState() => _VehicleEditSheetState();
}

class _VehicleEditSheetState extends ConsumerState<_VehicleEditSheet> {
  late String? _truckType;
  late TextEditingController _plateCtrl;
  late String? _origTruckType;
  late String _origPlate;
  Map<String, Uint8List> _newBytes = {};
  Map<String, String> _newNames = {};
  bool _hasChanges = false;
  bool _saving = false;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _truckType = widget.profile?['truckType'];
    _origTruckType = widget.profile?['truckType'];
    _origPlate = widget.profile?['plateNumber'] ?? '';
    _plateCtrl = TextEditingController(text: _origPlate);
    _plateCtrl.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    super.dispose();
  }

  void _checkChanges() {
    final changed = _truckType != _origTruckType ||
        _plateCtrl.text.trim() != _origPlate ||
        _newBytes.isNotEmpty;
    if (changed != _hasChanges) setState(() => _hasChanges = changed);
  }

  Future<void> _pickImage(String field) async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final ext = img.name.split('.').last;
    setState(() {
      _newBytes[field] = bytes;
      _newNames[field] = '${field}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      _hasChanges = true;
    });
  }

  void _viewImage(String? url, Uint8List? bytes) {
    if (url == null && bytes == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain)
            else if (url != null)
              Image.network(url, fit: BoxFit.contain),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(driverRepositoryProvider);
      if (_truckType != _origTruckType && _newBytes.isEmpty &&
          _plateCtrl.text.trim() == _origPlate) {
        final truck = widget.trucks.firstWhere(
          (t) => t['type'] == _truckType, orElse: () => widget.profile ?? {});
        await repo.updateProfile(
          fullName: widget.profile?['fullName'] ?? '',
          truckType: _truckType ?? _origTruckType ?? '',
          plateNumber: _origPlate,
          capacity: (truck['capacity'] as num?)?.toDouble() ?? 1.5,
        );
        widget.onDone();
        setState(() { _saving = false; _success = true; });
        return;
      }
      if (_plateCtrl.text.trim() != _origPlate && _newBytes['tech'] == null) {
        setState(() => _saving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Davlat raqami o\'zgartirilganda texnik pasport rasmi majburiy!'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }
      await repo.requestProfileUpdate(
        plateNumber: _plateCtrl.text.trim() != _origPlate
            ? _plateCtrl.text.trim().toUpperCase().replaceAll(' ', '') : null,
        truckType: _truckType != _origTruckType ? _truckType : null,
        passportBytes: _newBytes['passport'],
        passportName: _newNames['passport'],
        licFrontBytes: _newBytes['licFront'],
        licFrontName: _newNames['licFront'],
        licBackBytes: _newBytes['licBack'],
        licBackName: _newNames['licBack'],
        techBytes: _newBytes['tech'],
        techName: _newNames['tech'],
      );
      widget.onDone();
      setState(() { _saving = false; _success = true; });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e'), backgroundColor: AppTheme.errorColor));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    return GestureDetector(
      onTap: _hasChanges ? null : () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: _success ? _buildSuccess(textPrimary, locale, border) : Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(AppStrings.get('vehicle_edit', locale),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
          ),
          Divider(height: 1, color: border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(AppStrings.get('truck_type', locale),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _truckType,
                      isExpanded: true,
                      dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                      icon: Icon(Icons.keyboard_arrow_down, color: textSecondary),
                      items: widget.trucks
                          .fold<Map<String, Map<String, dynamic>>>({}, (map, t) {
                            final key = t['type'] as String;
                            if (!map.containsKey(key)) map[key] = t;
                            return map;
                          })
                          .values
                          .map((t) {
                        return DropdownMenuItem<String>(
                          value: t['type'] as String,
                          child: Row(children: [
                            Icon(Icons.local_shipping_outlined, size: 18,
                                color: _truckType == t['type'] ? AppTheme.primaryColor : textSecondary),
                            const SizedBox(width: 10),
                            Text(
                              '${t['name'] ?? t['type']} (${t['capacity']}t)',
                              style: TextStyle(
                                fontSize: 14,
                                color: _truckType == t['type'] ? AppTheme.primaryColor : textPrimary,
                                fontWeight: _truckType == t['type'] ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() { _truckType = val; _checkChanges(); });
                      },
                    ),
                  ),
                ),
                if (_truckType != null) ...[
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final selectedTruck = widget.trucks.where((t) => t['type'] == _truckType).firstOrNull;
                    if (selectedTruck == null) return const SizedBox();
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.scale_outlined, size: 14, color: AppTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          '${AppStrings.get('capacity', locale)}: ${selectedTruck['capacity']} t',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                Text(AppStrings.get('plate_number', locale),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                const SizedBox(height: 4),
                Text('Admin tasdiqlagandan keyin o\'zgaradi',
                    style: TextStyle(fontSize: 11, color: AppTheme.warningColor)),
                const SizedBox(height: 8),
                TextField(
                  controller: _plateCtrl,
                  style: TextStyle(color: textPrimary, letterSpacing: 2, fontWeight: FontWeight.w600),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(hintText: '40 A 452 BS'),
                ),
                const SizedBox(height: 20),
                Text(AppStrings.get('documents', locale),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                const SizedBox(height: 4),
                Text('Rasmni ko\'rish uchun pastki o\'ng belgini bosing',
                    style: TextStyle(fontSize: 11, color: textSecondary)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.1,
                  children: [
                    _DocCard(
                      label: AppStrings.get('passport', locale),
                      icon: Icons.badge_outlined,
                      url: widget.profile?['passportUrl'],
                      newBytes: _newBytes['passport'],
                      isDark: isDark,
                      locale: locale,
                      onPick: () => _pickImage('passport'),
                      onView: () => _viewImage(widget.profile?['passportUrl'], _newBytes['passport']),
                    ),
                    _DocCard(
                      label: '${AppStrings.get('license', locale)} (old)',
                      icon: Icons.drive_eta_outlined,
                      url: widget.profile?['licenceFrontUrl'],
                      newBytes: _newBytes['licFront'],
                      isDark: isDark,
                      locale: locale,
                      onPick: () => _pickImage('licFront'),
                      onView: () => _viewImage(widget.profile?['licenceFrontUrl'], _newBytes['licFront']),
                    ),
                    _DocCard(
                      label: '${AppStrings.get('license', locale)} (orqa)',
                      icon: Icons.drive_eta_outlined,
                      url: widget.profile?['licenceBackUrl'],
                      newBytes: _newBytes['licBack'],
                      isDark: isDark,
                      locale: locale,
                      onPick: () => _pickImage('licBack'),
                      onView: () => _viewImage(widget.profile?['licenceBackUrl'], _newBytes['licBack']),
                    ),
                    _DocCard(
                      label: AppStrings.get('tech_passport', locale),
                      icon: Icons.description_outlined,
                      url: widget.profile?['techPassportUrl'],
                      newBytes: _newBytes['tech'],
                      isDark: isDark,
                      locale: locale,
                      onPick: () => _pickImage('tech'),
                      onView: () => _viewImage(widget.profile?['techPassportUrl'], _newBytes['tech']),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: border)),
            ),
            child: _hasChanges
                ? _GradientButton(
                    label: AppStrings.get('confirm', locale),
                    loading: _saving,
                    onTap: _submit,
                  )
                : OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: border),
                      foregroundColor: textSecondary,
                    ),
                    child: Text(AppStrings.get('close', locale),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(Color textPrimary, String locale, Color border) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
          const Spacer(),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.security_outlined, color: AppTheme.warningColor, size: 32),
          ),
          const SizedBox(height: 20),
          Text(AppStrings.get('admin_approval_sent', locale),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
            ),
            child: Text(AppStrings.get('admin_approval_notice', locale),
                style: const TextStyle(fontSize: 13, color: AppTheme.warningColor, height: 1.5),
                textAlign: TextAlign.center),
          ),
          const Spacer(),
          _GradientButton(
            label: AppStrings.get('close', locale),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// ===== PAROL O'ZGARTIRISH =====
class _ChangePasswordSheet extends ConsumerStatefulWidget {
  final bool isDark;
  final String locale;
  final String driverPhone;
  const _ChangePasswordSheet({required this.isDark, required this.locale, required this.driverPhone});
  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  int _step = 0;
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.driverPhone.replaceFirst('+998', '').replaceAll(RegExp(r'\D'), '');
  }

  @override
  void dispose() {
    _currentCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose();
    _phoneCtrl.dispose(); _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newCtrl.text.length < 6) {
      setState(() => _error = AppStrings.get('password_too_short', widget.locale));
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = AppStrings.get('password_mismatch', widget.locale));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(driverRepositoryProvider).changePassword(
        oldPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      setState(() { _success = true; _loading = false; });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '').replaceAll('DioException [bad response]: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _sendForgotOtp() async {
    if (_phoneCtrl.text.length < 9) {
      setState(() => _error = AppStrings.get('phone_incomplete_error', widget.locale));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).sendOtp('+998${_phoneCtrl.text.trim()}', 'DRIVER');
      setState(() { _step = 2; _loading = false; });
    } catch (e) {
      setState(() { _error = AppStrings.get('generic_error', widget.locale); _loading = false; });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.length < 6) return;
    setState(() { _step = 3; });
  }

  Future<void> _setNewPassword() async {
    if (_newCtrl.text.length < 6) {
      setState(() => _error = AppStrings.get('password_too_short', widget.locale));
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = AppStrings.get('password_mismatch', widget.locale));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).resetPassword(
        phone: '+998${_phoneCtrl.text.trim()}',
        code: _otpCtrl.text,
        newPassword: _newCtrl.text,
      );
      setState(() { _success = true; _loading = false; });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '').replaceAll('DioException [bad response]: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final locale = widget.locale;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _success
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Icon(Icons.check_circle, color: AppTheme.successColor, size: 48),
              const SizedBox(height: 16),
              Text(AppStrings.get('password_changed', locale),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              _GradientButton(label: AppStrings.get('close', locale),
                  onTap: () => Navigator.pop(context)),
            ])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              if (_step == 0) ...[
                Text(AppStrings.get('change_password', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 16),
                _PasswordField(controller: _currentCtrl,
                    label: AppStrings.get('current_password', locale),
                    obscure: _obscureCurrent, isDark: isDark,
                    onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent)),
                const SizedBox(height: 10),
                _PasswordField(controller: _newCtrl,
                    label: AppStrings.get('new_password', locale),
                    obscure: _obscureNew, isDark: isDark,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew)),
                const SizedBox(height: 10),
                _PasswordField(controller: _confirmCtrl,
                    label: AppStrings.get('confirm_password', locale),
                    obscure: _obscureConfirm, isDark: isDark,
                    onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() { _step = 1; _error = null; }),
                  child: Text(AppStrings.get('forgot_password', locale),
                      style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('save', locale),
                    loading: _loading, onTap: _changePassword),
              ],
              if (_step == 1) ...[
                Text(AppStrings.get('reset_password', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 8),
                Text(AppStrings.get('reset_password_phone_prompt', locale),
                    style: TextStyle(fontSize: 13, color: textSecondary)),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
                      child: const Row(children: [
                        Text('🇺🇿', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 6),
                        Text('+998', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.number,
                        enabled: false,
                        style: TextStyle(fontSize: 16, color: textPrimary, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: '77 014 77 03',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                      ),
                    ),
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('send_code', locale),
                    loading: _loading, onTap: _sendForgotOtp),
              ],
              if (_step == 2) ...[
                Text(AppStrings.get('enter_otp', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 8),
                Text('+998${_phoneCtrl.text} ${AppStrings.get('otp_sent', locale)}',
                    style: TextStyle(fontSize: 13, color: textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: textPrimary, letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('verify', locale),
                    loading: _loading, onTap: _verifyOtp),
              ],
              if (_step == 3) ...[
                Text(AppStrings.get('set_new_password', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 8),
                Text(
                  AppStrings.get('reset_password_otp_note', locale),
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                const SizedBox(height: 16),
                _PasswordField(controller: _newCtrl,
                    label: AppStrings.get('new_password', locale),
                    obscure: _obscureNew, isDark: isDark,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew)),
                const SizedBox(height: 10),
                _PasswordField(controller: _confirmCtrl,
                    label: AppStrings.get('confirm_password', locale),
                    obscure: _obscureConfirm, isDark: isDark,
                    onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('save', locale),
                    loading: _loading, onTap: _setNewPassword),
              ],
            ]),
    );
  }
}

class _ChangePhoneSheet extends ConsumerStatefulWidget {
  final bool isDark;
  final String locale;
  final VoidCallback onDone;
  final String currentPhone;
  const _ChangePhoneSheet({required this.isDark, required this.locale, required this.onDone, required this.currentPhone});
  @override
  ConsumerState<_ChangePhoneSheet> createState() => _ChangePhoneSheetState();
}

class _ChangePhoneSheetState extends ConsumerState<_ChangePhoneSheet> {
  int _step = -1;
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _currentPhoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _currentPhoneCtrl.text = widget.currentPhone.replaceFirst('+998', '').replaceAll(RegExp(r'\D'), '');
    _phoneCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _currentPhoneCtrl.dispose();
    super.dispose();
  }

  String _extractErrorMessage(Object e, String locale) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return AppStrings.get('generic_error', locale);
  }

  Future<void> _requestChange() async {
    final rawPhone = _phoneCtrl.text.replaceAll(' ', '');
    if (rawPhone.length != 9) {
      setState(() => _error = AppStrings.get('phone_incomplete_error', widget.locale));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).requestPhoneChange('+998$rawPhone');
      setState(() { _step = 1; _loading = false; });
    } catch (e) {
      setState(() {
        _error = _extractErrorMessage(e, widget.locale);
        _loading = false;
      });
    }
  }

  Future<void> _verifyChange() async {
    if (_otpCtrl.text.length < 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rawPhone = _phoneCtrl.text.replaceAll(' ', '');
      await ref.read(authRepositoryProvider).verifyPhoneChange('+998$rawPhone', _otpCtrl.text);
      setState(() { _success = true; _loading = false; });
    } catch (e) {
      setState(() {
        _error = _extractErrorMessage(e, widget.locale);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final locale = widget.locale;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final hasNewPhone = _phoneCtrl.text.replaceAll(' ', '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _success
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Icon(Icons.check_circle, color: AppTheme.successColor, size: 48),
              const SizedBox(height: 16),
              Text(AppStrings.get('phone_changed_success', locale),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              _GradientButton(label: AppStrings.get('close', locale),
                  onTap: () { Navigator.pop(context); widget.onDone(); }),
            ])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              if (_step == -1) ...[
                Text(AppStrings.get('connected_phone_title', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 16),
                Text(AppStrings.get('current_phone_number', locale),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
                      child: const Row(children: [
                        Text('🇺🇿', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 6),
                        Text('+998', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _currentPhoneCtrl,
                        enabled: false,
                        style: TextStyle(fontSize: 16, color: textPrimary, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('close', locale),
                    onTap: () => Navigator.pop(context)),
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _step = 0),
                    child: Text(AppStrings.get('change_phone_button', locale),
                        style: const TextStyle(color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
              if (_step == 0) ...[
                Text(AppStrings.get('change_phone', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 16),
                Text(AppStrings.get('new_phone_number', locale),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
                      child: const Row(children: [
                        Text('🇺🇿', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 6),
                        Text('+998', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                          _PhoneNumberFormatter(),
                        ],
                        style: TextStyle(fontSize: 16, color: textPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('enter_new_phone_hint', locale),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                      ),
                    ),
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                hasNewPhone
                    ? _GradientButton(label: AppStrings.get('submit_label', locale),
                        loading: _loading, onTap: _requestChange)
                    : _GradientButton(label: AppStrings.get('close', locale),
                        onTap: () => setState(() => _step = -1)),
              ],
              if (_step == 1) ...[
                Text(AppStrings.get('enter_otp', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 8),
                Text(AppStrings.get('phone_change_otp_sent', locale)
                        .replaceAll('{phone}', '+998 ${_phoneCtrl.text}'),
                    style: TextStyle(fontSize: 13, color: textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: textPrimary, letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                _GradientButton(label: AppStrings.get('verify', locale),
                    loading: _loading, onTap: _verifyChange),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() { _step = 0; _otpCtrl.clear(); _error = null; }),
                  child: Text(AppStrings.get('resend_code', locale),
                      style: const TextStyle(color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ]),
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 1 || i == 4 || i == 6) {
        if (i != digits.length - 1) buffer.write(' ');
      }
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ===== DOC CARD (2x2 grid) =====
class _DocCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? url;
  final Uint8List? newBytes;
  final bool isDark;
  final String locale;
  final VoidCallback onPick;
  final VoidCallback onView;
  const _DocCard({
    required this.label, required this.icon, this.url, this.newBytes,
    required this.isDark, required this.locale,
    required this.onPick, required this.onView,
  });
  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final hasNew = newBytes != null;
    final hasExisting = url != null;
    final hasAny = hasNew || hasExisting;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: hasNew
              ? AppTheme.successColor.withOpacity(0.06)
              : hasExisting
                  ? AppTheme.primaryColor.withOpacity(0.04)
                  : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasNew
                ? AppTheme.successColor.withOpacity(0.4)
                : hasExisting
                    ? AppTheme.primaryColor.withOpacity(0.3)
                    : border,
            width: hasAny ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (hasNew)
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.memory(newBytes!, width: double.infinity,
                    height: double.infinity, fit: BoxFit.cover),
              )
            else if (hasExisting)
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(url!, width: double.infinity,
                    height: double.infinity, fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : const Center(child: AppLoadingIndicator(strokeWidth: 2)),
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(icon, size: 28, color: AppTheme.primaryColor))),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 28, color: textSecondary),
                    const SizedBox(height: 6),
                    Text(AppStrings.get('tap_to_upload', locale),
                        style: TextStyle(fontSize: 10, color: textSecondary),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            if (hasAny)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: const TextStyle(fontSize: 10, color: Colors.white,
                                fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      GestureDetector(
                        onTap: onView,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.open_in_new, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Positioned(
                bottom: 6, left: 8, right: 8,
                child: Text(label,
                    style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            if (hasNew)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Yangi', style: TextStyle(fontSize: 9,
                      color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===== HELPERS =====
class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _GradientButton({required this.label, this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (loading || onTap == null) ? null : onTap,
      child: Container(
        width: double.infinity, height: 48,
        decoration: BoxDecoration(
          gradient: (!loading && onTap != null)
              ? const LinearGradient(
                  colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight)
              : null,
          color: (loading || onTap == null) ? null : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            if (loading)
              const SizedBox(width: 22, height: 22,
                  child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
            else
              Text(label, style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool isDark;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.label,
      required this.obscure, required this.isDark, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary, size: 20),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final bool isDark;
  final VoidCallback? onTap;
  const _MenuItem({required this.icon, required this.iconColor, required this.label,
      this.value, required this.isDark, this.onTap});
  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    return ListTile(
      visualDensity: VisualDensity.standard,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: iconColor),
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: textSecondary)),
          const SizedBox(width: 4),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: textSecondary),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}