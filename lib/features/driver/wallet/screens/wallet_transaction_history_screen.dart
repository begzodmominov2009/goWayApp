import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/driver_repository.dart';

class WalletTransactionHistoryScreen extends ConsumerStatefulWidget {
  const WalletTransactionHistoryScreen({super.key});

  @override
  ConsumerState<WalletTransactionHistoryScreen> createState() => _WalletTransactionHistoryScreenState();
}

class _WalletTransactionHistoryScreenState extends ConsumerState<WalletTransactionHistoryScreen> {
  List<dynamic> _transactions = [];
  bool _loading = true;
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
      final history = await ref.read(driverRepositoryProvider).getHistory();
      setState(() {
        _transactions = List.from((history['transactions'] as List?) ?? []);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_searchQuery.isEmpty) return _transactions;
    return _transactions.where((tx) {
      final desc = (tx['description'] as String? ?? '').toLowerCase();
      return desc.contains(_searchQuery);
    }).toList();
  }

  Map<String, List<dynamic>> get _grouped {
    final Map<String, List<dynamic>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final tx in _filtered) {
      final dateStr = tx['createdAt'] as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      String label;
      if (date == null) {
        label = 'Boshqa';
      } else {
        final dateOnly = DateTime(date.year, date.month, date.day);
        if (dateOnly == today) {
          label = 'Bugun';
        } else if (dateOnly == yesterday) {
          label = 'Kecha';
        } else {
          const months = ['yan', 'fev', 'mar', 'apr', 'may', 'iyun', 'iyul', 'avg', 'sen', 'okt', 'noy', 'dek'];
          label = '${date.day} ${months[date.month - 1]} ${date.year}';
        }
      }
      grouped.putIfAbsent(label, () => []).add(tx);
    }
    return grouped;
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr)?.toLocal();
    if (date == null) return '';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final grouped = _grouped;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Tranzaksiyalar tarixi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: Column(
        children: [
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
                  hintText: 'Qidirish...',
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text('Tranzaksiyalar topilmadi', style: TextStyle(color: textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: grouped.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 6, left: 2),
                                  child: Text(entry.key,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: border),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: entry.value.length,
                                    separatorBuilder: (_, __) => Divider(height: 1, color: border),
                                    itemBuilder: (ctx, i) {
                                      final tx = entry.value[i] as Map<String, dynamic>;
                                      final isPlus = tx['type'] == 'DEPOSIT' || tx['type'] == 'TOPUP';
                                      return ListTile(
                                        leading: Container(
                                          width: 36, height: 36,
                                          decoration: BoxDecoration(
                                            color: isPlus ? AppTheme.primaryColor.withOpacity(0.1) : AppTheme.errorColor.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isPlus ? Icons.arrow_downward : Icons.arrow_upward,
                                            size: 16,
                                            color: isPlus ? AppTheme.primaryColor : AppTheme.errorColor,
                                          ),
                                        ),
                                        title: Text(tx['description'] ?? tx['type'] ?? '',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                                        subtitle: Text(_formatTime(tx['createdAt'] as String?),
                                            style: TextStyle(fontSize: 11, color: textSecondary)),
                                        trailing: Text(
                                          '${isPlus ? '+' : '-'}${tx['amount']} so\'m',
                                          style: TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w700,
                                            color: isPlus ? AppTheme.primaryColor : AppTheme.errorColor,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
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