import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/geo_repository.dart';
import '../../../../core/providers/driver_cache_providers.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

enum _ActiveFilter { all, activeOnly, inactiveOnly }

/// Viloyat tanlash — mustaqil sahifa (Navigator.push orqali ochiladi).
/// Natija: Navigator.pop(context, region) — faol viloyat tanlanganda,
/// aks holda null (orqaga qaytilganda).
class RegionPickerPage extends ConsumerStatefulWidget {
  final String title;
  const RegionPickerPage({super.key, required this.title});

  @override
  ConsumerState<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends ConsumerState<RegionPickerPage> {
  final _searchCtrl = TextEditingController();
  _ActiveFilter _filter = _ActiveFilter.all;

  @override
  void initState() {
    super.initState();
    ref.read(driverRegionsCacheProvider.notifier).refreshIfStale();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(GeoRegion region) {
    if (!region.isActive) {
      _showInactiveSheet();
      return;
    }
    Navigator.pop(context, region);
  }

  Future<void> _openFilterSheet() async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final result = await showModalBottomSheet<_ActiveFilter>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              _FilterOptionTile(
                label: AppStrings.get('filter_all', locale),
                selected: _filter == _ActiveFilter.all,
                onTap: () => Navigator.pop(ctx, _ActiveFilter.all),
              ),
              _FilterOptionTile(
                label: AppStrings.get('filter_active_only', locale),
                selected: _filter == _ActiveFilter.activeOnly,
                onTap: () => Navigator.pop(ctx, _ActiveFilter.activeOnly),
              ),
              _FilterOptionTile(
                label: AppStrings.get('filter_inactive_only', locale),
                selected: _filter == _ActiveFilter.inactiveOnly,
                onTap: () => Navigator.pop(ctx, _ActiveFilter.inactiveOnly),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _filter = result);
  }

  Future<void> _showInactiveSheet() async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              Text(AppStrings.get('route_inactive_title', locale), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 8),
              Text(AppStrings.get('route_inactive_message', locale), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: textSecondary)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity, height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(AppStrings.get('close', locale),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;

    final regionsAsync = ref.watch(driverRegionsCacheProvider);
    final loading = regionsAsync.isLoading && !regionsAsync.hasValue;
    final regions = [...regionsAsync.valueOrNull ?? const <GeoRegion>[]]
      ..sort((a, b) => a.name.compareTo(b.name));

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = regions.where((r) {
      if (_filter == _ActiveFilter.activeOnly && !r.isActive) return false;
      if (_filter == _ActiveFilter.inactiveOnly && r.isActive) return false;
      if (query.isNotEmpty && !r.name.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('region_search_hint', locale),
                          hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close, size: 16, color: textSecondary),
                                  onPressed: () => _searchCtrl.clear(),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.tune, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 8,
                      separatorBuilder: (_, __) => Divider(height: 1, color: border),
                      itemBuilder: (ctx, i) => _SkeletonRow(isDark: isDark),
                    )
                  : filtered.isEmpty
                      ? Center(child: Text(AppStrings.get('no_results_found', locale), style: TextStyle(color: textSecondary)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: border),
                          itemBuilder: (ctx, i) {
                            final region = filtered[i];
                            return _RegionTile(
                              name: region.name,
                              isActive: region.isActive,
                              isDark: isDark,
                              locale: locale,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              onTap: () => _select(region),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterOptionTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary)),
      trailing: selected ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
      onTap: onTap,
    );
  }
}

class _RegionTile extends StatelessWidget {
  final String name;
  final bool isActive;
  final bool isDark;
  final String locale;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _RegionTile({
    required this.name, required this.isActive, required this.isDark, required this.locale,
    required this.textPrimary, required this.textSecondary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isActive ? textPrimary : textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(AppStrings.get('route_inactive_badge', locale),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary)),
                )
              else
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ro'yxat qatori o'rnida ko'rinadigan miltillovchi skelet chiziq.
class _SkeletonRow extends StatelessWidget {
  final bool isDark;
  const _SkeletonRow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final highlight = isDark ? const Color(0xFF475569) : const Color(0xFFF1F5F9);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          width: 160, height: 14,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}
