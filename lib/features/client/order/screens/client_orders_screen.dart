import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/client_repository.dart';

enum _FilterType { all, pending, accepted, cancelled }

class ClientOrdersScreen extends ConsumerStatefulWidget {
  const ClientOrdersScreen({super.key});

  @override
  ConsumerState<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends ConsumerState<ClientOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  _FilterType _filter = _FilterType.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final orders = await ref.read(clientRepositoryProvider).getOrders();
      setState(() { _orders = orders; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // Backend statuslarini 3 ta guruhga ajratish
  bool _matchesFilter(String status) {
    switch (_filter) {
      case _FilterType.all:
        return true;
      case _FilterType.pending:
        return ['SEARCHING', 'OFFERED', 'ACCEPTED', 'DRIVER_ARRIVING', 'LOADING', 'IN_TRANSIT'].contains(status);
      case _FilterType.accepted:
        return ['DELIVERED', 'COMPLETED'].contains(status);
      case _FilterType.cancelled:
        return status == 'CANCELLED';
    }
  }

  bool _matchesSearch(Map<String, dynamic> order) {
    if (_searchQuery.isEmpty) return true;
    final from = (order['fromCity'] as String? ?? '').toLowerCase();
    final to = (order['toCity'] as String? ?? '').toLowerCase();
    return from.contains(_searchQuery) || to.contains(_searchQuery);
  }

  List<Map<String, dynamic>> get _filtered {
    return _orders.where((o) {
      final status = o['status'] as String? ?? '';
      return _matchesFilter(status) && _matchesSearch(o);
    }).toList();
  }

  // Sana bo'yicha guruhlash — Payme uslubida
  Map<String, List<Map<String, dynamic>>> get _groupedByDate {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final order in _filtered) {
      final createdAt = order['createdAt'] as String?;
      if (createdAt == null) continue;
      final date = DateTime.tryParse(createdAt);
      if (date == null) continue;
      final dateOnly = DateTime(date.year, date.month, date.day);

      String label;
      if (dateOnly == today) {
        label = 'Bugun';
      } else if (dateOnly == yesterday) {
        label = 'Kecha';
      } else {
        const months = ['yan', 'fev', 'mar', 'apr', 'may', 'iyun', 'iyul', 'avg', 'sen', 'okt', 'noy', 'dek'];
        label = '${date.day} ${months[date.month - 1]}';
      }

      grouped.putIfAbsent(label, () => []).add(order);
    }
    return grouped;
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

  bool _canCancel(String status) => status == 'SEARCHING' || status == 'OFFERED';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final grouped = _groupedByDate;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Buyurtmalarim', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textPrimary, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Qidiruv
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Shahar bo\'yicha qidirish...',
                  hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, size: 18, color: textSecondary),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Filter tugmalari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _FilterBtn(label: 'Barchasi', selected: _filter == _FilterType.all, isDark: isDark, onTap: () => setState(() => _filter = _FilterType.all))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: 'Kutilmoqda', selected: _filter == _FilterType.pending, isDark: isDark, onTap: () => setState(() => _filter = _FilterType.pending))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: 'Yakunlangan', selected: _filter == _FilterType.accepted, isDark: isDark, onTap: () => setState(() => _filter = _FilterType.accepted))),
                const SizedBox(width: 8),
                Expanded(child: _FilterBtn(label: 'Bekor', selected: _filter == _FilterType.cancelled, isDark: isDark, onTap: () => setState(() => _filter = _FilterType.cancelled))),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Ro'yxat
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: textSecondary),
                            const SizedBox(height: 16),
                            Text('Buyurtmalar topilmadi', style: TextStyle(fontSize: 16, color: textSecondary)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: grouped.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 8, left: 4),
                                  child: Text(entry.key,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                                ),
                                ...entry.value.map((order) {
                                  final status = order['status'] as String? ?? '';
                                  final orderId = order['id'] as String? ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GestureDetector(
                                      onTap: () => context.push('/client/order/$orderId'),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: surface,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: border),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(14),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${order['fromCity'] ?? ''} → ${order['toCity'] ?? ''}',
                                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(status).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(_statusText(status),
                                                    style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.w700)),
                                              ),
                                            ],
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 6),
                                              Text(order['truckType'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                                              if (order['price'] != null)
                                                Text('${(order['price'] as num).toStringAsFixed(0)} so\'m',
                                                    style: const TextStyle(fontSize: 13, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                          trailing: _canCancel(status)
                                              ? TextButton(
                                                  onPressed: () async {
                                                    await ref.read(clientRepositoryProvider).cancelOrder(orderId);
                                                    _load();
                                                  },
                                                  child: const Text('Bekor', style: TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                                                )
                                              : const Icon(Icons.chevron_right, size: 18),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }).toList(),
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
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)])
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : textSecondary,
          ),
        ),
      ),
    );
  }
}