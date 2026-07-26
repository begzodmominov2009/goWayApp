import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/providers/driver_cache_providers.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';

enum _TopupFilter { all, pending, approved, rejected }

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

class TopupRequestHistoryScreen extends ConsumerStatefulWidget {
  const TopupRequestHistoryScreen({super.key});

  @override
  ConsumerState<TopupRequestHistoryScreen> createState() => _TopupRequestHistoryScreenState();
}

class _TopupRequestHistoryScreenState extends ConsumerState<TopupRequestHistoryScreen> {
  // Balans to'ldirish so'rovlari endi keshdan (driverTopupHistoryCacheProvider).
  List<Map<String, dynamic>> get _requests =>
      ref.read(driverTopupHistoryCacheProvider).valueOrNull ?? const [];
  _TopupFilter _filter = _TopupFilter.all;

  @override
  void initState() {
    super.initState();
    ref.read(driverTopupHistoryCacheProvider.notifier).refreshIfStale();
  }

  // Pull-to-refresh — majburiy yangilash.
  Future<void> _load() async {
    await ref.read(driverTopupHistoryCacheProvider.notifier).forceRefresh();
  }

  bool _matchesFilter(String status) {
    switch (_filter) {
      case _TopupFilter.all: return true;
      case _TopupFilter.pending: return status == 'PENDING';
      case _TopupFilter.approved: return status == 'APPROVED';
      case _TopupFilter.rejected: return status == 'REJECTED';
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _requests.where((r) => _matchesFilter(r['status'] as String? ?? '')).toList();

  Color _statusColor(String status) {
    switch (status) {
      case 'PENDING': return AppTheme.warningColor;
      case 'APPROVED': return AppTheme.successColor;
      case 'REJECTED': return AppTheme.errorColor;
      default: return AppTheme.textSecondary;
    }
  }

  String _statusText(String status, String locale) {
    switch (status) {
      case 'PENDING': return AppStrings.get('topup_status_pending', locale);
      case 'APPROVED': return AppStrings.get('topup_status_approved', locale);
      case 'REJECTED': return AppStrings.get('topup_status_rejected', locale);
      default: return status;
    }
  }

  String _formatDateTime(String? dateStr, String locale) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr)?.toLocal();
    if (date == null) return '';
    final month = AppStrings.get('month_short_${date.month.toString().padLeft(2, '0')}', locale);
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day} $month ${date.year}, $h:$m';
  }

  void _showDetail(Map<String, dynamic> req) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.read(localeProvider).languageCode;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final status = req['status'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_statusText(status, locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(status))),
              ),
              const Spacer(),
              Text('${req['amount']} so\'m', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
            ]),
            const SizedBox(height: 14),
            _DetailRow(label: AppStrings.get('topup_request_date', locale), value: _formatDateTime(req['createdAt'] as String?, locale), textPrimary: textPrimary, textSecondary: textSecondary),
            if (req['approvedAmount'] != null)
              _DetailRow(label: AppStrings.get('topup_approved_amount', locale), value: '${req['approvedAmount']} so\'m', textPrimary: textPrimary, textSecondary: textSecondary),
            if (status == 'REJECTED' && req['adminNote'] != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.errorColor.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline, size: 15, color: AppTheme.errorColor),
                      const SizedBox(width: 6),
                      Text(AppStrings.get('topup_rejection_reason', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                    ]),
                    const SizedBox(height: 6),
                    Text(req['adminNote'] as String, style: TextStyle(fontSize: 13, color: textPrimary, height: 1.4)),
                  ],
                ),
              ),
            ],
            if (req['receiptUrl'] != null) ...[
              const SizedBox(height: 14),
              Text(AppStrings.get('topup_receipt_label', locale), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(req['receiptUrl'] as String, width: double.infinity, height: 180, fit: BoxFit.cover),
              ),
            ],
          ],
        ),
      ),
    );
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
    final topupAsync = ref.watch(driverTopupHistoryCacheProvider);
    final loading = topupAsync.isLoading && !topupAsync.hasValue;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.get('topup_history_title', locale),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _FilterBtn(label: AppStrings.get('topup_filter_all', locale), selected: _filter == _TopupFilter.all, isDark: isDark, onTap: () => setState(() => _filter = _TopupFilter.all))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: AppStrings.get('topup_status_pending', locale), selected: _filter == _TopupFilter.pending, isDark: isDark, onTap: () => setState(() => _filter = _TopupFilter.pending))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: AppStrings.get('topup_status_approved', locale), selected: _filter == _TopupFilter.approved, isDark: isDark, onTap: () => setState(() => _filter = _TopupFilter.approved))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: AppStrings.get('topup_status_rejected', locale), selected: _filter == _TopupFilter.rejected, isDark: isDark, onTap: () => setState(() => _filter = _TopupFilter.rejected))),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: AppLoadingIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text(AppStrings.get('topup_no_requests_found', locale), style: TextStyle(color: textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final req = _filtered[i];
                            final status = req['status'] as String? ?? '';
                            return GestureDetector(
                              onTap: () => _showDetail(req),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), shape: BoxShape.circle),
                                      child: Icon(
                                        status == 'PENDING' ? Icons.hourglass_empty
                                            : status == 'APPROVED' ? Icons.check_circle_outline
                                            : Icons.cancel_outlined,
                                        size: 18, color: _statusColor(status),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${req['amount']} so\'m',
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                          const SizedBox(height: 3),
                                          Text(_formatDateTime(req['createdAt'] as String?, locale),
                                              style: TextStyle(fontSize: 11, color: textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text(_statusText(status, locale),
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterBtn({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)]) : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : border),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: selected ? Colors.white : textSecondary)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  const _DetailRow({required this.label, required this.value, required this.textPrimary, required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text('$label: ', style: TextStyle(fontSize: 12, color: textSecondary)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary))),
      ]),
    );
  }
}