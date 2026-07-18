import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/common/splash/screens/splash_screen.dart';
import '../../features/common/onboarding/screens/onboarding_screen.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/role_select_screen.dart';
import '../../features/auth/screens/driver_register_screen.dart';
import '../../features/auth/screens/pending_approval_screen.dart';
import '../../features/auth/screens/client_register_screen.dart';
import '../../features/client/home/screens/client_home_screen.dart';
import '../../features/client/order/screens/client_orders_screen.dart';
import '../../features/client/order/screens/order_detail_screen.dart';
import '../../features/client/order/screens/select_address_screen.dart';
import '../../features/client/order/screens/order_details_screen.dart';
import '../../features/client/order/screens/active_order_details_screen.dart';
import '../../features/client/order/screens/saved_addresses_screen.dart';
import '../../shared/widgets/place.dart';
import '../../features/client/profile/screens/client_profile_screen.dart';
import '../../features/client/settings/screens/client_settings_screen.dart';
import '../../features/driver/home/screens/driver_home_screen.dart';
import '../../features/driver/order/screens/driver_order_detail_screen.dart';
import '../../features/driver/order/screens/driver_history_screen.dart';
import '../../features/driver/order/screens/driver_order_history_full_screen.dart';
import '../../features/driver/wallet/screens/driver_wallet_screen.dart';
import '../../features/driver/wallet/screens/wallet_transaction_history_screen.dart';
import '../../features/driver/wallet/screens/topup_request_history_screen.dart';
import '../../features/driver/profile/screens/driver_profile_screen.dart';
import '../../features/driver/settings/screens/driver_settings_screen.dart';
import '../../shared/screens/chat_screen.dart';
import '../../shared/screens/terms_screen.dart';
import '../../shared/screens/notifications_screen.dart';
import '../../shared/screens/feedback_screen.dart';
import '../../shared/screens/faq_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const roleSelect = '/role-select';
  static const phone = '/phone';
  static const otp = '/otp';
  static const forgotPassword = '/forgot-password';
  static const driverRegister = '/driver-register';
  static const driverHistory = '/driver/history';
  static const driverOrderHistoryFull = '/driver/history/all';
  static const pendingApproval = '/pending-approval';

  static const clientOrders = '/client/orders';
  static const clientRegister = '/client-register';
  static const clientHome = '/client/home';
  static const clientOrderDetail = '/client/order/:id';
  static const clientProfile = '/client/profile';
  static const clientSettings = '/client/settings';
  static const clientSelectAddress = '/client/select-address';
  static const clientOrderDetails = '/client/order-details';
  static const clientActiveOrderDetails = '/client/active-order-details';
  static const clientSavedAddresses = '/client/saved-addresses';

  static const driverHome = '/driver/home';
  static const driverOrderDetail = '/driver/order/:id';
  static const driverWallet = '/driver/wallet';
  static const walletTransactionHistory = '/driver/wallet/transactions';
  static const topupRequestHistory = '/driver/wallet/topup-history';
  static const driverProfile = '/driver/profile';
  static const driverSettings = '/driver/settings';

  static const chat = '/chat/:orderId';
  static const terms = '/terms';
  static const notifications = '/notifications';
  static const feedback = '/feedback';
  static const faq = '/faq';
}

// Sahifalar orasida o'tishni kuzatish uchun — Home ekranidagi
// logo/manzil panelini boshqa sahifaga o'tilganda yashirish, qaytib
// kelganda qayta ko'rsatish uchun ishlatiladi.
final routeObserver = RouteObserver<PageRoute>();

// Instagram/iOS uslubidagi "o'ngdan chapga siljish" animatsiyasi —
// barcha GoRoute'larda builder o'rniga shu funksiya ishlatiladi.
// Orqaga qaytishda (pop) joriy ekran biroz orqaga suriladi (parallax).
CustomTransitionPage _slidePage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;

      final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      final offsetAnimation = animation.drive(tween);

      final secondaryTween = Tween(begin: Offset.zero, end: const Offset(-0.3, 0.0))
          .chain(CurveTween(curve: curve));
      final secondaryOffsetAnimation = secondaryAnimation.drive(secondaryTween);

      return SlideTransition(
        position: offsetAnimation,
        child: SlideTransition(
          position: secondaryOffsetAnimation,
          child: child,
        ),
      );
    },
  );
}

// Splash va Onboarding uchun — bular boshlang'ich ekranlar, fade
// (yumshoq paydo bo'lish) animatsiyasi ko'proq mos keladi
CustomTransitionPage _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => _fadePage(const SplashScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => _fadePage(const OnboardingScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.roleSelect,
        pageBuilder: (context, state) => _slidePage(const RoleSelectScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.phone,
        pageBuilder: (context, state) => _slidePage(
          PhoneScreen(role: state.extra as String? ?? 'CLIENT'),
          state,
        ),
      ),
      GoRoute(
        path: AppRoutes.otp,
        pageBuilder: (context, state) => _slidePage(
          OtpScreen(
            phone: (state.extra as Map)['phone'] as String,
            role: (state.extra as Map)['role'] as String,
          ),
          state,
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return _slidePage(
            ForgotPasswordScreen(
              initialPhone: extra['phone'] as String?,
              role: extra['role'] as String? ?? 'CLIENT',
            ),
            state,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.driverRegister,
        pageBuilder: (context, state) => _slidePage(const DriverRegisterScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.driverHistory,
        pageBuilder: (context, state) => _slidePage(const DriverHistoryScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.driverOrderHistoryFull,
        pageBuilder: (context, state) => _slidePage(const DriverOrderHistoryFullScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.pendingApproval,
        pageBuilder: (context, state) => _slidePage(const PendingApprovalScreen(), state),
      ),

      GoRoute(
        path: AppRoutes.clientRegister,
        pageBuilder: (context, state) => _slidePage(const ClientRegisterScreen(), state),
      ),

      // Client
      GoRoute(
        path: AppRoutes.clientHome,
        pageBuilder: (context, state) => _fadePage(const ClientHomeScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.clientOrders,
        pageBuilder: (context, state) => _slidePage(const ClientOrdersScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.clientOrderDetail,
        pageBuilder: (context, state) => _slidePage(
          ClientOrderDetailScreen(orderId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        path: AppRoutes.clientProfile,
        pageBuilder: (context, state) => _slidePage(const ClientProfileScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.clientSettings,
        pageBuilder: (context, state) => _slidePage(const ClientSettingsScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.clientSelectAddress,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return _slidePage(
            SelectAddressScreen(
              initialFrom: extra['initialFrom'] as Place?,
              fromLat: extra['fromLat'] as double,
              fromLng: extra['fromLng'] as double,
            ),
            state,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.clientOrderDetails,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return _slidePage(
            OrderDetailsScreen(
              fromPlace: extra['fromPlace'] as Place,
              toPlace: extra['toPlace'] as Place,
            ),
            state,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.clientActiveOrderDetails,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return _slidePage(
            ActiveOrderDetailsScreen(
              order: extra['order'] as Map<String, dynamic>,
              distKm: extra['distKm'] as double?,
              timeMin: extra['timeMin'] as int?,
            ),
            state,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.clientSavedAddresses,
        pageBuilder: (context, state) => _slidePage(const SavedAddressesScreen(), state),
      ),

      // Driver
      GoRoute(
        path: AppRoutes.driverHome,
        pageBuilder: (context, state) => _fadePage(const DriverHomeScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.driverOrderDetail,
        pageBuilder: (context, state) => _slidePage(
          DriverOrderDetailScreen(orderId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        path: AppRoutes.driverWallet,
        pageBuilder: (context, state) => _slidePage(const DriverWalletScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.walletTransactionHistory,
        pageBuilder: (context, state) => _slidePage(const WalletTransactionHistoryScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.topupRequestHistory,
        pageBuilder: (context, state) => _slidePage(const TopupRequestHistoryScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.driverProfile,
        pageBuilder: (context, state) => _slidePage(const DriverProfileScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.driverSettings,
        pageBuilder: (context, state) => _slidePage(const DriverSettingsScreen(), state),
      ),

      // Umumiy — Chat, Terms, Notifications
      GoRoute(
        path: AppRoutes.chat,
        pageBuilder: (context, state) => _slidePage(
          ChatScreen(
            orderId: state.pathParameters['orderId']!,
            otherPersonName: (state.extra as String?) ?? 'Suhbat',
          ),
          state,
        ),
      ),
      GoRoute(
        path: AppRoutes.terms,
        pageBuilder: (context, state) => _slidePage(const TermsScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        pageBuilder: (context, state) => _slidePage(const NotificationsScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.feedback,
        pageBuilder: (context, state) => _slidePage(const FeedbackScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.faq,
        pageBuilder: (context, state) => _slidePage(const FaqScreen(), state),
      ),
    ],
  );
});