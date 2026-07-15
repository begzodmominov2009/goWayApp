import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/client_repository.dart';
import '../../../../core/network/geocode_repository.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/place.dart';
import '../../../../shared/widgets/map_address_picker.dart';

/// Foydalanuvchining saqlangan manzillarini to'liq boshqarish sahifasi —
/// qo'shish, tahrirlash va o'chirish shu yerda amalga oshiriladi. Tezkor
/// kirish uchun qisqa ro'yxat select_address_screen.dart da ham ko'rsatiladi.
class SavedAddressesScreen extends ConsumerStatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  ConsumerState<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddress {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const _SavedAddress({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory _SavedAddress.fromMap(Map<String, dynamic> m) => _SavedAddress(
        id: m['id'].toString(),
        name: m['name'] as String? ?? '',
        address: m['address'] as String? ?? '',
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
      );
}

class _SavedAddressesScreenState extends ConsumerState<SavedAddressesScreen> {
  List<_SavedAddress> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(clientRepositoryProvider).getSavedAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = list.map(_SavedAddress.fromMap).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddressFormSheet(),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditForm(_SavedAddress item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddressFormSheet(existing: item),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(_SavedAddress item) async {
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('delete_address_confirm_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(AppStrings.get('delete_address_confirm_msg', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale),
                style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get('delete', locale),
                style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(clientRepositoryProvider).deleteSavedAddress(item.id);
      if (!mounted) return;
      setState(() => _addresses.removeWhere((a) => a.id == item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('address_deleted_snackbar', locale)), backgroundColor: AppTheme.successColor),
      );
    } catch (_) {}
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
        title: Text(AppStrings.get('saved_places', locale),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: AppLoadingIndicator())
          : _addresses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border, size: 56, color: textSecondary),
                      const SizedBox(height: 12),
                      Text(AppStrings.get('no_saved_addresses', locale), style: TextStyle(color: textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, i) {
                    final item = _addresses[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.bookmark, size: 18, color: AppTheme.primaryColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name.isNotEmpty ? item.name : item.address,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (item.address.isNotEmpty && item.address != item.name)
                                  Text(item.address,
                                      style: TextStyle(fontSize: 12, color: textSecondary),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: textSecondary),
                            color: surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (value) {
                              if (value == 'edit') _openEditForm(item);
                              if (value == 'delete') _confirmDelete(item);
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_outlined, size: 18, color: textPrimary),
                                  const SizedBox(width: 8),
                                  Text(AppStrings.get('edit', locale), style: TextStyle(color: textPrimary)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                                  const SizedBox(width: 8),
                                  Text(AppStrings.get('delete', locale), style: const TextStyle(color: AppTheme.errorColor)),
                                ]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(color: surface, border: Border(top: BorderSide(color: border))),
        child: GestureDetector(
          onTap: _openAddForm,
          child: Container(
            width: double.infinity, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                begin: Alignment.centerLeft, end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(AppStrings.get('add_new_address', locale),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Manzil qo'shish/tahrirlash formasi — nom (ixtiyoriy) + manzil qidiruv
/// (select_address_screen.dart dagi qidiruv logikasiga o'xshab) yoki mavjud
/// MapAddressPicker orqali xaritadan tanlash. `existing` berilsa — tahrirlash
/// rejimi, aks holda yangi manzil qo'shish rejimi.
class _AddressFormSheet extends ConsumerStatefulWidget {
  final _SavedAddress? existing;
  const _AddressFormSheet({this.existing});

  @override
  ConsumerState<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends ConsumerState<_AddressFormSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  final _addressFocus = FocusNode();
  Timer? _debounce;
  List<Place> _results = [];
  bool _searching = false;
  bool _saving = false;

  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _lat = e?.latitude;
    _lng = e?.longitude;
    _addressFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String val) {
    _debounce?.cancel();
    _lat = null;
    _lng = null;
    if (val.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final repo = ref.read(geocodeRepositoryProvider);
      final results = await repo.search(val, lat: _lat ?? 41.2995, lng: _lng ?? 69.2401);
      if (!mounted) return;
      setState(() {
        _results = results
            .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
            .toList();
        _searching = false;
      });
    });
  }

  void _selectResult(Place place) {
    _addressFocus.unfocus();
    setState(() {
      _addressCtrl.text = place.address.isNotEmpty ? place.address : place.name;
      _lat = place.lat;
      _lng = place.lng;
      _results = [];
    });
  }

  Future<void> _pickOnMap() async {
    final locale = ref.read(localeProvider).languageCode;
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapAddressPicker(
          initialLat: _lat ?? 41.2995,
          initialLng: _lng ?? 69.2401,
          title: AppStrings.get('choose_on_map', locale),
          isFrom: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _addressCtrl.text = result.address.isNotEmpty ? result.address : result.name;
      _lat = result.lat;
      _lng = result.lng;
      _results = [];
    });
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null || _addressCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final locale = ref.read(localeProvider).languageCode;
    final name = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : _addressCtrl.text.trim();
    try {
      final repo = ref.read(clientRepositoryProvider);
      if (widget.existing != null) {
        await repo.updateSavedAddress(
          widget.existing!.id,
          name: name,
          address: _addressCtrl.text.trim(),
          latitude: _lat!,
          longitude: _lng!,
        );
      } else {
        await repo.saveSavedAddress(
          name: name,
          address: _addressCtrl.text.trim(),
          latitude: _lat!,
          longitude: _lng!,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get(
              widget.existing != null ? 'address_updated_snackbar' : 'address_saved_snackbar', locale)),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
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
    final canSave = !_saving && _addressCtrl.text.trim().isNotEmpty && _lat != null && _lng != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(
              AppStrings.get(widget.existing != null ? 'edit_address' : 'add_address_title', locale),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(hintText: AppStrings.get('address_name_optional_hint', locale)),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _addressCtrl,
                    focusNode: _addressFocus,
                    onChanged: _onAddressChanged,
                    style: TextStyle(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: AppStrings.get('address_field_hint', locale),
                      hintStyle: TextStyle(color: textSecondary, fontSize: 12),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.map_outlined, color: AppTheme.primaryColor),
                  onPressed: _pickOnMap,
                ),
              ]),
            ),
            if (_addressFocus.hasFocus && (_results.isNotEmpty || _searching)) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: _searching
                    ? const Center(child: Padding(padding: EdgeInsets.all(12), child: AppLoadingIndicator(strokeWidth: 2)))
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        itemBuilder: (ctx, i) {
                          final place = _results[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.primaryColor),
                            title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600)),
                            subtitle: place.address.isNotEmpty && place.address != place.name
                                ? Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: textSecondary))
                                : null,
                            onTap: () => _selectResult(place),
                          );
                        },
                      ),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: canSave ? _save : null,
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  gradient: canSave
                      ? const LinearGradient(
                          colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                          begin: Alignment.centerLeft, end: Alignment.centerRight,
                        )
                      : null,
                  color: canSave ? null : Colors.grey.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(AppStrings.get('save', locale),
                          style: TextStyle(color: canSave ? Colors.white : Colors.grey, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
