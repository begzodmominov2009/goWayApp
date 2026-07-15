import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';

class DriverRegisterScreen extends ConsumerStatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  ConsumerState<DriverRegisterScreen> createState() =>
      _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends ConsumerState<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _plateController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;

  String? _selectedTruckType;
  List<Map<String, dynamic>> _trucks = [];
  bool _trucksLoading = true;

  // Fayl nomi (UI uchun null check)
  String? _passportUrl;
  String? _licenceFrontUrl;
  String? _licenceBackUrl;
  String? _techPassportUrl;

  // Bytes (web uchun)
  Uint8List? _passportBytes;
  Uint8List? _licenceFrontBytes;
  Uint8List? _licenceBackBytes;
  Uint8List? _techPassportBytes;

  // Fayl nomlari (multipart uchun)
  String? _passportName;
  String? _licenceFrontName;
  String? _licenceBackName;
  String? _techPassportName;

  @override
  void initState() {
    super.initState();
    _loadTrucks();
  }

  Future<void> _loadTrucks() async {
    try {
      final trucks = await ref.read(driverRepositoryProvider).getTrucks();
      setState(() {
        _trucks = trucks;
        _trucksLoading = false;
      });
    } catch (e) {
      setState(() => _trucksLoading = false);
    }
  }

  String _getBackendPlate() {
    return _plateController.text.toUpperCase().replaceAll(' ', '');
  }

  Future<void> _pickImage(String type) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) return;

    try {
      // Web da ham, telefonda ham ishlaydi
      final bytes = await image.readAsBytes();
      final name = image.name;

      setState(() {
        switch (type) {
          case 'passport':
            _passportBytes = bytes;
            _passportName = name;
            _passportUrl = name;
            break;
          case 'licence_front':
            _licenceFrontBytes = bytes;
            _licenceFrontName = name;
            _licenceFrontUrl = name;
            break;
          case 'licence_back':
            _licenceBackBytes = bytes;
            _licenceBackName = name;
            _licenceBackUrl = name;
            break;
          case 'tech_passport':
            _techPassportBytes = bytes;
            _techPassportName = name;
            _techPassportUrl = name;
            break;
        }
      });
    } catch (e) {
      setState(() => _error = 'Fayl yuklanmadi');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTruckType == null) {
      setState(() => _error = 'Mashina turini tanlang');
      return;
    }

    if (_passportBytes == null ||
        _licenceFrontBytes == null ||
        _licenceBackBytes == null ||
        _techPassportBytes == null) {
      setState(() => _error = 'Barcha hujjatlarni yuklang');
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Parol kamida 6 ta belgidan iborat bo\'lishi kerak');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Parollar mos kelmaydi');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final driverRepo = ref.read(driverRepositoryProvider);
      final selectedTruck = _trucks.firstWhere(
        (t) => t['type'] == _selectedTruckType,
        orElse: () => {'capacity': 1.5},
      );

      // 1. Profil yangilash
      await driverRepo.updateProfile(
        fullName: _fullNameController.text.trim(),
        truckType: _selectedTruckType!,
        plateNumber: _getBackendPlate(),
        capacity: (selectedTruck['capacity'] as num).toDouble(),
      );

      // 2. Hujjatlar yuborish
      await driverRepo.uploadDocuments(
        passportBytes: _passportBytes!,
        passportName: _passportName!,
        licenceFrontBytes: _licenceFrontBytes!,
        licenceFrontName: _licenceFrontName!,
        licenceBackBytes: _licenceBackBytes!,
        licenceBackName: _licenceBackName!,
        techPassportBytes: _techPassportBytes!,
        techPassportName: _techPassportName!,
      );

      // 3. Parol saqlash
      await driverRepo.setPassword(_passwordController.text);

      if (mounted) context.go(AppRoutes.pendingApproval);
    } catch (e) {
      setState(() => _error = 'Xatolik yuz berdi. Qayta urinib ko\'ring.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _plateController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.get('driver', locale),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Full name
            _Label(text: AppStrings.get('full_name', locale), isDark: isDark),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fullNameController,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
              ),
              decoration: _inputDecoration(
                hint: 'Begzod Mominov',
                isDark: isDark,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ismingizni kiriting' : null,
            ),
            const SizedBox(height: 20),

            // Truck type
            _Label(text: AppStrings.get('truck_type', locale), isDark: isDark),
            const SizedBox(height: 8),
            _trucksLoading
                ? const Center(child: AppLoadingIndicator())
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.borderColor,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTruckType,
                        hint: Text(
                          AppStrings.get('truck_type', locale),
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        isExpanded: true,
                        dropdownColor:
                            isDark ? AppTheme.darkSurface : Colors.white,
                        items: _trucks
                            .map((t) => DropdownMenuItem(
                                  value: t['type'] as String,
                                  child: Row(
                                    children: [
                                      const Text('🚛'),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${t['name']} (${t['capacity']}t)',
                                        style: TextStyle(
                                          color: isDark
                                              ? AppTheme.darkTextPrimary
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedTruckType = v),
                      ),
                    ),
                  ),
            const SizedBox(height: 20),

            // Plate number
            _Label(
                text: AppStrings.get('plate_number', locale), isDark: isDark),
            const SizedBox(height: 8),
            TextFormField(
              controller: _plateController,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  String clean =
                      newValue.text.toUpperCase().replaceAll(RegExp(r'\s+'), '');
                  if (clean.isEmpty) return newValue;

                  String result = '';
                  for (int i = 0; i < clean.length && i < 9; i++) {
                    if (i == 2 || i == 3 || i == 6) result += ' ';
                    result += clean[i];
                  }
                  return TextEditingValue(
                    text: result,
                    selection:
                        TextSelection.collapsed(offset: result.length),
                  );
                }),
              ],
              decoration: _inputDecoration(
                hint: '40 A 452 BS',
                isDark: isDark,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Davlat raqamini kiriting' : null,
            ),
            const SizedBox(height: 24),

            // Documents
            _Label(text: 'Hujjatlar', isDark: isDark),
            const SizedBox(height: 12),

            _DocumentPicker(
              label: AppStrings.get('passport', locale),
              emoji: '🪪',
              isUploaded: _passportUrl != null,
              onTap: () => _pickImage('passport'),
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _DocumentPicker(
              label: '${AppStrings.get('license', locale)} (old)',
              emoji: '🚗',
              isUploaded: _licenceFrontUrl != null,
              onTap: () => _pickImage('licence_front'),
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _DocumentPicker(
              label: '${AppStrings.get('license', locale)} (orqa)',
              emoji: '🚗',
              isUploaded: _licenceBackUrl != null,
              onTap: () => _pickImage('licence_back'),
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _DocumentPicker(
              label: AppStrings.get('tech_passport', locale),
              emoji: '📄',
              isUploaded: _techPassportUrl != null,
              onTap: () => _pickImage('tech_passport'),
              isDark: isDark,
            ),

            const SizedBox(height: 24),
            // Parol bo'limi
            _Label(text: 'Parol o\'rnating', isDark: isDark),
            const SizedBox(height: 4),
            Text(
              'Keyingi safar kirish uchun parol kerak bo\'ladi',
              style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
              decoration: _inputDecoration(hint: 'Kamida 6 ta belgi', isDark: isDark).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => v == null || v.length < 6 ? 'Kamida 6 ta belgi' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
              decoration: _inputDecoration(hint: 'Parolni takrorlang', isDark: isDark).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary, size: 20),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) => v != _passwordController.text ? 'Parollar mos kelmaydi' : null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.errorColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: AppLoadingIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(AppStrings.get('continue_btn', locale)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
      ),
      filled: true,
      fillColor: isDark ? AppTheme.darkSurface : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.borderColor,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.borderColor,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppTheme.primaryColor,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool isDark;
  const _Label({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
      ),
    );
  }
}

class _DocumentPicker extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isUploaded;
  final bool isDark;
  final VoidCallback onTap;

  const _DocumentPicker({
    required this.label,
    required this.emoji,
    required this.isUploaded,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUploaded
              ? AppTheme.successColor.withOpacity(0.05)
              : isDark
                  ? AppTheme.darkSurface
                  : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUploaded
                ? AppTheme.successColor.withOpacity(0.3)
                : isDark
                    ? AppTheme.darkBorder
                    : AppTheme.borderColor,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary,
                ),
              ),
            ),
            if (isUploaded)
              const Icon(Icons.check_circle,
                  color: AppTheme.successColor, size: 22)
            else
              Icon(
                Icons.upload_outlined,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}