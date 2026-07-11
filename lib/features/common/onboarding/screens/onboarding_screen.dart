import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _langSelected = false;

  final List<Map<String, dynamic>> _languages = [
    {
      'code': 'uz',
      'name': 'O\'zbek tili',
      'flag': '🇺🇿',
      'native': 'Tilni tanlang',
    },
    {
      'code': 'ru',
      'name': 'Русский язык',
      'flag': '🇷🇺',
      'native': 'Выберите язык',
    },
    {
      'code': 'en',
      'name': 'English',
      'flag': '🇬🇧',
      'native': 'Choose language',
    },
  ];

  List<Map<String, dynamic>> _getPages(String locale) => [
        {
          'icon': FontAwesomeIcons.truckMoving,
          'color': const Color(0xFF2563EB),
          'bg': const Color(0xFFEFF6FF),
          'darkBg': const Color(0xFF1E3A5F),
          'title': AppStrings.get('onboarding1_title', locale),
          'subtitle': AppStrings.get('onboarding1_subtitle', locale),
        },
        {
          'icon': FontAwesomeIcons.locationDot,
          'color': const Color(0xFF059669),
          'bg': const Color(0xFFECFDF5),
          'darkBg': const Color(0xFF064E3B),
          'title': AppStrings.get('onboarding2_title', locale),
          'subtitle': AppStrings.get('onboarding2_subtitle', locale),
        },
      ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final pages = _getPages(locale);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_langSelected) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: FaIcon(
                      FontAwesomeIcons.earthAsia,
                      color: AppTheme.primaryColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _languages
                      .map((lang) => Text(
                            lang['native'] as String,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.textPrimary,
                              height: 1.5,
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 40),
                ..._languages.map((lang) => GestureDetector(
                      onTap: () async {
                        await ref
                            .read(localeProvider.notifier)
                            .setLocale(lang['code'] as String);
                        setState(() => _langSelected = true);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkSurface
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : AppTheme.borderColor,
                          ),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isDark
                                    ? AppTheme.darkBackground
                                    : AppTheme.backgroundColor,
                              ),
                              child: Center(
                                child: Text(
                                  lang['flag'] as String,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang['native'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  lang['name'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: FaIcon(
                                  FontAwesomeIcons.chevronRight,
                                  size: 12,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.roleSelect),
                  child: Text(
                    AppStrings.get('skip', locale),
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  final color = page['color'] as Color;
                  final bg = isDark
                      ? page['darkBg'] as Color
                      : page['bg'] as Color;
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Center(
                            child: FaIcon(
                              page['icon'] as IconData,
                              size: 64,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page['title'] as String,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page['subtitle'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? AppTheme.primaryColor
                              : isDark
                                  ? AppTheme.darkBorder
                                  : AppTheme.borderColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage < pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        context.go(AppRoutes.roleSelect);
                      }
                    },
                    child: Text(
                      _currentPage < pages.length - 1
                          ? AppStrings.get('next', locale)
                          : AppStrings.get('start', locale),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}