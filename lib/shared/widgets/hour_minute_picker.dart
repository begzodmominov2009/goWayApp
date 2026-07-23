import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/localization/app_strings.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

const List<int> kAllowedMinutes = [0, 15, 30, 45];

int nearestAllowedMinute(int minute) {
  var closest = kAllowedMinutes.first;
  var diff = 60;
  for (final m in kAllowedMinutes) {
    final d = (m - minute).abs();
    if (d < diff) {
      diff = d;
      closest = m;
    }
  }
  return closest;
}

/// Soat/daqiqa tanlash uchun umumiy pastdan chiquvchi modal. Daqiqa faqat
/// 00/15/30/45 qadamlarda tanlanadi.
Future<TimeOfDay?> showHourMinutePicker(BuildContext context, {TimeOfDay? initial}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    sheetAnimationStyle: _kSheetAnimationStyle,
    builder: (ctx) => _HourMinutePickerSheet(initial: initial),
  );
}

class _HourMinutePickerSheet extends ConsumerStatefulWidget {
  final TimeOfDay? initial;
  const _HourMinutePickerSheet({this.initial});

  @override
  ConsumerState<_HourMinutePickerSheet> createState() => _HourMinutePickerSheetState();
}

class _HourMinutePickerSheetState extends ConsumerState<_HourMinutePickerSheet> {
  late int _hour;
  late int _minute;
  final ScrollController _hourScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    final base = widget.initial ?? TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    _hour = base.hour;
    _minute = nearestAllowedMinute(base.minute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hourScrollCtrl.hasClients) return;
      final target = (_hour * 52.0 - 100).clamp(0.0, _hourScrollCtrl.position.maxScrollExtent);
      _hourScrollCtrl.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _hourScrollCtrl.dispose();
    super.dispose();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(
              '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
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
              onTap: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
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
