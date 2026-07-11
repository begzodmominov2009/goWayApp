import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/client_repository.dart';

class ClientOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ClientOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<ClientOrderDetailScreen> createState() => _ClientOrderDetailScreenState();
}

class _ClientOrderDetailScreenState extends ConsumerState<ClientOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final order = await ref.read(clientRepositoryProvider).getOrder(widget.orderId);
      setState(() { _order = order; _loading = false; });
    } catch (_) {
      setState(() { _loading = false; _error = 'Buyurtma topilmadi'; });
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'SEARCHING': return 'Haydovchi qidirilmoqda';
      case 'OFFERED': return 'Taklif yuborilgan';
      case 'ACCEPTED': return 'Qabul qilindi';
      case 'DRIVER_ARRIVING': return 'Haydovchi kelmoqda';
      case 'LOADING': return 'Yuklanmoqda';
      case 'IN_TRANSIT': return 'Yo\'lda';
      case 'DELIVERED': return 'Yetkazildi';
      case 'COMPLETED': return 'Yakunlandi';
      case 'CANCELLED': return 'Bekor qilindi';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'SEARCHING':
      case 'OFFERED':
        return AppTheme.warningColor;
      case 'ACCEPTED':
      case 'DRIVER_ARRIVING':
      case 'LOADING':
      case 'IN_TRANSIT':
        return AppTheme.primaryColor;
      case 'DELIVERED':
      case 'COMPLETED':
        return AppTheme.successColor;
      case 'CANCELLED':
        return AppTheme.errorColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        title: Text('Buyurtma tafsilotlari',
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
                      // Status + narx
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _statusColor(_order!['status'] as String? ?? '').withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _statusText(_order!['status'] as String? ?? ''),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(_order!['status'] as String? ?? '')),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${((_order!['price'] as num?) ?? 0).toStringAsFixed(0)} so\'m',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Marshrut
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  Text(_order!['fromCity'] as String? ?? '—',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                                  if ((_order!['fromAddress'] as String? ?? '').isNotEmpty)
                                    Text(_order!['fromAddress'] as String,
                                        style: TextStyle(fontSize: 12, color: textSecondary)),
                                  const SizedBox(height: 16),
                                  Text(_order!['toCity'] as String? ?? '—',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                                  if ((_order!['toAddress'] as String? ?? '').isNotEmpty)
                                    Text(_order!['toAddress'] as String,
                                        style: TextStyle(fontSize: 12, color: textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Yuk ma'lumotlari
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
                            Text('Yuk ma\'lumotlari',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                            const SizedBox(height: 12),
                            _InfoRow(icon: Icons.local_shipping_outlined, label: 'Mashina turi', value: _order!['truckType'] as String? ?? '—', isDark: isDark),
                            const SizedBox(height: 8),
                            _InfoRow(icon: Icons.scale_outlined, label: 'Og\'irlik', value: '${_order!['weight'] ?? '—'} t', isDark: isDark),
                            if ((_order!['note'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              _InfoRow(icon: Icons.notes_outlined, label: 'Izoh', value: _order!['note'] as String, isDark: isDark),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Driver ma'lumotlari (agar tayinlangan bo'lsa)
                      if (_order!['driver'] != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    ((_order!['driver']['fullName'] as String? ?? 'D')).isNotEmpty
                                        ? (_order!['driver']['fullName'] as String? ?? 'D')[0].toUpperCase()
                                        : 'D',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_order!['driver']['fullName'] as String? ?? '',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                                    const SizedBox(height: 2),
                                    Text(_order!['driver']['plateNumber'] as String? ?? '',
                                        style: TextStyle(fontSize: 12, color: textSecondary)),
                                  ],
                                ),
                              ),
                              Row(children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                const SizedBox(width: 2),
                                Text('${_order!['driver']['averageRating'] ?? 5}',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({required this.icon, required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 15, color: textSecondary),
        const SizedBox(width: 8),
        Text('$label:', style: TextStyle(fontSize: 12, color: textSecondary)),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary))),
      ],
    );
  }
}