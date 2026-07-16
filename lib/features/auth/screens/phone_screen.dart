import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  bool _useOtpFlow = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _fullPhone => '+998${_phoneController.text.replaceAll(RegExp(r'\D'), '')}';

  bool get _isPhoneValid => _phoneController.text.replaceAll(RegExp(r'\D'), '').length >= 9;

  Future<void> _submit() async {
    if (!_isPhoneValid) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final authRepo = ref.read(authRepositoryProvider);

    try {
      if (_useOtpFlow) {
        await authRepo.sendOtp(_fullPhone, widget.role);
        if (mounted) {
          context.push(AppRoutes.otp, extra: {'phone': _fullPhone, 'role': widget.role});
        }
        return;
      }

      // Parol bilan kirish
      if (_passwordController.text.isEmpty) {
        setState(() { _loading = false; _error = 'Parolni kiriting'; });
        return;
      }

      final res = await authRepo.loginWithPassword(
        phone: _fullPhone,
        password: _passwordController.text,
      );

      if (res['success'] == true) {
        final token = res['data']['accessToken'] ?? res['data']['token'];
        final refreshToken = res['data']['refreshToken'] as String?;
        final user = res['data']['user'];
        final role = user['role'] as String;

        await authRepo.saveToken(token);
        // Refresh token — accessToken (15 daqiqa) eskirganda, foyda-
        // lanuvchini qayta login qildirmasdan yangi token olish uchun.
        if (refreshToken != null) {
          await authRepo.saveRefreshToken(refreshToken);
        }
        await authRepo.saveRole(role);

        FcmService.init(ref);

        if (mounted) {
          if (role == 'CLIENT') {
            final client = res['data']['client'];
            if (client == null || client['fullName'] == null) {
              context.go(AppRoutes.clientRegister);
            } else {
              context.go(AppRoutes.clientHome);
            }
          } else if (role == 'DRIVER') {
            final driver = res['data']['driver'];
            final status = driver != null ? driver['verificationStatus'] as String? : null;
            if (driver == null || driver['fullName'] == null || driver['truckType'] == null) {
              context.go(AppRoutes.driverRegister);
            } else if (status == 'APPROVED') {
              context.go(AppRoutes.driverHome);
            } else {
              context.go(AppRoutes.pendingApproval);
            }
          }
        }
      }
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('o\'rnatilmagan') ||
          message.contains('password') ||
          message.contains('404') ||
          message.contains('topilmadi')) {
        // Parol hali o'rnatilmagan — OTP orqali kirish oqimiga o'tamiz
        setState(() {
          _useOtpFlow = true;
          _loading = false;
        });
        await _submit();
        return;
      }
      setState(() => _error = 'Telefon raqam yoki parol noto\'g\'ri');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.backgroundColor;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(AppStrings.get('phone_title', locale),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 8),
              Text(AppStrings.get('phone_subtitle', locale),
                  style: TextStyle(fontSize: 16, color: textSecondary)),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Text('🇺🇿 +998', style: TextStyle(fontSize: 16, color: textPrimary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 24, color: border),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(fontSize: 16, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: '90 123 45 67',
                          hintStyle: TextStyle(color: textSecondary),
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_useOtpFlow) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(fontSize: 16, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Parol',
                      hintStyle: TextStyle(color: textSecondary),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: textSecondary, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              if (!_useOtpFlow)
                TextButton(
                  onPressed: () {
                    context.push('/forgot-password', extra: {'phone': _fullPhone, 'role': widget.role});
                  },
                  child: Text(AppStrings.get('forgot_password', locale),
                      style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: (_isPhoneValid && !_loading) ? _submit : null,
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_useOtpFlow
                        ? AppStrings.get('send_code', locale)
                        : AppStrings.get('verify', locale)),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _useOtpFlow = !_useOtpFlow),
                  child: Text(
                    _useOtpFlow ? 'Parol bilan kirish' : 'SMS kod bilan kirish',
                    style: const TextStyle(color: AppTheme.primaryColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}