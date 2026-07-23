import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/geo_repository.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';

/// Haydovchi xizmat ko'rsatadigan yo'nalishni (liniyani) belgilash sahifasi.
/// Yuqorida joriy liniya ko'rsatiladi (bekor qilish imkoni bilan), pastda
/// "Qayerdan" -> "Qayerga" ikki bosqichli viloyat/tuman tanlash (xaritasiz)
/// va davomiylik tanlab tasdiqlash bo'limi joylashgan.
class DriverLineScreen extends ConsumerStatefulWidget {
  const DriverLineScreen({super.key});

  @override
  ConsumerState<DriverLineScreen> createState() => _DriverLineScreenState();
}

class _DriverLineScreenState extends ConsumerState<DriverLineScreen> {
  bool _loadingCurrent = true;
  Map<String, dynamic>? _currentLine;
  String _fromLabel = '';
  String _toLabel = '';
  bool _clearing = false;

  List<GeoRegion> _regions = [];
  bool _loadingRegions = true;

  int _phase = 1; // 1 = Qayerdan, 2 = Qayerga
  bool _pickingDistrict = false;
  GeoRegion? _activeRegion;
  List<GeoDistrict> _activeDistricts = [];
  bool _loadingDistricts = false;

  GeoRegion? _fromRegion;
  GeoDistrict? _fromDistrict;
  GeoRegion? _toRegion;
  GeoDistrict? _toDistrict;

  int _durationHours = 12;
  bool _submitting = false;

  bool get _selectionComplete => _fromRegion != null && _toRegion != null;

  @override
  void initState() {
    super.initState();
    _loadRegions();
    _loadCurrentLine();
  }

  Future<void> _loadRegions() async {
    final list = await ref.read(geoRepositoryProvider).getAllRegions();
    if (!mounted) return;
    setState(() {
      _regions = list;
      _loadingRegions = false;
    });
  }

  Future<void> _loadCurrentLine() async {
    setState(() => _loadingCurrent = true);
    try {
      final line = await ref.read(driverRepositoryProvider).getDriverLine();
      if (!mounted) return;
      setState(() {
        _currentLine = line;
        _fromLabel = '';
        _toLabel = '';
        _loadingCurrent = false;
      });
      if (line != null) _resolveCurrentLineLabels(line);
    } catch (_) {
      if (mounted) setState(() { _currentLine = null; _loadingCurrent = false; });
    }
  }

  GeoRegion? _findRegion(List<GeoRegion> list, String? id) {
    if (id == null) return null;
    for (final r in list) {
      if (r.id == id) return r;
    }
    return null;
  }

  GeoDistrict? _findDistrict(List<GeoDistrict> list, String? id) {
    if (id == null) return null;
    for (final d in list) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _resolveCurrentLineLabels(Map<String, dynamic> line) async {
    final repo = ref.read(geoRepositoryProvider);
    final regions = _regions.isNotEmpty ? _regions : await repo.getAllRegions();

    final fromRegionId = line['fromRegionId'] as String?;
    final fromDistrictId = line['fromDistrictId'] as String?;
    final toRegionId = line['toRegionId'] as String?;
    final toDistrictId = line['toDistrictId'] as String?;

    final fromRegion = _findRegion(regions, fromRegionId);
    final toRegion = _findRegion(regions, toRegionId);

    String fromLabel = fromRegion?.name ?? '';
    String toLabel = toRegion?.name ?? '';

    if (fromRegionId != null && fromDistrictId != null) {
      final districts = await repo.getAllDistricts(fromRegionId);
      final d = _findDistrict(districts, fromDistrictId);
      if (d != null) fromLabel = '$fromLabel, ${d.name}';
    }
    if (toRegionId != null && toDistrictId != null) {
      final districts = await repo.getAllDistricts(toRegionId);
      final d = _findDistrict(districts, toDistrictId);
      if (d != null) toLabel = '$toLabel, ${d.name}';
    }

    if (!mounted) return;
    setState(() { _fromLabel = fromLabel; _toLabel = toLabel; });
  }

  Future<void> _clearLine() async {
    setState(() => _clearing = true);
    try {
      await ref.read(driverRepositoryProvider).clearDriverLine();
      if (!mounted) return;
      setState(() {
        _currentLine = null;
        _fromLabel = '';
        _toLabel = '';
        _clearing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _selectRegion(GeoRegion region) async {
    if (!region.isActive) {
      _showInactiveDialog();
      return;
    }
    setState(() {
      _activeRegion = region;
      _pickingDistrict = true;
      _loadingDistricts = true;
      _activeDistricts = [];
    });
    final list = await ref.read(geoRepositoryProvider).getAllDistricts(region.id);
    if (!mounted) return;
    setState(() {
      _activeDistricts = list;
      _loadingDistricts = false;
    });
  }

  void _selectDistrict(GeoDistrict district) {
    if (!district.isActive) {
      _showInactiveDialog();
      return;
    }
    setState(() {
      if (_phase == 1) {
        _fromRegion = _activeRegion;
        _fromDistrict = district;
        _phase = 2;
      } else {
        _toRegion = _activeRegion;
        _toDistrict = district;
      }
      _pickingDistrict = false;
      _activeRegion = null;
      _activeDistricts = [];
    });
  }

  void _backInStepper() {
    setState(() {
      if (_pickingDistrict) {
        _pickingDistrict = false;
        _activeRegion = null;
        _activeDistricts = [];
      } else if (_phase == 2) {
        _phase = 1;
        _fromRegion = null;
        _fromDistrict = null;
      }
    });
  }

  void _resetStepper() {
    setState(() {
      _phase = 1;
      _pickingDistrict = false;
      _activeRegion = null;
      _activeDistricts = [];
      _fromRegion = null;
      _fromDistrict = null;
      _toRegion = null;
      _toDistrict = null;
      _durationHours = 12;
    });
  }

  Future<void> _submitLine() async {
    if (!_selectionComplete || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(driverRepositoryProvider).setDriverLine(
        fromRegionId: _fromRegion!.id,
        fromDistrictId: _fromDistrict?.id,
        toRegionId: _toRegion!.id,
        toDistrictId: _toDistrict?.id,
        durationHours: _durationHours,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _resetStepper();
      _loadCurrentLine();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e is DriverLineException && e.reasonKey == 'bad_request') {
        _showInactiveDialog();
      } else {
        _showErrorSnack(e is DriverLineException ? e : null);
      }
    }
  }

  void _showErrorSnack(DriverLineException? e) {
    final locale = ref.read(localeProvider).languageCode;
    String msg;
    switch (e?.reasonKey) {
      case 'timeout':
        msg = AppStrings.get('error_timeout', locale);
        break;
      case 'no_connection':
        msg = AppStrings.get('error_no_connection', locale);
        break;
      case 'server_error':
        msg = AppStrings.get('error_server', locale);
        break;
      default:
        msg = AppStrings.get('generic_error', locale);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
    );
  }

  Future<void> _showInactiveDialog() async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.get('route_inactive_title', locale),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 16,
          ),
        ),
        content: Text(
          AppStrings.get('route_inactive_message', locale),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppStrings.get('close', locale),
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
                  Text(
                    AppStrings.get('my_line', locale),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCurrentLineCard(locale, isDark, textPrimary, textSecondary, border),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppStrings.get('set_new_line_title', locale),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _selectionComplete
                    ? SingleChildScrollView(
                        child: _buildCompleteSection(locale, isDark, textPrimary, textSecondary, border, bg),
                      )
                    : _buildStepperSection(locale, isDark, textPrimary, textSecondary, border, bg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentLineCard(String locale, bool isDark, Color textPrimary, Color textSecondary, Color border) {
    if (_loadingCurrent) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: const Center(child: AppLoadingIndicator(strokeWidth: 2)),
      );
    }

    if (_currentLine == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.get('no_active_line', locale),
                style: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final fromText = _fromLabel.isNotEmpty ? _fromLabel : AppStrings.get('resolving_label', locale);
    final toText = _toLabel.isNotEmpty ? _toLabel : AppStrings.get('resolving_label', locale);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.get('active_line_label', locale),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            '$fromText  ↔  $toText',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _clearing ? null : _clearLine,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: AppTheme.errorColor),
                foregroundColor: AppTheme.errorColor,
              ),
              child: _clearing
                  ? const SizedBox(width: 18, height: 18, child: AppLoadingIndicator(strokeWidth: 2, color: AppTheme.errorColor))
                  : Text(AppStrings.get('cancel_line', locale), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperSection(String locale, bool isDark, Color textPrimary, Color textSecondary, Color border, Color bg) {
    final showBack = _pickingDistrict || _phase == 2;
    final stepNum = _phase == 1 ? '1/2' : '2/2';
    final stepLabel = _phase == 1
        ? AppStrings.get('select_from_region', locale)
        : AppStrings.get('select_to_region', locale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showBack)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _backInStepper,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.arrow_back_ios, size: 16, color: textPrimary),
                ),
              ),
            if (showBack) const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                stepNum,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primaryColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _pickingDistrict ? (_activeRegion?.name ?? '') : stepLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              final offsetAnim = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(animation);
              return SlideTransition(position: offsetAnim, child: child);
            },
            child: _pickingDistrict
                ? _buildDistrictList(
                    key: ValueKey('districts_$_phase'),
                    locale: locale, isDark: isDark,
                    textPrimary: textPrimary, textSecondary: textSecondary, border: border,
                  )
                : _buildRegionList(
                    key: ValueKey('regions_$_phase'),
                    locale: locale, isDark: isDark,
                    textPrimary: textPrimary, textSecondary: textSecondary, border: border,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegionList({
    required Key key,
    required String locale,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
  }) {
    if (_loadingRegions) {
      return Center(key: key, child: const AppLoadingIndicator());
    }
    if (_regions.isEmpty) {
      return Center(
        key: key,
        child: Text(AppStrings.get('no_results_found', locale), style: TextStyle(color: textSecondary)),
      );
    }
    return ListView.separated(
      key: key,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _regions.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: border),
      itemBuilder: (ctx, i) {
        final region = _regions[i];
        return _GeoListTile(
          name: region.name,
          isActive: region.isActive,
          isDark: isDark,
          locale: locale,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          onTap: () => _selectRegion(region),
        );
      },
    );
  }

  Widget _buildDistrictList({
    required Key key,
    required String locale,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
  }) {
    if (_loadingDistricts) {
      return Center(key: key, child: const AppLoadingIndicator());
    }
    if (_activeDistricts.isEmpty) {
      return Center(
        key: key,
        child: Text(AppStrings.get('no_results_found', locale), style: TextStyle(color: textSecondary)),
      );
    }
    return ListView.separated(
      key: key,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _activeDistricts.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: border),
      itemBuilder: (ctx, i) {
        final district = _activeDistricts[i];
        return _GeoListTile(
          name: district.name,
          isActive: district.isActive,
          isDark: isDark,
          locale: locale,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          onTap: () => _selectDistrict(district),
        );
      },
    );
  }

  Widget _buildCompleteSection(String locale, bool isDark, Color textPrimary, Color textSecondary, Color border, Color bg) {
    final fromText = '${_fromRegion!.name}${_fromDistrict != null ? ', ${_fromDistrict!.name}' : ''}';
    final toText = '${_toRegion!.name}${_toDistrict != null ? ', ${_toDistrict!.name}' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryRow(icon: Icons.trip_origin, text: fromText, textPrimary: textPrimary),
                  const SizedBox(height: 6),
                  _SummaryRow(icon: Icons.flag, text: toText, textPrimary: textPrimary),
                ],
              ),
            ),
            TextButton(
              onPressed: _resetStepper,
              child: Text(AppStrings.get('cancel_selection', locale), style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          AppStrings.get('line_duration', locale),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _DurationChip(label: AppStrings.get('hours_6', locale), selected: _durationHours == 6, isDark: isDark, onTap: () => setState(() => _durationHours = 6)),
            const SizedBox(width: 8),
            _DurationChip(label: AppStrings.get('hours_12', locale), selected: _durationHours == 12, isDark: isDark, onTap: () => setState(() => _durationHours = 12)),
            const SizedBox(width: 8),
            _DurationChip(label: AppStrings.get('hours_24', locale), selected: _durationHours == 24, isDark: isDark, onTap: () => setState(() => _durationHours = 24)),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _submitting ? null : _submitLine,
          child: Container(
            width: double.infinity, height: 50,
            decoration: BoxDecoration(
              gradient: _submitting ? null : const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              color: _submitting ? Colors.grey.withOpacity(0.25) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text(AppStrings.get('confirm_line', locale), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color textPrimary;
  const _SummaryRow({required this.icon, required this.text, required this.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
        ),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _DurationChip({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppTheme.primaryColor : border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _GeoListTile extends StatelessWidget {
  final String name;
  final bool isActive;
  final String locale;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _GeoListTile({
    required this.name,
    required this.isActive,
    required this.locale,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isActive ? textPrimary : textSecondary,
                  ),
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
                  child: Text(
                    AppStrings.get('route_inactive_badge', locale),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary),
                  ),
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
