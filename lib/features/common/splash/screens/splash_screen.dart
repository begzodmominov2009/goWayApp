import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/utils/map_icon_helper.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  late final AnimationController _textController;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;

  // Logo tugagach ishga tushadigan yengil "nafas olish" effekti — xuddi
  // shu controller pastdagi uchta nuqtaning fazali pulsatsiyasi uchun
  // ham qayta ishlatiladi (alohida controller shart emas).
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOut));

    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));
    _textFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseScale = Tween<double>(begin: 1.0, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // Elastik "sakrash" bilan to'qnashmasligi uchun, nafas olish effekti
    // faqat logo animatsiyasi to'liq tugagach boshlanadi.
    _logoController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.repeat(reverse: true);
      }
    });

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _textController.forward();
    });

    _checkAuth();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    final authRepo = ref.read(authRepositoryProvider);

    // Token/role o'qish va MapKit pinlarini tayyorlash — PARALLEL
    // (ketma-ket emas), bu ilova ochilishini tezlashtiradi.
    final results = await Future.wait([
      authRepo.getToken(),
      authRepo.getRole(),
      MapIconHelper.isPreloaded ? Future.value(null) : MapIconHelper.preloadAll(),
    ]);

    final token = results[0] as String?;
    final role = results[1] as String?;

    if (!mounted) return;

    if (token != null && role != null) {
      FcmService.init(ref);

      if (role == 'CLIENT') {
        context.go(AppRoutes.clientHome);
      } else if (role == 'DRIVER') {
        try {
          final status = await authRepo.getDriverStatus();
          final vs = status['verificationStatus'] as String?;
          if (vs == 'APPROVED') {
            context.go(AppRoutes.driverHome);
          } else {
            context.go(AppRoutes.pendingApproval);
          }
        } catch (_) {
          context.go(AppRoutes.driverHome);
        }
      } else {
        context.go(AppRoutes.onboarding);
      }
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final titleColor = isDark ? Colors.white : AppTheme.textPrimary;
    final taglineColor = isDark ? Colors.white.withOpacity(0.6) : AppTheme.textSecondary;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0f172a), Color(0xFF1e293b)]
                : const [Color(0xFFEFF6FF), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Transform.scale(
                  scale: _pulseScale.value,
                  child: child,
                ),
                child: ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.local_shipping, color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textFade,
                  child: Column(
                    children: [
                      Text(
                        'GoWay',
                        style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800,
                          color: titleColor, letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.get('app_tagline', locale),
                        style: TextStyle(fontSize: 14, color: taglineColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 60),
              _PulsingDots(controller: _pulseController, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uchta kichik nuqtali pulsatsiya indikatori — mavjud _pulseController'ga
/// ulanib, har bir nuqtani biroz farqli fazada (0.25 siljish bilan)
/// yorqinlashtirib-xiralashtiradi, natijada "to'lqinsimon" yuklanish
/// effekti hosil bo'ladi.
class _PulsingDots extends StatelessWidget {
  final Animation<double> controller;
  final bool isDark;
  const _PulsingDots({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white : AppTheme.primaryColor;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (controller.value + i * 0.25) % 1.0;
          final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}
