import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/auth_repository.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState
    extends ConsumerState<PendingApprovalScreen> {
  Timer? _timer;
  bool _checking = false;
  String? _rejectionReason;
  bool _isRejected = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    _checking = true;
    try {
      final status = await ref.read(authRepositoryProvider).getDriverStatus();
      final verificationStatus = status['verificationStatus'] as String?;
      if (!mounted) return;
      if (verificationStatus == 'APPROVED') {
        _timer?.cancel();
        context.go(AppRoutes.driverHome);
      } else if (verificationStatus == 'REJECTED') {
        _timer?.cancel();
        setState(() {
          _isRejected = true;
          _rejectionReason = status['rejectionReason'] as String?;
        });
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  void _resubmit() => context.go(AppRoutes.driverRegister);

  void _logout() async {
    await ref.read(authRepositoryProvider).logout();
    if (mounted) context.go(AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isRejected) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('❌', style: TextStyle(fontSize: 60)),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Hujjatlar rad etildi',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Adminlar hujjatlaringizni ko\'rib chiqdi va rad etdi.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_rejectionReason != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.errorColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sabab:',
                          style: TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _rejectionReason!,
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _resubmit,
                    child: const Text('Qayta yuborish'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _logout,
                    child: const Text('Chiqish'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('⏳', style: TextStyle(fontSize: 60)),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                AppStrings.get('pending_title', locale),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.get('pending_subtitle', locale),
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  AppStrings.get('pending_time', locale),
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.warningColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppTheme.warningColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppStrings.get('waiting', locale),
                      style: const TextStyle(
                        color: AppTheme.warningColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: AppLoadingIndicator(
                        strokeWidth: 2,
                        color: AppTheme.warningColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _StepItem(
                number: '1',
                title: AppStrings.get('step_sent', locale),
                isDone: true,
                isDark: isDark,
              ),
              _StepItem(
                number: '2',
                title: AppStrings.get('step_reviewing', locale),
                isDone: false,
                isActive: true,
                isDark: isDark,
              ),
              _StepItem(
                number: '3',
                title: AppStrings.get('step_approved', locale),
                isDone: false,
                isDark: isDark,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: _logout,
                child: Text(
                  'Chiqish',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary,
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

class _StepItem extends StatelessWidget {
  final String number;
  final String title;
  final bool isDone;
  final bool isActive;
  final bool isDark;

  const _StepItem({
    required this.number,
    required this.title,
    required this.isDone,
    this.isActive = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDone
                  ? AppTheme.successColor
                  : isActive
                      ? AppTheme.warningColor
                      : isDark
                          ? AppTheme.darkSurface
                          : AppTheme.backgroundColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDone
                    ? AppTheme.successColor
                    : isActive
                        ? AppTheme.warningColor
                        : isDark
                            ? AppTheme.darkBorder
                            : AppTheme.borderColor,
              ),
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : isActive
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: AppLoadingIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          number,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isDone || isActive ? FontWeight.w600 : FontWeight.w400,
              color: isDone
                  ? AppTheme.successColor
                  : isActive
                      ? AppTheme.warningColor
                      : isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}