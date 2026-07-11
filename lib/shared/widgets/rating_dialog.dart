import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Yulduzcha bilan baholash modali — buyurtma yakunlangач client va
/// driver tomonidan bir-birini baholash uchun umumiy widget.
class RatingDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<void> Function(int score, String? note) onSubmit;

  const RatingDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _score = 0;
  final _noteCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score == 0) return;
    setState(() => _loading = true);
    try {
      await widget.onSubmit(_score, _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return PopScope(
      canPop: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(widget.title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(widget.subtitle,
                style: TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _score = starIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starIndex <= _score ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 40,
                      color: starIndex <= _score ? Colors.amber : textSecondary.withOpacity(0.4),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Izoh qoldiring (ixtiyoriy)',
                hintStyle: TextStyle(color: textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: (_score == 0 || _loading) ? null : _submit,
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  gradient: (_score > 0 && !_loading)
                      ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
                      : null,
                  color: (_score > 0 && !_loading) ? null : Colors.grey.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text('Yuborish',
                          style: TextStyle(color: (_score > 0) ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}