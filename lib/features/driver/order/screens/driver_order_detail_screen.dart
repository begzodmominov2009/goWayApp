import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/network/sos_repository.dart';

class DriverOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const DriverOrderDetailScreen({super.key, required this.orderId});
  @override
  ConsumerState<DriverOrderDetailScreen> createState() => _DriverOrderDetailScreenState();
}

class _DriverOrderDetailScreenState extends ConsumerState<DriverOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  static const _steps = [
    'ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT', 'DELIVERED',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final order = await ref.read(driverRepositoryProvider).getOrder(widget.orderId);
      setState(() { _order = order; _loading = false; });
    } catch (_) {
      setState(() { _loading = false; _error = 'Buyurtma topilmadi'; });
    }
  }

  int _currentStepIndex(String status) {
    final idx = _steps.indexOf(status);
    return idx == -1 ? 0 : idx;
  }

  Future<void> _advanceStatus() async {
    if (_order == null) return;
    final status = _order!['status'] as String;
    final idx = _currentStepIndex(status);
    if (idx >= _steps.length - 1) return;
    final nextStatus = _steps[idx + 1];
    try {
      await ref.read(driverRepositoryProvider).updateOrderStatus(widget.orderId, nextStatus);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // SOS signali — tasdiqlash dialogi orqali, joriy joylashuv bilan
  // birga backend'ga yuboriladi.
  Future<void> _sendSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 24),
          SizedBox(width: 8),
          Text('SOS signal yuborish'),
        ]),
        content: const Text(
          'SOS signal yuborilganda, sizning joriy joylashuvingiz admin panelga darhol yuboriladi. Faqat favqulodda holatlarda ishlating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SOS yuborish', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      await ref.read(sosRepositoryProvider).sendSos(lat: position.latitude, lng: position.longitude);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS signal yuborildi. Yordam yo\'lda.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOS yuborishda xatolik: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Buyurtma #${widget.orderId.substring(0, 6)}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null || _order == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: textSecondary),
                      const SizedBox(height: 12),
                      Text(_error ?? 'Buyurtma topilmadi', style: TextStyle(color: textSecondary)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('Qayta urinish')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Marshrut
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            Column(
                              children: [
                                Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)),
                                Container(width: 1.5, height: 40, color: border),
                                Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle)),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_order?['fromCity'] ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                                  Text(_order?['fromAddress'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                                  const SizedBox(height: 16),
                                  Text(_order?['toCity'] ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                                  Text(_order?['toAddress'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                                ],
                              ),
                            ),
                            Text('${_order?['price'] ?? 0} so\'m',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Client ma'lumotlari
                      if (_order?['client'] != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                          ),
                          child: Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.person, color: AppTheme.primaryColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_order?['client']?['fullName'] ?? 'Mijoz',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                Text(_order?['client']?['user']?['phone'] ?? '',
                                    style: TextStyle(fontSize: 12, color: textSecondary)),
                              ],
                            )),
                          ]),
                        ),
                      const SizedBox(height: 12),
                      // Status
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                            const SizedBox(height: 12),
                            _StatusStep(label: 'Qabul qilindi', isDone: _currentStepIndex(_order!['status']) >= 0, isActive: false, isDark: isDark),
                            _StatusStep(label: 'Mijozga bormoqda', isDone: _currentStepIndex(_order!['status']) >= 1, isActive: _order!['status'] == 'DRIVER_ARRIVING', isDark: isDark),
                            _StatusStep(label: 'Yuk ortilmoqda', isDone: _currentStepIndex(_order!['status']) >= 2, isActive: _order!['status'] == 'LOADING', isDark: isDark),
                            _StatusStep(label: 'Yo\'lda', isDone: _currentStepIndex(_order!['status']) >= 3, isActive: _order!['status'] == 'IN_TRANSIT', isDark: isDark),
                            _StatusStep(label: 'Yetkazildi', isDone: _currentStepIndex(_order!['status']) >= 4, isActive: false, isDark: isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Keyingi bosqichga o'tish tugmasi
                      if (_currentStepIndex(_order!['status']) < _steps.length - 1)
                        GestureDetector(
                          onTap: _advanceStatus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2563eb)]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                _nextStepLabel(_order!['status']),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      // SOS tugmasi — endi ishlaydi, tasdiqlash bilan
                      GestureDetector(
                        onTap: _sendSos,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.errorColor),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sos_outlined, color: AppTheme.errorColor, size: 20),
                              SizedBox(width: 8),
                              Text('SOS signal', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w700, fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  String _nextStepLabel(String currentStatus) {
    switch (currentStatus) {
      case 'ACCEPTED': return 'Mijozga yetib keldim';
      case 'DRIVER_ARRIVING': return 'Yuk ortildi';
      case 'LOADING': return 'Yo\'lga chiqdim';
      case 'IN_TRANSIT': return 'Yetkazib berdim';
      default: return 'Davom etish';
    }
  }
}

class _StatusStep extends StatelessWidget {
  final String label;
  final bool isDone;
  final bool isActive;
  final bool isDark;
  const _StatusStep({required this.label, required this.isDone, this.isActive = false, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isDone ? AppTheme.successColor : isActive ? AppTheme.primaryColor : (isDark ? AppTheme.darkBackground : AppTheme.backgroundColor),
              shape: BoxShape.circle,
              border: Border.all(color: isDone ? AppTheme.successColor : isActive ? AppTheme.primaryColor : (isDark ? AppTheme.darkBorder : AppTheme.borderColor)),
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : isActive
                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: isDone || isActive ? FontWeight.w600 : FontWeight.w400,
            color: isDone ? AppTheme.successColor : isActive ? AppTheme.primaryColor : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
          )),
        ],
      ),
    );
  }
}