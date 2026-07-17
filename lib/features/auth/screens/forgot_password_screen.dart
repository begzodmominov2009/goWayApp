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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialPhone;
  final String role;
  const ForgotPasswordScreen({super.key, this.initialPhone, required this.role});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  int _stage = 0;

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _loading = false;
  String? _error;

  int _seconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPhone;
    if (initial != null) {
      _phoneController.text = initial.replaceFirst('+998', '').replaceAll(RegExp(r'\D'), '');
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _fullPhone => '+998${_phoneController.text.replaceAll(RegExp(r'\D'), '')}';

  bool get _isPhoneValid => _phoneController.text.replaceAll(RegExp(r'\D'), '').length >= 9;

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

  Future<void> _sendCode() async {
    if (!_isPhoneValid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.sendOtp(_fullPhone, widget.role);
      if (mounted) {
        _startTimer();
        setState(() => _stage = 1);
      }
    } catch (e) {
      final locale = ref.read(localeProvider).languageCode;
      setState(() => _error = AppStrings.get('generic_error', locale));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    try {
      await ref.read(authRepositoryProvider).sendOtp(_fullPhone, widget.role);
      _startTimer();
      setState(() => _error = null);
    } catch (e) {
      final locale = ref.read(localeProvider).languageCode;
      setState(() => _error = AppStrings.get('generic_error', locale));
    }
  }

  void _submitCode() {
    if (_otpController.text.length < 6) return;
    setState(() {
      _error = null;
      _stage = 2;
    });
  }

  Future<void> _savePassword() async {
    final locale = ref.read(localeProvider).languageCode;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.length < 6) {
      setState(() => _error = AppStrings.get('password_too_short', locale));
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = AppStrings.get('password_mismatch', locale));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.resetPassword(
        phone: _fullPhone,
        code: _otpController.text,
        newPassword: newPassword,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('password_changed', locale))),
        );
        context.go(AppRoutes.phone, extra: widget.role);
      }
    } catch (e) {
      setState(() {
        _error = AppStrings.get('invalid_or_expired_code', locale);
        _stage = 1;
      });
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
          onPressed: () {
            if (_stage > 0) {
              setState(() {
                _error = null;
                _stage -= 1;
              });
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                _stage == 0
                    ? AppStrings.get('reset_password', locale)
                    : _stage == 1
                        ? AppStrings.get('enter_code', locale)
                        : AppStrings.get('set_new_password', locale),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _stage == 0
                    ? AppStrings.get('reset_password_subtitle', locale)
                    : _stage == 1
                        ? '$_fullPhone ${AppStrings.get('code_sent', locale)}'
                        : AppStrings.get('set_new_password_subtitle', locale),
                style: TextStyle(fontSize: 16, color: textSecondary),
              ),
              const SizedBox(height: 40),
              if (_stage == 0) ..._buildPhoneStage(locale, textPrimary, textSecondary, border, surface),
              if (_stage == 1) ..._buildOtpStage(locale, isDark),
              if (_stage == 2) ..._buildPasswordStage(locale, textPrimary, textSecondary, border, surface),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: _loading ? null : _primaryAction(),
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _stage == 0
                            ? AppStrings.get('send_code', locale)
                            : _stage == 1
                                ? AppStrings.get('continue_btn', locale)
                                : AppStrings.get('save', locale),
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  VoidCallback? _primaryAction() {
    if (_stage == 0) return _isPhoneValid ? _sendCode : null;
    if (_stage == 1) return _otpController.text.length == 6 ? _submitCode : null;
    return _savePassword;
  }

  List<Widget> _buildPhoneStage(
    String locale,
    Color textPrimary,
    Color textSecondary,
    Color border,
    Color surface,
  ) {
    return [
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
                  filled: false,
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
    ];
  }

  List<Widget> _buildOtpStage(String locale, bool isDark) {
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
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

    return [
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
          onChanged: (_) => setState(() {}),
          onCompleted: (_) => _submitCode(),
        ),
      ),
      const SizedBox(height: 24),
      Center(
        child: _seconds > 0
            ? Text(
                '${AppStrings.get('resend_in', locale)} $_seconds s',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                  fontSize: 14,
                ),
              )
            : TextButton(
                onPressed: _resendCode,
                child: Text(
                  AppStrings.get('resend', locale),
                  style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
      ),
    ];
  }

  List<Widget> _buildPasswordStage(
    String locale,
    Color textPrimary,
    Color textSecondary,
    Color border,
    Color surface,
  ) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: TextField(
          controller: _newPasswordController,
          obscureText: _obscureNewPassword,
          style: TextStyle(fontSize: 16, color: textPrimary),
          decoration: InputDecoration(
            filled: false,
            hintText: AppStrings.get('new_password', locale),
            hintStyle: TextStyle(color: textSecondary),
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                  color: textSecondary, size: 20),
              onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          style: TextStyle(fontSize: 16, color: textPrimary),
          decoration: InputDecoration(
            filled: false,
            hintText: AppStrings.get('confirm_password', locale),
            hintStyle: TextStyle(color: textSecondary),
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                  color: textSecondary, size: 20),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
      ),
    ];
  }
}
