import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/localization/app_strings.dart';
import 'hour_minute_picker.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

/// "Hozir / Bugun / Ertaga" buyurtma turini tanlash modali. Vaqt tanlash
/// (Bugun/Ertaga uchun) alohida modal sifatida emas, shu modalning ichki
/// ikkinchi bosqichi sifatida (AnimatedSwitcher bilan) ko'rsatiladi — hech
/// qanday ikkinchi showModalBottomSheet chaqirilmaydi.
///
/// Natija: {'isScheduled': false} — darhol qidirish, yoki
/// {'isScheduled': true, 'scheduledFor': DateTime} — rejalashtirilgan
/// buyurtma, yoki null — modal yopilgan (hech narsa tanlanmagan).
Future<Map<String, dynamic>?> showOrderTypeSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    sheetAnimationStyle: _kSheetAnimationStyle,
    builder: (ctx) => const _OrderTypeSheet(),
  );
}

class _OrderTypeSheet extends ConsumerStatefulWidget {
  const _OrderTypeSheet();

  @override
  ConsumerState<_OrderTypeSheet> createState() => _OrderTypeSheetState();
}

class _OrderTypeSheetState extends ConsumerState<_OrderTypeSheet> {
  int _stage = 1; // 1 = tur tanlash, 2 = vaqt tanlash
  bool _isTomorrow = false;
  late int _hour;
  late int _minute;
  final ScrollController _hourScrollCtrl = ScrollController();

  @override
  void dispose() {
    _hourScrollCtrl.dispose();
    super.dispose();
  }

  void _goToTimeStage(bool isTomorrow) {
    final now = TimeOfDay.now();
    setState(() {
      _isTomorrow = isTomorrow;
      _hour = (now.hour + 1) % 24;
      _minute = 0;
      _stage = 2;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hourScrollCtrl.hasClients) return;
      final target = (_hour * 52.0 - 100).clamp(0.0, _hourScrollCtrl.position.maxScrollExtent);
      _hourScrollCtrl.jumpTo(target);
    });
  }

  void _backToStage1() => setState(() => _stage = 1);

  void _confirmTime() {
    final locale = ref.read(localeProvider).languageCode;
    final now = DateTime.now();
    final baseDate = _isTomorrow ? now.add(const Duration(days: 1)) : now;
    final scheduledFor = DateTime(baseDate.year, baseDate.month, baseDate.day, _hour, _minute);
    final minAllowed = now.add(const Duration(hours: 1));

    if (scheduledFor.isBefore(minAllowed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('order_type_min_time_error', locale)),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }
    Navigator.pop(context, {'isScheduled': true, 'scheduledFor': scheduledFor});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final offsetAnim = Tween<Offset>(
              begin: Offset(_stage == 2 ? 1 : -1, 0),
              end: Offset.zero,
            ).animate(animation);
            return SlideTransition(position: offsetAnim, child: child);
          },
          child: _stage == 1
              ? _buildStage1(locale: locale, isDark: isDark, textPrimary: textPrimary, border: border)
              : _buildStage2(locale: locale, textPrimary: textPrimary, border: border, bg: bg),
        ),
      ),
    );
  }

  Widget _buildStage1({
    required String locale,
    required bool isDark,
    required Color textPrimary,
    required Color border,
  }) {
    return Column(
      key: const ValueKey('order_type_stage1'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 18),
        Text(
          AppStrings.get('order_type_sheet_title', locale),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
        ),
        const SizedBox(height: 16),
        _OrderTypeCard(
          icon: Icons.flash_on_rounded,
          title: AppStrings.get('order_type_now', locale),
          subtitle: AppStrings.get('order_type_now_desc', locale),
          isDark: isDark,
          onTap: () => Navigator.pop(context, {'isScheduled': false}),
        ),
        const SizedBox(height: 10),
        _OrderTypeCard(
          icon: Icons.today_rounded,
          title: AppStrings.get('order_type_today', locale),
          subtitle: AppStrings.get('order_type_select_time', locale),
          isDark: isDark,
          onTap: () => _goToTimeStage(false),
        ),
        const SizedBox(height: 10),
        _OrderTypeCard(
          icon: Icons.event_rounded,
          title: AppStrings.get('order_type_tomorrow', locale),
          subtitle: AppStrings.get('order_type_select_time', locale),
          isDark: isDark,
          onTap: () => _goToTimeStage(true),
        ),
      ],
    );
  }

  Widget _buildStage2({
    required String locale,
    required Color textPrimary,
    required Color border,
    required Color bg,
  }) {
    final questionKey = _isTomorrow ? 'order_type_pick_time_tomorrow' : 'order_type_pick_time_today';

    return Column(
      key: const ValueKey('order_type_stage2'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _backToStage1,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.arrow_back_ios, size: 16, color: textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.get(questionKey, locale),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 44,
          child: ListView.separated(
            controller: _hourScrollCtrl,
            scrollDirection: Axis.horizontal,
            itemCount: 24,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) => _Chip(
              label: i.toString().padLeft(2, '0'),
              width: 44,
              selected: i == _hour,
              bg: bg, textPrimary: textPrimary,
              onTap: () => setState(() => _hour = i),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: kAllowedMinutes.map((m) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _Chip(
                  label: m.toString().padLeft(2, '0'),
                  selected: m == _minute,
                  bg: bg, textPrimary: textPrimary,
                  onTap: () => setState(() => _minute = m),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _confirmTime,
          child: Container(
            width: double.infinity, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                begin: Alignment.centerLeft, end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                AppStrings.get('confirm', locale),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _OrderTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final double? width;
  final bool selected;
  final Color bg;
  final Color textPrimary;
  final VoidCallback onTap;

  const _Chip({
    required this.label, this.width, required this.selected,
    required this.bg, required this.textPrimary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : bg,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : textPrimary),
        ),
      ),
    );
  }
}
