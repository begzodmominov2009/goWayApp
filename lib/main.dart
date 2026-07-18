import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'shared/widgets/app_loading_indicator.dart';
import 'shared/widgets/no_internet_overlay.dart';
import 'core/router/app_router.dart';
import 'core/localization/locale_provider.dart';
import 'core/utils/map_icon_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Xarita pinlarini ilova ishga tushishi bilan bir marta tayyorlab
  // qo'yamiz — Home ekranlari endi qayta chizmaydi, bu UI'ning
  // "qotib qolishi" muammosini bartaraf etadi. Xato bo'lsa ham ilova
  // ishlashda davom etadi (pinlar keyinroq, ekranning o'zida qayta
  // urinilib olinadi).
  MapIconHelper.preloadAll().catchError((_) {});

  runApp(const ProviderScope(child: GoWayApp()));
}

class GoWayApp extends ConsumerStatefulWidget {
  const GoWayApp({super.key});

  @override
  ConsumerState<GoWayApp> createState() => _GoWayAppState();
}

class _GoWayAppState extends ConsumerState<GoWayApp> {
  Locale? _prevLocale;
  ThemeMode? _prevTheme;
  bool _transitioning = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Til yoki tema o'zgarganda qisqa loading
    if ((_prevLocale != null && _prevLocale != locale) ||
        (_prevTheme != null && _prevTheme != themeMode)) {
      if (!_transitioning) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() => _transitioning = true);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _transitioning = false);
          });
        });
      }
    }
    _prevLocale = locale;
    _prevTheme = themeMode;

    return MaterialApp.router(
      title: 'GoWay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('uz'),
        Locale('ru'),
        Locale('en'),
      ],
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox(),
            if (_transitioning)
              AnimatedOpacity(
                opacity: _transitioning ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0f172a)
                      : Colors.white,
                  child: const Center(
                    child: AppLoadingIndicator(
                      color: AppTheme.primaryColor,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            const NoInternetOverlay(),
          ],
        );
      },
    );
  }
}