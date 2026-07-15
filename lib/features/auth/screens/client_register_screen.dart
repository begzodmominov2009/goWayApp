import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/router/app_router.dart';

class ClientRegisterScreen extends ConsumerStatefulWidget {
  const ClientRegisterScreen({super.key});

  @override
  ConsumerState<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends ConsumerState<ClientRegisterScreen> {
  final _fullNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_fullNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ismingizni kiriting');
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      setState(() => _error = AppStrings.get('password_too_short', ref.read(localeProvider).languageCode));
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = AppStrings.get('password_mismatch', ref.read(localeProvider).languageCode));
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      // 1. Ism yangilash
      await ref.read(clientRepositoryProvider).updateProfile(
        fullName: _fullNameCtrl.text.trim(),
      );

      // 2. Parol o'rnatish
      await ref.read(clientRepositoryProvider).setPassword(_passwordCtrl.text);

      if (mounted) context.go(AppRoutes.clientHome);
    } catch (e) {
      setState(() => _error = 'Xatolik yuz berdi');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Hisob yaratish',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Icon
            Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.person_outline, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: Text('Yuk beruvchi',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textPrimary)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Ma\'lumotlaringizni kiriting',
                  style: TextStyle(fontSize: 14, color: textSecondary)),
            ),
            const SizedBox(height: 32),

            // Ism
            Text('To\'liq ism', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: textSecondary, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _fullNameCtrl,
                style: TextStyle(color: textPrimary),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Ism Familiya',
                  hintStyle: TextStyle(color: textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.person_outline, color: textSecondary, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Parol
            Text('Parol', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: textSecondary, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Kamida 6 ta belgi',
                  hintStyle: TextStyle(color: textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.lock_outline, color: textSecondary, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: textSecondary, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Parol tasdiqlash
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Parolni takrorlang',
                  hintStyle: TextStyle(color: textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.lock_outline, color: textSecondary, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: textSecondary, size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
            const SizedBox(height: 24),

            // Submit
            GestureDetector(
              onTap: _loading ? null : _submit,
              child: Container(
                width: double.infinity, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Boshlash',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}