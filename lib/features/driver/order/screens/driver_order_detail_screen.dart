import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/driver_repository.dart';

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

  // COMPLETED holati DELIVERED bilan bir xil bosqichda hisoblanadi;
  // CANCELLED — _steps ro'yxatida yo'q, alohida belgi bilan ko'rsatiladi.
  int _currentStepIndex(String status) {
    if (status == 'COMPLETED') return _steps.length - 1;
    final idx = _steps.indexOf(status);
    return idx == -1 ? 0 : idx;
  }

  List<Map<String, dynamic>> _sosList() {
    final raw = _order?['sosList'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  double? _distanceTraveledKm() {
    final raw = _order?['distance'] ?? _order?['distanceKm'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  int? _clientScore() {
    final ratings = _order?['ratings'];
    Map<String, dynamic>? rating;
    if (ratings is List && ratings.isNotEmpty) {
      rating = Map<String, dynamic>.from(ratings.first as Map);
    } else if (ratings is Map) {
      rating = Map<String, dynamic>.from(ratings);
    }
    final score = rating?['clientScore'];
    return score is num ? score.toInt() : null;
  }

  String? _completionDuration(String locale) {
    final created = DateTime.tryParse(_order?['createdAt'] as String? ?? '');
    final updated = DateTime.tryParse(_order?['updatedAt'] as String? ?? '');
    if (created == null || updated == null) return null;
    final diff = updated.difference(created);
    if (diff.isNegative) return null;
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return '$hours ${AppStrings.get('route_time_hour', locale)} $minutes ${AppStrings.get('route_time_min', locale)}';
  }

  String _formatDateTime(String? dateStr) {
    final date = DateTime.tryParse(dateStr ?? '')?.toLocal();
    if (date == null) return '';
    final d = date.day.toString().padLeft(2, '0');
    final mo = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final mi = date.minute.toString().padLeft(2, '0');
    return '$d.$mo.${date.year}, $h:$mi';
  }

  // Telefon raqamiga qo'ng'iroq qilishdan oldin tasdiqlash so'raladi.
  Future<void> _confirmAndCall(String phone) async {
    if (phone.isEmpty) return;
    final locale = ref.read(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppStrings.get('call_confirm_title', locale),
            style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('$phone\n${AppStrings.get('call_confirm_message', locale)}',
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get('cancel', locale),
                style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get('call', locale),
                style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('call_failed', locale)), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('call_failed', locale)), backgroundColor: AppTheme.errorColor),
        );
      }
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
          ? const Center(child: AppLoadingIndicator())
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
                                if ((_order?['client']?['user']?['phone'] as String? ?? '').isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _confirmAndCall(_order!['client']['user']['phone'] as String),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.phone_outlined, size: 12, color: AppTheme.primaryColor),
                                      const SizedBox(width: 4),
                                      Text(_order!['client']['user']['phone'] as String,
                                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                                    ]),
                                  ),
                              ],
                            )),
                          ]),
                        ),
                      const SizedBox(height: 12),
                      // Status tarixi — faqat o'qish uchun (bu sahifa buyurtmalar
                      // tarixidan ochiladi, aktiv buyurtma paneli emas)
                      Builder(builder: (context) {
                        final status = _order!['status'] as String;
                        final currentIdx = _currentStepIndex(status);
                        final isCancelled = status == 'CANCELLED';
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppStrings.get('status_history_label', locale),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                              const SizedBox(height: 12),
                              _StatusStep(label: AppStrings.get('status_accepted', locale), isDone: currentIdx >= 0, isDark: isDark),
                              _StatusStep(label: AppStrings.get('status_driver_arriving', locale), isDone: currentIdx >= 1, isDark: isDark),
                              _StatusStep(label: AppStrings.get('status_loading', locale), isDone: currentIdx >= 2, isDark: isDark),
                              _StatusStep(label: AppStrings.get('status_in_transit', locale), isDone: currentIdx >= 3, isDark: isDark),
                              _StatusStep(label: AppStrings.get('status_delivered', locale), isDone: currentIdx >= 4, isDark: isDark),
                              if (isCancelled)
                                _StatusStep(label: AppStrings.get('status_cancelled', locale), isDone: true, isCancelled: true, isDark: isDark),
                            ],
                          ),
                        );
                      }),
                      // SOS ma'lumoti — faqat shu buyurtmaga oid SOS signal(lar)
                      // yuborilgan bo'lsa ko'rsatiladi, aks holda bo'lim umuman yo'q
                      if (_sosList().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.errorColor.withOpacity(0.12) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.emergency_share_outlined, size: 18, color: AppTheme.errorColor),
                                const SizedBox(width: 8),
                                Text(AppStrings.get('sos_sent_label', locale),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                              ]),
                              const SizedBox(height: 8),
                              for (final sos in _sosList())
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(_formatDateTime(sos['createdAt'] as String?),
                                      style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                                ),
                            ],
                          ),
                        ),
                      ],
                      // Qo'shimcha ma'lumot — masofa/davomiylik/reyting maydonlari
                      // backend javobida mavjud bo'lgandagina ko'rsatiladi
                      Builder(builder: (context) {
                        final distanceKm = _distanceTraveledKm();
                        final duration = _completionDuration(locale);
                        final clientScore = _clientScore();
                        if (distanceKm == null && duration == null && clientScore == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppStrings.get('additional_info_label', locale),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                                const SizedBox(height: 10),
                                if (distanceKm != null)
                                  _InfoRow(
                                    label: AppStrings.get('distance_traveled_label', locale),
                                    value: '${distanceKm.toStringAsFixed(1)} km',
                                    textPrimary: textPrimary, textSecondary: textSecondary,
                                  ),
                                if (duration != null)
                                  _InfoRow(
                                    label: AppStrings.get('completion_duration_label', locale),
                                    value: duration,
                                    textPrimary: textPrimary, textSecondary: textSecondary,
                                  ),
                                if (clientScore != null)
                                  _InfoRow(
                                    label: AppStrings.get('client_rating_label', locale),
                                    value: '${'⭐' * clientScore}${'☆' * (5 - clientScore)} ($clientScore/5)',
                                    textPrimary: textPrimary, textSecondary: textSecondary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  const _InfoRow({required this.label, required this.value, required this.textPrimary, required this.textSecondary});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: textSecondary)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
        ],
      ),
    );
  }
}

class _StatusStep extends StatelessWidget {
  final String label;
  final bool isDone;
  final bool isCancelled;
  final bool isDark;
  const _StatusStep({required this.label, required this.isDone, this.isCancelled = false, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final activeColor = isCancelled ? AppTheme.errorColor : AppTheme.successColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isDone ? activeColor : (isDark ? AppTheme.darkBackground : AppTheme.backgroundColor),
              shape: BoxShape.circle,
              border: Border.all(color: isDone ? activeColor : (isDark ? AppTheme.darkBorder : AppTheme.borderColor)),
            ),
            child: Center(
              child: isDone
                  ? Icon(isCancelled ? Icons.close : Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: isDone ? FontWeight.w600 : FontWeight.w400,
            color: isDone ? activeColor : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
          )),
        ],
      ),
    );
  }
}