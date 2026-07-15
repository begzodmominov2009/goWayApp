import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_repository.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/utils/map_icon_helper.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);
    _ctrl.forward();
    _checkAuth();
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
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
              const SizedBox(height: 20),
              const Text(
                'GoWay',
                style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Yuk tashish platformasi',
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 60),
              const AppLoadingIndicator(
                color: Color(0xFF3b82f6), strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}