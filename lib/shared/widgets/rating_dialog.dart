import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/localization/app_strings.dart';
import 'app_loading_indicator.dart';

/// Yulduzcha bilan baholash modali — buyurtma yakunlangач client va
/// driver tomonidan bir-birini baholash uchun umumiy widget.
///
/// `subtitle` — baholanayotgan shaxsning ismi (avatar ostida ko'rsatiladi).
/// `title` — chaqiruvchi tomonidan uzatiladi, lekin yangi dizaynda tepadagi
/// sarlavha endi doim umumiy (AppStrings) savol matni bo'lgani uchun
/// vizual ravishda ishlatilmaydi (API mosligini saqlash uchun saqlab
/// qolingan).
class RatingDialog extends ConsumerStatefulWidget {
  final String title;
  final String subtitle;
  final Future<void> Function(int score, String? note) onSubmit;
  final String? avatarUrl;
  final String? vehicleInfo;
  final bool isVerified;

  const RatingDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    this.avatarUrl,
    this.vehicleInfo,
    this.isVerified = false,
  });

  @override
  ConsumerState<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends ConsumerState<RatingDialog> {
  int _score = 0;
  final _noteCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score == 0) return;
    final locale = ref.read(localeProvider).languageCode;
    setState(() { _loading = true; _error = null; });
    final note = _noteCtrl.text.trim();
    final tags = _selectedTags.join(', ');
    final combined = [note, tags].where((s) => s.isNotEmpty).join(note.isNotEmpty && tags.isNotEmpty ? ', ' : '');
    try {
      await widget.onSubmit(_score, combined.isEmpty ? null : combined);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '${AppStrings.get('rating_submit_error', locale)}: $e';
        });
      }
    }
  }

  void _skip() {
    if (_loading) return;
    Navigator.pop(context, true);
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final fieldBg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);

    final tags = [
      AppStrings.get('rating_tag_on_time', locale),
      AppStrings.get('rating_tag_friendly', locale),
      AppStrings.get('rating_tag_recommend', locale),
    ];

    return PopScope(
      canPop: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Text(AppStrings.get('rating_dialog_title', locale),
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: textPrimary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(AppStrings.get('rating_dialog_subtitle', locale),
                    style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
                    textAlign: TextAlign.center),
                const SizedBox(height: 22),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 88, height: 88,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.35), width: 1.5),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                        ),
                        child: (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                            ? ClipOval(
                                child: Image.network(
                                  widget.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _AvatarInitial(name: widget.subtitle),
                                ),
                              )
                            : _AvatarInitial(name: widget.subtitle),
                      ),
                    ),
                    if (widget.isVerified)
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: surface, width: 2.5),
                          ),
                          child: const Icon(Icons.verified_rounded, size: 13, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.subtitle.isNotEmpty)
                  Text(widget.subtitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                if (widget.vehicleInfo != null && widget.vehicleInfo!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_shipping_outlined, size: 13, color: textSecondary),
                    const SizedBox(width: 4),
                    Text(widget.vehicleInfo!, style: TextStyle(fontSize: 12, color: textSecondary)),
                  ]),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final starIndex = i + 1;
                    final filled = starIndex <= _score;
                    return GestureDetector(
                      onTap: () => setState(() => _score = starIndex),
                      child: AnimatedScale(
                        scale: filled ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.elasticOut,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            filled ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 46,
                            color: filled ? Colors.amber : textSecondary.withOpacity(0.35),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(16)),
                  child: TextField(
                    controller: _noteCtrl,
                    minLines: 3,
                    maxLines: 5,
                    style: TextStyle(fontSize: 14, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: AppStrings.get('review_placeholder', locale),
                      hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8, runSpacing: 8,
                        children: tags.map((tag) {
                          final selected = _selectedTags.contains(tag);
                          return GestureDetector(
                            onTap: () => _toggleTag(tag),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.primaryColor : fieldBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: selected ? AppTheme.primaryColor : border),
                              ),
                              child: Text(tag,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : textPrimary)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(AppStrings.get('optional_label', locale), style: TextStyle(fontSize: 12, color: textSecondary)),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: (_score == 0 || _loading) ? null : _submit,
                  child: Container(
                    width: double.infinity, height: 52,
                    decoration: BoxDecoration(
                      gradient: (_score > 0 && !_loading)
                          ? const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)])
                          : null,
                      color: (_score > 0 && !_loading) ? null : Colors.grey.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: _loading
                          ? const SizedBox(width: 22, height: 22, child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(AppStrings.get('submit_review', locale),
                              style: TextStyle(color: (_score > 0) ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _skip,
                    child: Text(AppStrings.get('skip_for_now', locale),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  final String name;
  const _AvatarInitial({required this.name});
  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
    );
  }
}