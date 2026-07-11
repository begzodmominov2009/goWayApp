import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/notification_repository.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(notificationRepositoryProvider).getNotifications();
      setState(() { _notifications = list; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(AppNotification n) async {
    if (n.isRead) return;
    try {
      await ref.read(notificationRepositoryProvider).markAsRead(n.id);
      setState(() {
        final index = _notifications.indexWhere((x) => x.id == n.id);
        if (index != -1) {
          _notifications[index] = AppNotification(
            id: n.id, type: n.type, title: n.title, body: n.body,
            isRead: true, createdAt: n.createdAt, date: n.date, time: n.time,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllAsRead();
      await _load();
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'ORDER': return Icons.local_shipping_outlined;
      case 'WALLET': return Icons.account_balance_wallet_outlined;
      case 'DRIVER': return Icons.badge_outlined;
      case 'PAYMENT': return Icons.payments_outlined;
      case 'SOS': return Icons.warning_amber_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'ORDER': return AppTheme.primaryColor;
      case 'WALLET': return AppTheme.successColor;
      case 'DRIVER': return AppTheme.warningColor;
      case 'SOS': return AppTheme.errorColor;
      default: return AppTheme.textSecondary;
    }
  }

  // Bildirishnomalarni sana bo'yicha guruhlaydi — "Bugun", "Kecha",
  // yoki "9 iyul" kabi sarlavhalar ostida (Yandex/Payme uslubida)
  Map<String, List<AppNotification>> get _grouped {
    final Map<String, List<AppNotification>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final n in _notifications) {
      final date = DateTime.tryParse(n.createdAt);
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
          label = '${date.day} ${months[date.month - 1]}';
        }
      }
      grouped.putIfAbsent(label, () => []).add(n);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.backgroundColor;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    final border = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    final hasUnread = _notifications.any((n) => !n.isRead);
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
        title: Text('Bildirishnomalar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Hammasini o\'qish', style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: textSecondary),
                      const SizedBox(height: 16),
                      Text('Bildirishnomalar yo\'q', style: TextStyle(fontSize: 16, color: textSecondary)),
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
                            padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
                            child: Text(entry.key,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                          ),
                          ...entry.value.map((n) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GestureDetector(
                                  onTap: () => _markAsRead(n),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: n.isRead ? surface : _colorForType(n.type).withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: n.isRead ? border : _colorForType(n.type).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40, height: 40,
                                          decoration: BoxDecoration(
                                            color: _colorForType(n.type).withOpacity(0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(_iconForType(n.type), size: 20, color: _colorForType(n.type)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(n.title,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                                                          color: textPrimary,
                                                        )),
                                                  ),
                                                  if (!n.isRead)
                                                    Container(
                                                      width: 8, height: 8,
                                                      margin: const EdgeInsets.only(left: 6, top: 4),
                                                      decoration: BoxDecoration(color: _colorForType(n.type), shape: BoxShape.circle),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(n.body, style: TextStyle(fontSize: 13, color: textSecondary)),
                                              const SizedBox(height: 6),
                                              Text(
                                                n.time != null ? n.time! : '',
                                                style: TextStyle(fontSize: 11, color: textSecondary.withOpacity(0.7)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}