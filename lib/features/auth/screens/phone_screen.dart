import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/services/fcm_service.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  final String role;
  const PhoneScreen({super.key, required this.role});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String _digits = '';

  String get _backendPhone => '+998$_digits';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // Parol bilan kirish
  Future<void> _loginWithPassword() async {
    if (_digits.length < 9) {
      setState(() => _error = 'Telefon raqamni to\'liq kiriting');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Parolni kiriting');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final res = await authRepo.loginWithPassword(
        phone: _backendPhone,
        password: _passwordCtrl.text,
      );
      if (res['success'] == true) {
        final token = res['data']['accessToken'] ?? res['data']['token'];
        final user = res['data']['user'];
        final role = user['role'] as String;
        await authRepo.saveToken(token);
        await authRepo.saveRole(role);

        // Parol bilan kirish muvaffaqiyatli bo'lgach — FCM tokenni sozlaymiz
        FcmService.init(ref);

        if (mounted) {
          if (role == 'CLIENT') {
            context.go(AppRoutes.clientHome);
          } else if (role == 'DRIVER') {
            // Login response da driver yo'q — profile dan olamiz
            try {
              final status = await authRepo.getDriverStatus();
              final vs = status['verificationStatus'] as String?;
              if (vs == 'APPROVED') {
                context.go(AppRoutes.driverHome);
              } else if (vs == null) {
                context.go(AppRoutes.driverRegister);
              } else {
                context.go(AppRoutes.pendingApproval);
              }
            } catch (_) {
              context.go(AppRoutes.driverRegister);
            }
          }
        }
      }
    } catch (e) {
      final msg = e.toString();
      // Parol o'rnatilmagan bo'lsa OTP ga yo'naltiramiz
      if (msg.contains('o\'rnatilmagan') || msg.contains('password') || msg.contains('404') || msg.contains('topilmadi')) {
        try {
          await ref.read(authRepositoryProvider).sendOtp(_backendPhone, widget.role);
          if (mounted) {
            context.go(AppRoutes.otp, extra: {
              'phone': _backendPhone,
              'role': widget.role,
            });
          }
        } catch (_) {
          setState(() => _error = 'Xatolik yuz berdi. Qayta urinib ko\'ring.');
        }
      } else {
        setState(() => _error = 'Telefon raqam yoki parol noto\'g\'ri');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // OTP yuborish (yangi hisob)
  Future<void> _sendOtp() async {
    if (_digits.length < 9) {
      setState(() => _error = 'Telefon raqamni to\'liq kiriting');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).sendOtp(_backendPhone, widget.role);
      if (mounted) {
        context.go(AppRoutes.otp, extra: {
          'phone': _backendPhone,
          'role': widget.role,
        });
      }
    } catch (e) {
      setState(() => _error = 'Xatolik yuz berdi. Qayta urinib ko\'ring.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _phoneInput(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.borderColor)),
            ),
            child: Row(
              children: [
                const Text('🇺🇿', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 6),
                Text('+998', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                )),
              ],
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '77 014 77 03',
                hintStyle: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary, fontWeight: FontWeight.w400, letterSpacing: 0),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              ),
              onChanged: (v) => setState(() => _digits = v),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: FaIcon(FontAwesomeIcons.arrowLeft, size: 18, color: textPrimary),
          onPressed: () => context.go(AppRoutes.roleSelect),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.mobileScreen, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(height: 24),
              Text(AppStrings.get('phone_title', locale),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 8),
              Text(AppStrings.get('phone_subtitle', locale),
                  style: TextStyle(fontSize: 16, color: textSecondary)),
              const SizedBox(height: 32),

              // Telefon
              _phoneInput(isDark),
              const SizedBox(height: 12),

              // Parol
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  style: TextStyle(fontSize: 16, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Parol',
                    hintStyle: TextStyle(color: textSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: textSecondary, size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),

              // Kirish tugmasi
              GestureDetector(
                onTap: _loading ? null : _loginWithPassword,
                child: Container(
                  width: double.infinity, height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _loading
                        ? const AppLoadingIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text('Kirish', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('yoki', style: TextStyle(color: textSecondary, fontSize: 13)),
                  ),
                  Expanded(child: Divider(color: border)),
                ],
              ),
              const SizedBox(height: 24),

              // Yangi hisob — OTP
              GestureDetector(
                onTap: _loading ? null : _sendOtp,
                child: Container(
                  width: double.infinity, height: 52,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      'Yangi hisob yaratish',
                      style: const TextStyle(color: AppTheme.primaryColor, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'OTP kod yuboriladi',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}