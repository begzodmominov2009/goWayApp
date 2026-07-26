import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_loading_indicator.dart';
import '../../shared/widgets/tutorial_sheet.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/localization/app_strings.dart';
import '../../core/network/feedback_repository.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _messageCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _maybeShowFeedbackTutorial();
  }

  Future<void> _maybeShowFeedbackTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seen_feedback_tutorial') == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showFeedbackTutorial();
    });
    await prefs.setBool('seen_feedback_tutorial', true);
  }

  void _showFeedbackTutorial() {
    final locale = ref.read(localeProvider).languageCode;
    showTutorialSheet(
      context,
      title: AppStrings.get('tutorial_feedback_title', locale),
      bullets: [
        AppStrings.get('tutorial_feedback_1', locale),
        AppStrings.get('tutorial_feedback_2', locale),
        AppStrings.get('tutorial_feedback_3', locale),
      ],
      icon: Icons.feedback_outlined,
      locale: locale,
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = img.name;
    });
  }

  Future<void> _submit() async {
    final locale = ref.read(localeProvider).languageCode;
    if (_messageCtrl.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(feedbackRepositoryProvider).sendFeedback(
            message: _messageCtrl.text.trim(),
            imageBytes: _imageBytes,
            imageName: _imageName,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('feedback_success', locale)),
          backgroundColor: AppTheme.successColor,
        ),
      );
      context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('generic_error', locale)),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

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
          AppStrings.get('feedback', locale),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: textSecondary, size: 20),
            onPressed: _showFeedbackTutorial,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.get('feedback_intro', locale),
              style: TextStyle(fontSize: 13, color: textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _messageCtrl,
                minLines: 6,
                maxLines: 10,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintText: AppStrings.get('feedback_placeholder', locale),
                  hintStyle: TextStyle(color: textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_imageBytes == null)
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.get('add_image', locale),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                ),
              )
            else
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_imageBytes!, width: 96, height: 96, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -8,
                    top: -8,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _imageBytes = null;
                        _imageName = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 28),
            _GradientButton(
              label: AppStrings.get('send', locale),
              loading: _sending,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _GradientButton({required this.label, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (loading || onTap == null) ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
        ),
      ),
    );
  }
}
