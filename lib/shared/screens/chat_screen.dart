import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_loading_indicator.dart';
import '../../core/network/chat_repository.dart';
import '../../core/network/auth_repository.dart';

/// Bitta buyurtmaga tegishli chat oynasi — client va driver o'rtasida.
/// Faqat aktiv buyurtma bo'lganda ochiladi (Yandex/Uber uslubida).
class ChatScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String otherPersonName;

  const ChatScreen({
    super.key,
    required this.orderId,
    required this.otherPersonName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  String? _myUserId;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages(scrollToEnd: false));
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _myUserId = await ref.read(authRepositoryProvider).getUserId();
    await _loadMessages(scrollToEnd: true);
  }

  Future<void> _loadMessages({required bool scrollToEnd}) async {
    try {
      final messages = await ref.read(chatRepositoryProvider).getMessages(widget.orderId);
      if (!mounted) return;
      setState(() { _messages = messages; _loading = false; });
      if (scrollToEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    try {
      final sent = await ref.read(chatRepositoryProvider).sendMessage(widget.orderId, text);
      if (!mounted) return;
      setState(() => _messages.add(sent));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xabar yuborilmadi'), backgroundColor: AppTheme.errorColor),
        );
      }
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
        title: Text(widget.otherPersonName,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: AppLoadingIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text('Hozircha xabarlar yo\'q',
                            style: TextStyle(color: textSecondary, fontSize: 14)),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMine = msg.senderId == _myUserId;
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                              decoration: BoxDecoration(
                                gradient: isMine
                                    ? const LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)])
                                    : null,
                                color: isMine ? null : surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isMine ? 14 : 2),
                                  bottomRight: Radius.circular(isMine ? 2 : 14),
                                ),
                                border: isMine ? null : Border.all(color: border),
                              ),
                              child: Text(
                                msg.message,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isMine ? Colors.white : textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 12, right: 12, top: 8,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
            ),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkBackground : AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Xabar yozing...',
                        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}