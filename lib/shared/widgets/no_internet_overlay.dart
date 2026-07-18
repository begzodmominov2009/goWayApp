import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/theme/app_theme.dart';

/// Butun ilova ustiga qo'yiladigan, internet aloqasi yo'qligida
/// ekranni to'liq qoplaydigan ogohlantirish. `MaterialApp.router`ning
/// `builder`i ichida, boshqa barcha kontent ustida joylashtiriladi.
class NoInternetOverlay extends ConsumerStatefulWidget {
  const NoInternetOverlay({super.key});

  @override
  ConsumerState<NoInternetOverlay> createState() => _NoInternetOverlayState();
}

class _NoInternetOverlayState extends ConsumerState<NoInternetOverlay> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _hasConnection = true;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => _hasConnection = !results.every((r) => r == ConnectivityResult.none));
    });
  }

  Future<void> _checkConnection() async {
    final results = await _connectivity.checkConnectivity();
    if (!mounted) return;
    setState(() => _hasConnection = !results.every((r) => r == ConnectivityResult.none));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasConnection) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final backgroundColor = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final titleColor = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final subtitleColor = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Positioned.fill(
      child: Material(
        color: backgroundColor,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.signal_wifi_off_rounded,
                    size: 72,
                    color: AppTheme.warningColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.get('no_internet_title', locale),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.get('no_internet_subtitle', locale),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _checkConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(AppStrings.get('retry_connection', locale)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
