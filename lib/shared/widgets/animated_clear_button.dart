  import 'package:flutter/material.dart';
  import '../../core/theme/app_theme.dart';

  /// Telegram uslubidagi input tozalash (X) tugmasi — berilgan [focusNode]
  /// fokusda bo'lganda o'zi paydo bo'ladi (kengligi 0'dan ochiladi + slide +
  /// fade, ~260ms), fokusdan chiqqanda xuddi shunday yo'qoladi. Bosilganda:
  /// [controller] tozalanadi, fokus olib tashlanadi (klaviatura yopiladi,
  /// kursor yo'qoladi) va ixtiyoriy [onCleared] chaqiriladi (masalan qidiruv
  /// natijalarini ham tozalash uchun).
  ///
  /// Fokusni FocusManager.instance.primaryFocus?.unfocus() orqali IMPERATIV
  /// ravishda olib tashlaydi — FocusScope.of(context) ATAYLAB ishlatilmaydi,
  /// chunki u chaqiruvchi widget'ning context'ini ambient fokus-scope'ga
  /// InheritedWidget bog'liqligi sifatida ro'yxatdan o'tkazadi va keyinroq
  /// fokus boshqa sababdan o'zgarganda ham (masalan yangi modal route
  /// ochilganda) o'sha widget qayta qurilishiga olib keladi.
  ///
  /// O'zi [focusNode]ga obuna bo'ladi va dispose()da obunani olib tashlaydi
  /// — chaqiruvchi taraf alohida holat (masalan "_searchActive" bayrog'i)
  /// saqlashi shart emas.
  class AnimatedClearButton extends StatefulWidget {
    final TextEditingController controller;
    final FocusNode focusNode;
    final VoidCallback? onCleared;

    const AnimatedClearButton({
      super.key,
      required this.controller,
      required this.focusNode,
      this.onCleared,
    });

    @override
    State<AnimatedClearButton> createState() => _AnimatedClearButtonState();
  }

  class _AnimatedClearButtonState extends State<AnimatedClearButton> {
    static const _duration = Duration(milliseconds: 260);
    static const _curve = Curves.easeOutCubic;

    @override
    void initState() {
      super.initState();
      widget.focusNode.addListener(_onFocusChange);
    }

    @override
    void dispose() {
      widget.focusNode.removeListener(_onFocusChange);
      super.dispose();
    }

    void _onFocusChange() {
      if (mounted) setState(() {});
    }

    void _clear() {
      widget.controller.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onCleared?.call();
    }

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
      final bg = isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9);
      final visible = widget.focusNode.hasFocus;

      // ClipRect + AnimatedAlign(widthFactor) — tugma o'z tabiiy o'lchamini
      // saqlab, faqat unga ajratilgan joy silliq o'sib/qisqaradi, shu bilan
      // qo'shni (odatda Expanded) element har kadrda avtomatik moslashadi
      // va layout sakramaydi.
      return ClipRect(
        child: AnimatedAlign(
          duration: _duration,
          curve: _curve,
          alignment: Alignment.centerRight,
          widthFactor: visible ? 1.0 : 0.0,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedSlide(
                duration: _duration,
                curve: _curve,
                offset: visible ? Offset.zero : const Offset(0.4, 0),
                child: AnimatedOpacity(
                  duration: _duration,
                  curve: _curve,
                  opacity: visible ? 1 : 0,
                  child: GestureDetector(
                    onTap: _clear,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 18, color: textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
