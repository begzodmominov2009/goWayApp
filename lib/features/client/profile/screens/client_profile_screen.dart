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
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/router/app_router.dart';

class ClientProfileScreen extends ConsumerStatefulWidget {
  const ClientProfileScreen({super.key});
  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends ConsumerState<ClientProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  Uint8List? _avatarBytes;
  bool _avatarUploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(clientRepositoryProvider).getProfile();
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _initials() {
    final name = _profile?['fullName'] as String? ?? '';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty)
      return parts[0][0].toUpperCase();
    return 'C';
  }

  // Galereyadan rasm tanlab, darhol serverga yuklaydi — muvaffaqiyatli
  // bo'lsa profil qayta yuklanib, header'dagi avatar yangi rasm bilan
  // yangilanadi. Xato bo'lsa, tanlangan (hali saqlanmagan) rasm bekor
  // qilinib, foydalanuvchiga SnackBar orqali xabar beriladi.
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (!mounted) return;
    setState(() { _avatarBytes = bytes; _avatarUploading = true; });
    final locale = ref.read(localeProvider).languageCode;
    try {
      await ref.read(clientRepositoryProvider).updateAvatar(bytes, img.name);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final themeMode = ref.watch(themeModeProvider);
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary =
        isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary =
        isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    // Dark mode — to'q navy gradient (avvalgidek). Light mode — och,
    // yumshoq ko'k tuslar, ko'zga yengilroq.
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
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined,
                color: AppTheme.primaryColor, size: 22),
            onPressed: _showEditNameSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: AppLoadingIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Gradient header — temaga qarab och/to'q
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
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.4), width: 2),
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
                            Text(_profile?['fullName'] ?? 'Client',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                final shortId =
                                    _profile?['user']?['shortId'] ?? '';
                                Clipboard.setData(ClipboardData(text: shortId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('ID nusxalandi!'),
                                      backgroundColor: AppTheme.successColor,
                                      duration: Duration(seconds: 2)),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      '#${_profile?['user']?['shortId'] ?? ''}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              Colors.white.withOpacity(0.85))),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy,
                                      size: 12,
                                      color: Colors.white.withOpacity(0.7)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_profile?['user']?['phone'] ?? '',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.75))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Otish yo'llari — Buyurtmalarim, Bildirishnomalar
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(children: [
                    _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppTheme.primaryColor,
                      label: AppStrings.get('my_orders', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.clientOrders),
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
                      icon: Icons.bookmark_border,
                      iconColor: AppTheme.primaryColor,
                      label: AppStrings.get('saved_places', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.clientSavedAddresses),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Sozlamalar
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(AppStrings.get('app_settings', locale),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                          letterSpacing: 0.6)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(children: [
                    _MenuItem(
                      icon: Icons.language_outlined,
                      iconColor: textSecondary,
                      label: AppStrings.get('language', locale),
                      value: locale == 'uz'
                          ? 'O\'zbek'
                          : locale == 'ru'
                              ? 'Русский'
                              : 'English',
                      isDark: isDark,
                      onTap: _showLanguageSheet,
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      iconColor: textSecondary,
                      label: AppStrings.get('theme', locale),
                      value: themeMode == ThemeMode.dark
                          ? AppStrings.get('theme_dark', locale)
                          : themeMode == ThemeMode.light
                              ? AppStrings.get('theme_light', locale)
                              : AppStrings.get('theme_auto', locale),
                      isDark: isDark,
                      onTap: _showThemeSheet,
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.lock_outline,
                      iconColor: textSecondary,
                      label: AppStrings.get('change_password', locale),
                      isDark: isDark,
                      onTap: _showChangePasswordSheet,
                    ),
                    Divider(height: 8, color: border, indent: 68),
                    _MenuItem(
                      icon: Icons.description_outlined,
                      iconColor: textSecondary,
                      label: AppStrings.get('terms', locale),
                      isDark: isDark,
                      onTap: () => context.push(AppRoutes.terms),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Chiqish
                GestureDetector(
                  onTap: _showLogoutDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFdc2626).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFdc2626).withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFdc2626).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.logout_outlined,
                            color: Color(0xFFdc2626), size: 16),
                      ),
                      const SizedBox(width: 12),
                      Text(AppStrings.get('logout', locale),
                          style: const TextStyle(
                              color: Color(0xFFdc2626),
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFFdc2626), size: 18),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  void _showEditNameSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    final ctrl = TextEditingController(text: _profile?['fullName'] ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppTheme.borderColor,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(AppStrings.get('edit_profile', locale),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary),
                  decoration: InputDecoration(
                      labelText: AppStrings.get('full_name', locale)),
                ),
                const SizedBox(height: 16),
                _GradientButton(
                  loading: saving,
                  label: AppStrings.get('save', locale),
                  onTap: () async {
                    setSt(() => saving = true);
                    try {
                      await ref
                          .read(clientRepositoryProvider)
                          .updateProfile(fullName: ctrl.text.trim());
                      await _load();
                      if (mounted) Navigator.pop(ctx);
                    } catch (_) {
                      setSt(() => saving = false);
                    }
                  },
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
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true, obscure2 = true, obscure3 = true;
    bool loading = false;
    String? error;
    bool success = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final surface = isDark ? AppTheme.darkSurface : Colors.white;
          final textPrimary =
              isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
          final textSecondary =
              isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
          final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
          return Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: success
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                          child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: border,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 24),
                      const Icon(Icons.check_circle,
                          color: AppTheme.successColor, size: 48),
                      const SizedBox(height: 16),
                      Text(AppStrings.get('password_changed', locale),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: textPrimary),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      _GradientButton(
                          label: AppStrings.get('close', locale),
                          onTap: () => Navigator.pop(ctx)),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: border,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),
                      Text(AppStrings.get('change_password', locale),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: textPrimary)),
                      const SizedBox(height: 16),
                      _PassField(
                          controller: currentCtrl,
                          label: AppStrings.get('current_password', locale),
                          obscure: obscure1,
                          isDark: isDark,
                          onToggle: () => setSt(() => obscure1 = !obscure1)),
                      const SizedBox(height: 10),
                      _PassField(
                          controller: newCtrl,
                          label: AppStrings.get('new_password', locale),
                          obscure: obscure2,
                          isDark: isDark,
                          onToggle: () => setSt(() => obscure2 = !obscure2)),
                      const SizedBox(height: 10),
                      _PassField(
                          controller: confirmCtrl,
                          label: AppStrings.get('confirm_password', locale),
                          obscure: obscure3,
                          isDark: isDark,
                          onToggle: () => setSt(() => obscure3 = !obscure3)),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error!,
                            style: const TextStyle(
                                color: AppTheme.errorColor, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      _GradientButton(
                        label: AppStrings.get('save', locale),
                        loading: loading,
                        onTap: () async {
                          if (newCtrl.text.length < 6) {
                            setSt(() => error =
                                AppStrings.get('password_too_short', locale));
                            return;
                          }
                          if (newCtrl.text != confirmCtrl.text) {
                            setSt(() => error =
                                AppStrings.get('password_mismatch', locale));
                            return;
                          }
                          setSt(() {
                            loading = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(clientRepositoryProvider)
                                .setPassword(newCtrl.text);
                            setSt(() {
                              loading = false;
                              success = true;
                            });
                          } catch (e) {
                            setSt(() {
                              loading = false;
                              error = 'Xatolik yuz berdi';
                            });
                          }
                        },
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _showLanguageSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final current = ref.read(localeProvider).languageCode;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tilni tanlang',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...([
                ('uz', 'O\'zbek', '🇺🇿'),
                ('ru', 'Русский', '🇷🇺'),
                ('en', 'English', '🇬🇧')
              ].map((item) => ListTile(
                    leading:
                        Text(item.$3, style: const TextStyle(fontSize: 22)),
                    title: Text(item.$2,
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary,
                          fontWeight: current == item.$1
                              ? FontWeight.w700
                              : FontWeight.w400,
                        )),
                    trailing: current == item.$1
                        ? const Icon(Icons.check,
                            color: AppTheme.primaryColor, size: 18)
                        : null,
                    onTap: () {
                      ref.read(localeProvider.notifier).setLocale(item.$1);
                      Navigator.pop(ctx);
                    },
                  ))),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final current = ref.read(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Temani tanlang',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...([
                (
                  ThemeMode.system,
                  AppStrings.get('theme_auto', locale),
                  Icons.brightness_auto_outlined
                ),
                (
                  ThemeMode.light,
                  AppStrings.get('theme_light', locale),
                  Icons.light_mode_outlined
                ),
                (
                  ThemeMode.dark,
                  AppStrings.get('theme_dark', locale),
                  Icons.dark_mode_outlined
                ),
              ].map((item) => ListTile(
                    leading: Icon(item.$3,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.textSecondary),
                    title: Text(item.$2,
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary,
                          fontWeight: current == item.$1
                              ? FontWeight.w700
                              : FontWeight.w400,
                        )),
                    trailing: current == item.$1
                        ? const Icon(Icons.check,
                            color: AppTheme.primaryColor, size: 18)
                        : null,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('logout', locale),
            style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                fontWeight: FontWeight.w700)),
        content: Text('Tizimdan chiqmoqchimisiz?',
            style: TextStyle(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale),
                style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chiqish',
                style: TextStyle(
                    color: Color(0xFFdc2626), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authRepositoryProvider).logout();
      if (mounted) context.go(AppRoutes.onboarding);
    }
  }
}

// ===== HELPERS =====
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final bool isDark;
  final VoidCallback? onTap;
  const _MenuItem(
      {required this.icon,
      required this.iconColor,
      required this.label,
      this.value,
      required this.isDark,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    return ListTile(
      visualDensity: VisualDensity.standard,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: iconColor),
      ),
      title: Text(label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: TextStyle(fontSize: 12, color: textSecondary)),
          const SizedBox(width: 4),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: textSecondary),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _GradientButton(
      {required this.label, this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (loading || onTap == null) ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: AppLoadingIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
        ),
      ),
    );
  }
}

class _PassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool isDark;
  final VoidCallback onToggle;
  const _PassField(
      {required this.controller,
      required this.label,
      required this.obscure,
      required this.isDark,
      required this.onToggle});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color:
                  isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
              size: 20),
          onPressed: onToggle,
        ),
      ),
    );
  }
}