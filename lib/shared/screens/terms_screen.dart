import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_loading_indicator.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/network/terms_repository.dart';

/// Oferta shartlari — joriy tilga mos ravishda backend'dan yuklanadi.
class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key});

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  Map<String, dynamic>? _terms;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final terms = await ref.read(termsRepositoryProvider).getActiveTerms();
      setState(() { _terms = terms; _loading = false; });
    } catch (_) {
      setState(() { _loading = false; _error = 'Shartlar topilmadi'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          locale == 'ru' ? 'Условия оферты' : locale == 'en' ? 'Terms of Service' : 'Oferta shartlari',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: AppLoadingIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined, size: 48, color: textSecondary),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: textSecondary)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('Qayta urinish')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_terms?['version'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Versiya: ${_terms!['version']}',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ),
                      Text(
                        _terms?['content'] as String? ?? '',
                        style: TextStyle(fontSize: 14, color: textPrimary, height: 1.6),
                      ),
                    ],
                  ),
                ),
    );
  }
}