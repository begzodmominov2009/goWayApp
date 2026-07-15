import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/services/fcm_service.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String role;
  const OtpScreen({super.key, required this.phone, required this.role});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  bool _loading = false;
  int _seconds = 60;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _seconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds == 0) {
        t.cancel();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length < 6) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final res = await authRepo.verifyOtp(
        phone: widget.phone,
        code: _otpController.text,
        role: widget.role,
      );

      if (res['success'] == true) {
        final token = res['data']['accessToken'] ?? res['data']['token'];
        final user = res['data']['user'];
        final role = user['role'] as String;

        await authRepo.saveToken(token);
        await authRepo.saveRole(role);

        // Tizimga kirish muvaffaqiyatli bo'lgach — FCM tokenni sozlaymiz
        // (token backend'ga yuborilishi uchun avtorizatsiya kerak edi)
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
              // Forma hali to'ldirilmagan — backend bo'sh Driver yozuvini
              // yaratgan bo'lishi mumkin (status null emas bo'lsa ham).
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
      setState(() => _error = 'Kod noto\'g\'ri. Qayta urinib ko\'ring.');
      _otpController.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    try {
      await ref.read(authRepositoryProvider).sendOtp(widget.phone, widget.role);
      _startTimer();
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = 'Xatolik yuz berdi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultPinTheme = PinTheme(
      width: 64,
      height: 64,
      textStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.borderColor,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
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
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: Text('🔐', style: TextStyle(fontSize: 28))),
              ),
              const SizedBox(height: 24),
              Text(AppStrings.get('enter_code', locale),
                  style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                  )),
              const SizedBox(height: 8),
              Text('${widget.phone} ${AppStrings.get('code_sent', locale)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                  )),
              const SizedBox(height: 40),
              Center(
                child: Pinput(
                  controller: _otpController,
                  length: 6,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                      border: Border.all(color: AppTheme.primaryColor, width: 2),
                    ),
                  ),
                  errorPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                      border: Border.all(color: AppTheme.errorColor, width: 2),
                    ),
                  ),
                  onCompleted: (_) => _verifyOtp(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.errorColor, fontSize: 14)),
                ),
              ],
              const SizedBox(height: 32),
              Center(
                child: _seconds > 0
                    ? Text('${AppStrings.get('resend_in', locale)} $_seconds s',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                          fontSize: 14,
                        ))
                    : TextButton(
                        onPressed: _resendOtp,
                        child: Text(AppStrings.get('resend', locale),
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _loading ? null : _verifyOtp,
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(AppStrings.get('verify', locale)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}