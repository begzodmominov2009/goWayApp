import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../core/network/driver_repository.dart';
import '../../../../core/providers/driver_cache_providers.dart';
import '../../../../core/router/app_router.dart';

final AnimationStyle _kSheetAnimationStyle = AnimationStyle(
  duration: const Duration(milliseconds: 350),
  reverseDuration: const Duration(milliseconds: 320),
);

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen> {
  // Hamyon ma'lumoti endi keshdan (driverWalletCacheProvider) o'qiladi.
  Map<String, dynamic>? get _stats {
    final data = ref.read(driverWalletCacheProvider).valueOrNull;
    if (data == null) return null;
    return Map<String, dynamic>.from((data['stats'] as Map?) ?? const {});
  }

  List<dynamic> get _transactions {
    final data = ref.read(driverWalletCacheProvider).valueOrNull;
    return List.from((data?['transactions'] as List?) ?? const []);
  }

  @override
  void initState() {
    super.initState();
    // Ochilganda: kesh eskirgan bo'lsagina yangilaydi, aks holda keshdan.
    ref.read(driverWalletCacheProvider.notifier).refreshIfStale();
  }

  // Majburiy yangilash — pull-to-refresh va topup so'rovidan keyin.
  Future<void> _load() async {
    await ref.read(driverWalletCacheProvider.notifier).forceRefresh();
  }

  void _openTopup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _kSheetAnimationStyle,
      builder: (ctx) => _TopupSheet(
        isDark: isDark,
        onClose: () => Navigator.pop(ctx),
        onDone: _load,
      ),
    );
  }

  Map<String, List<dynamic>> get _recentGrouped {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<dynamic>> grouped = {};
    for (final tx in _transactions) {
      final dateStr = tx['createdAt'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(weekAgo)) continue;

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
      grouped.putIfAbsent(label, () => []).add(tx);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final walletAsync = ref.watch(driverWalletCacheProvider);
    final loading = walletAsync.isLoading && !walletAsync.hasValue;
    final grouped = _recentGrouped;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Hamyon',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: AppLoadingIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Balans card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF2563eb)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Asosiy balans',
                            style: TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 4),
                        Text(
                          '${_stats?['currentBalance'] ?? 0} so\'m',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _WalletStat(label: 'Jami reyslar', value: '${_stats?['totalOrders'] ?? 0}'),
                            const SizedBox(width: 24),
                            _WalletStat(label: 'Jami daromad', value: '${_stats?['totalEarned'] ?? 0}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Topup tugmasi
                  GestureDetector(
                    onTap: _openTopup,
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Balans to\'ldirish',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // So'rovlarim tarixi tugmasi
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.topupRequestHistory),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 18, color: AppTheme.primaryColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('To\'ldirish so\'rovlarim tarixi',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tranzaksiyalar sarlavhasi + "Barchasini ko'rish"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('So\'nggi tranzaksiyalar',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                      if (_transactions.isNotEmpty)
                        GestureDetector(
                          onTap: () => context.push(AppRoutes.walletTransactionHistory),
                          child: const Text('Barchasini ko\'rish',
                              style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_transactions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Tranzaksiyalar yo\'q',
                            style: TextStyle(color: textSecondary)),
                      ),
                    )
                  else
                    ...grouped.entries.map((entry) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6, left: 2),
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
                                itemBuilder: (context, i) {
                                  final tx = entry.value[i] as Map<String, dynamic>;
                                  return _TransactionTile(tx: tx, textPrimary: textPrimary, textSecondary: textSecondary);
                                },
                              ),
                            ),
                          ],
                        )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  final Color textPrimary;
  final Color textSecondary;

  const _TransactionTile({required this.tx, required this.textPrimary, required this.textSecondary});

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final local = date.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
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
      title: Text(
        tx['description'] ?? tx['type'] ?? '',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      subtitle: Text(
        _formatTime(tx['createdAt'] as String?),
        style: TextStyle(fontSize: 11, color: textSecondary),
      ),
      trailing: Text(
        '${isPlus ? '+' : '-'}${tx['amount']} so\'m',
        style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: isPlus ? AppTheme.primaryColor : AppTheme.errorColor,
        ),
      ),
    );
  }
}

class _WalletStat extends StatelessWidget {
  final String label;
  final String value;
  const _WalletStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }
}

// ===== TOPUP SHEET =====
class _TopupSheet extends ConsumerStatefulWidget {
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onDone;

  const _TopupSheet({required this.isDark, required this.onClose, required this.onDone});

  @override
  ConsumerState<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends ConsumerState<_TopupSheet> {
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  bool _success = false;
  bool _cardLoading = true;
  String? _error;
  Map<String, dynamic>? _card;
  Uint8List? _receiptBytes;
  String? _receiptName;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCard() async {
    try {
      final card = await ref.read(driverRepositoryProvider).getTopupCard();
      setState(() { _card = card; _cardLoading = false; });
    } catch (_) {
      setState(() => _cardLoading = false);
    }
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final ext = image.name.split('.').last;
    setState(() {
      _receiptBytes = bytes;
      _receiptName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.$ext';
    });
  }

  void _copyCard() {
    if (_card == null) return;
    Clipboard.setData(ClipboardData(text: _card!['cardNumber'] as String));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Karta raqami nusxalandi!'),
          backgroundColor: AppTheme.successColor, duration: Duration(seconds: 2)),
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(' ', '').replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'To\'g\'ri summa kiriting');
      return;
    }
    if (_receiptBytes == null) {
      setState(() => _error = 'Chek rasmini yuklang');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(driverRepositoryProvider).requestTopup(
        amount: amount,
        receiptBytes: _receiptBytes!,
        receiptName: _receiptName!,
      );
      setState(() { _loading = false; _success = true; });
      widget.onDone();
    } catch (_) {
      setState(() { _loading = false; _error = 'Xatolik yuz berdi. Qayta urinib ko\'ring.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _success ? _buildSuccess(textPrimary) : _buildForm(isDark, surface, textPrimary, textSecondary, border, bg),
    );
  }

  Widget _buildSuccess(Color textPrimary) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 24),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: AppTheme.successColor.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, color: AppTheme.successColor, size: 36),
        ),
        const SizedBox(height: 16),
        Text('So\'rov yuborildi!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Admin tasdiqlashini kuting.\nOdatda 5-30 daqiqa ichida balansga qo\'shiladi.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: double.infinity, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: Text('Yopish',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(bool isDark, Color surface, Color textPrimary, Color textSecondary, Color border, Color bg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text('Balans to\'ldirish',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary)),
        const SizedBox(height: 16),

        if (_cardLoading)
          const Center(child: AppLoadingIndicator())
        else if (_card != null) ...[
          Text('Pul o\'tkaziladigan karta:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.credit_card, color: AppTheme.primaryColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_card!['cardNumber'] ?? '',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: textPrimary, letterSpacing: 1)),
                          Text(_card!['cardHolder'] ?? '',
                              style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _copyCard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy, size: 14, color: AppTheme.primaryColor),
                            SizedBox(width: 4),
                            Text('Nusxa', style: TextStyle(fontSize: 11, color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppTheme.primaryColor),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ushbu karta raqamini nusxalab, Click yoki Payme orqali to\'lov qiling, so\'ng chekini yuklang.',
                          style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
            ),
            child: const Text('Hozirda aktiv to\'lov kartasi yo\'q.',
                style: TextStyle(color: AppTheme.warningColor, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 14),

        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          style: TextStyle(color: textPrimary),
          decoration: const InputDecoration(
              labelText: 'To\'lov summasi (so\'m)', hintText: '500 000', suffixText: 'so\'m'),
        ),
        const SizedBox(height: 4),
        const Text('Tashlagan summangizni to\'liq va to\'g\'ri kiriting. Chek bilan bir xil bo\'lsin.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
        const SizedBox(height: 14),

        GestureDetector(
          onTap: _pickReceipt,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _receiptBytes != null ? AppTheme.successColor.withOpacity(0.05) : bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _receiptBytes != null ? AppTheme.successColor.withOpacity(0.3) : border),
            ),
            child: Row(
              children: [
                Icon(_receiptBytes != null ? Icons.check_circle : Icons.upload_outlined,
                    color: _receiptBytes != null ? AppTheme.successColor : textSecondary, size: 20),
                const SizedBox(width: 10),
                Text(_receiptBytes != null ? 'Chek yuklandi ✓' : 'Chek rasmini yuklang',
                    style: TextStyle(fontSize: 13,
                        color: _receiptBytes != null ? AppTheme.successColor : textSecondary,
                        fontWeight: _receiptBytes != null ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Chek rasmini galereyadan tanlang. Aniq va o\'qilishi mumkin bo\'lsin.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 16),

        GestureDetector(
          onTap: (_loading || _card == null) ? null : _submit,
          child: Container(
            width: double.infinity, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0f172a), Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_loading)
                  const SizedBox(width: 22, height: 22,
                      child: AppLoadingIndicator(color: Colors.white, strokeWidth: 2.5))
                else
                  Text(
                    (_card == null) ? 'Karta yo\'q' : 'Jo\'natish',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}