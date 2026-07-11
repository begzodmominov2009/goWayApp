import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/geocode_repository.dart';
import '../widgets/place.dart';
import 'map_address_picker.dart';

class AddressModal extends ConsumerStatefulWidget {
  final bool isDark;
  final Place? initialFrom;
  final double fromLat;
  final double fromLng;
  final void Function(Place? from, Place? to) onConfirmed;

  const AddressModal({
    super.key,
    required this.isDark,
    required this.initialFrom,
    required this.fromLat,
    required this.fromLng,
    required this.onConfirmed,
  });

  @override
  ConsumerState<AddressModal> createState() => _AddressModalState();
}

class _AddressModalState extends ConsumerState<AddressModal> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  Place? _fromPlace;
  Place? _toPlace;

  List<Place> _fromResults = [];
  List<Place> _toResults = [];
  bool _fromSearching = false;
  bool _toSearching = false;
  bool _fromFocused = false;
  bool _toFocused = false;

  Timer? _fromTimer;
  Timer? _toTimer;

  bool get _allFilled => _fromPlace != null && _toPlace != null;

  @override
  void initState() {
    super.initState();
    _fromPlace = widget.initialFrom;
    _fromCtrl = TextEditingController(text: widget.initialFrom?.name ?? '');
    _toCtrl = TextEditingController();

    _fromFocus.addListener(() => setState(() => _fromFocused = _fromFocus.hasFocus));
    _toFocus.addListener(() => setState(() => _toFocused = _toFocus.hasFocus));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_toFocus);
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _fromTimer?.cancel();
    _toTimer?.cancel();
    super.dispose();
  }

  void _onFromChanged(String val) {
    _fromTimer?.cancel();
    if (val.isEmpty) {
      setState(() { _fromResults = []; _fromPlace = null; });
      return;
    }
    setState(() => _fromSearching = true);
    _fromTimer = Timer(const Duration(milliseconds: 500), () async {
      final results = await _search(val);
      if (mounted) setState(() { _fromResults = results; _fromSearching = false; });
    });
  }

  void _onToChanged(String val) {
    _toTimer?.cancel();
    if (val.isEmpty) {
      setState(() { _toResults = []; _toPlace = null; });
      return;
    }
    setState(() => _toSearching = true);
    _toTimer = Timer(const Duration(milliseconds: 500), () async {
      final results = await _search(val);
      if (mounted) setState(() { _toResults = results; _toSearching = false; });
    });
  }

  Future<List<Place>> _search(String query) async {
    final repo = ref.read(geocodeRepositoryProvider);
    final results = await repo.search(query, lat: widget.fromLat, lng: widget.fromLng);
    return results
        .map((r) => Place(name: r.name, address: r.address, lat: r.lat, lng: r.lng, distanceKm: r.distanceKm))
        .toList();
  }

  Future<void> _openPicker(bool isFrom) async {
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapAddressPicker(
          initialLat: isFrom ? widget.fromLat : (_toPlace?.lat ?? widget.fromLat),
          initialLng: isFrom ? widget.fromLng : (_toPlace?.lng ?? widget.fromLng),
          title: isFrom ? 'Qayerdan?' : 'Qayerga?',
          isFrom: isFrom,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isFrom) { _fromPlace = result; _fromCtrl.text = result.name; }
      else { _toPlace = result; _toCtrl.text = result.name; }
    });
  }

  // Tanlangan natijani inputga joylashtirish. Avval fokusni yo'qotamiz,
  // keyin bir freym kutib (addPostFrameCallback) matnni yangilaymiz —
  // aks holda FocusNode listener bilan setState orasida nomuvofiqlik
  // (race condition) yuzaga kelib, matn ekranga chiqmasligi mumkin edi.
  void _selectResult(Place place, {required bool isFrom}) {
    if (isFrom) {
      _fromFocus.unfocus();
    } else {
      _toFocus.unfocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (isFrom) {
          _fromPlace = place;
          _fromCtrl.text = place.name;
          _fromCtrl.selection = TextSelection.collapsed(offset: place.name.length);
          _fromResults = [];
          _fromFocused = false;
        } else {
          _toPlace = place;
          _toCtrl.text = place.name;
          _toCtrl.selection = TextSelection.collapsed(offset: place.name.length);
          _toResults = [];
          _toFocused = false;
        }
      });
    });
  }

  // Har ikkala chegarani ham InputBorder.none qilib qo'yish shart —
  // aks holda global tema (AppTheme)dagi focusedBorder ustunlik qilib,
  // bosilganda chiziq chiqib qoladi.
  InputDecoration _fieldDecoration({
    required String hint,
    required Color hintColor,
    required Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor),
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;

    final showFrom = _fromFocused && (_fromResults.isNotEmpty || _fromSearching);
    final showTo = _toFocused && (_toResults.isNotEmpty || _toSearching);
    final results = showFrom ? _fromResults : _toResults;
    final searching = showFrom ? _fromSearching : _toSearching;
    final isFromActive = showFrom;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
                  )),
                ),

                // Inputlar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border),
                    ),
                    child: Column(children: [
                      // Qayerdan
                      Row(children: [
                        Padding(padding: const EdgeInsets.only(left: 12),
                          child: Container(width: 24, height: 24,
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.local_shipping, size: 12, color: AppTheme.primaryColor)),
                        ),
                        Expanded(child: TextField(
                          controller: _fromCtrl,
                          focusNode: _fromFocus,
                          onChanged: _onFromChanged,
                          style: TextStyle(fontSize: 13, color: textPrimary),
                          decoration: _fieldDecoration(
                            hint: 'Qayerdan?',
                            hintColor: textSecondary,
                            suffixIcon: _fromCtrl.text.isNotEmpty
                                ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                    onPressed: () { _fromCtrl.clear(); setState(() { _fromPlace = null; _fromResults = []; }); })
                                : null,
                          ),
                        )),
                        _MapBtn(onTap: () => _openPicker(true)),
                      ]),
                      Divider(height: 1, color: border),
                      // Qayerga
                      Row(children: [
                        Padding(padding: const EdgeInsets.only(left: 12),
                          child: Container(width: 24, height: 24,
                            decoration: BoxDecoration(color: AppTheme.errorColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.location_on, size: 12, color: AppTheme.errorColor)),
                        ),
                        Expanded(child: TextField(
                          controller: _toCtrl,
                          focusNode: _toFocus,
                          onChanged: _onToChanged,
                          style: TextStyle(fontSize: 13, color: textPrimary),
                          decoration: _fieldDecoration(
                            hint: 'Qayerga?',
                            hintColor: textSecondary,
                            suffixIcon: _toCtrl.text.isNotEmpty
                                ? IconButton(icon: Icon(Icons.close, size: 14, color: textSecondary),
                                    onPressed: () { _toCtrl.clear(); setState(() { _toPlace = null; _toResults = []; }); })
                                : null,
                          ),
                        )),
                        _MapBtn(onTap: () => _openPicker(false)),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),

                // Qidiruv natijalari
                if (showFrom || showTo)
                  Expanded(
                    child: searching
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : results.isEmpty
                            ? Center(child: Text('Natija topilmadi', style: TextStyle(color: textSecondary)))
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: results.length,
                                itemBuilder: (ctx, i) {
                                  final place = results[i];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _selectResult(place, isFrom: isFromActive),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: border, width: 0.5)),
                                        ),
                                        child: Row(children: [
                                          Container(width: 32, height: 32,
                                            decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                                            child: const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.primaryColor)),
                                          const SizedBox(width: 10),
                                          Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(place.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              if (place.address.isNotEmpty && place.address != place.name)
                                                Text(place.address, style: TextStyle(fontSize: 11, color: textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          )),
                                          if (place.distanceKm != null)
                                            Container(
                                              margin: const EdgeInsets.only(left: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                place.distanceKm! < 1
                                                    ? '${(place.distanceKm! * 1000).round()} m'
                                                    : '${place.distanceKm!.toStringAsFixed(1)} km',
                                                style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                        ]),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  )
                else
                  const Spacer(),

                // Pastki tugma — bo'sh bo'lsa "Yopish", to'liq bo'lsa "Tasdiqlash"
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border(top: BorderSide(color: border)),
                  ),
                  child: _allFilled
                      ? _GradBtn(
                          label: 'Manzilni tasdiqlash',
                          onTap: () {
                            widget.onConfirmed(_fromPlace, _toPlace);
                            Navigator.pop(context);
                          },
                        )
                      : OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: border),
                            foregroundColor: textSecondary,
                          ),
                          child: const Text('Yopish', style: TextStyle(fontWeight: FontWeight.w600)),
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

class _MapBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _MapBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, size: 12, color: AppTheme.primaryColor),
            SizedBox(width: 3),
            Text('Xarita', style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _GradBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GradBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
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
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}