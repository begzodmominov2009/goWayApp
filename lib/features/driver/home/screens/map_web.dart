import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

bool _registered = false;

void updateWebMapLocation(double lat, double lng) {
  js.context.callMethod('updateDriverLocation', [lat, lng]);
}

void setMapDarkMode(bool isDark) {
  js.context.callMethod('setMapDarkMode', [isDark]);
}

Widget buildMap({required double lat, required double lng, bool isDark = false}) {
  const viewType = 'yandex-map-view';

  if (!_registered) {
    _registered = true;
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final div = html.DivElement()
        ..id = 'yandex-map-$viewId'
        ..style.width = '100%'
        ..style.height = '100%';

      Future.delayed(const Duration(milliseconds: 800), () {
        js.context.callMethod('initYandexMap', ['yandex-map-$viewId', lat, lng, isDark]);
      });

      return div;
    });
  } else {
    Future.microtask(() => setMapDarkMode(isDark));
  }

  final btnBg = isDark ? AppTheme.darkSurface : Colors.white;
  final btnBorder = isDark ? AppTheme.darkBorder : AppTheme.borderColor;
  final btnIcon = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;

  return Stack(
    children: [
      const HtmlElementView(viewType: viewType),
      Positioned(
        left: 12,
        bottom: 220,
        child: Column(
          children: [
            _MapButton(icon: Icons.my_location, tooltip: 'Meni topish',
                onTap: () => js.context.callMethod('goToMyLocation', []),
                bg: btnBg, border: btnBorder, iconColor: btnIcon),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: btnBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: btnBorder),
              ),
              child: Column(
                children: [
                  _MapButton(icon: Icons.add, tooltip: 'Yaqinlashtirish',
                      onTap: () => js.context.callMethod('zoomIn', []),
                      bg: btnBg, border: btnBorder, iconColor: btnIcon, rounded: false),
                  Container(height: 0.5, color: btnBorder),
                  _MapButton(icon: Icons.remove, tooltip: 'Uzoqlashtirish',
                      onTap: () => js.context.callMethod('zoomOut', []),
                      bg: btnBg, border: btnBorder, iconColor: btnIcon, rounded: false),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _MapTypePanel(isDark: isDark),
          ],
        ),
      ),
    ],
  );
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool rounded;
  final Color bg;
  final Color border;
  final Color iconColor;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.bg,
    required this.border,
    required this.iconColor,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: bg,
      borderRadius: rounded ? BorderRadius.circular(12) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: rounded ? BorderRadius.circular(12) : null,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: iconColor),
          ),
        ),
      ),
    );

    if (rounded) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: child,
      );
    }
    return child;
  }
}

class _MapTypePanel extends StatefulWidget {
  final bool isDark;
  const _MapTypePanel({this.isDark = false});

  @override
  State<_MapTypePanel> createState() => _MapTypePanelState();
}

class _MapTypePanelState extends State<_MapTypePanel> {
  int _selected = 0;

  final _types = [
    {'icon': Icons.map_outlined, 'label': 'Oddiy', 'type': 'map'},
    {'icon': Icons.satellite_alt_outlined, 'label': 'Yo\'l', 'type': 'satellite'},
    {'icon': Icons.view_in_ar_outlined, 'label': '3D', 'type': '3d'},
  ];

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? AppTheme.darkSurface : Colors.white;
    final border = widget.isDark ? AppTheme.darkBorder : AppTheme.borderColor;
    final activeColor = AppTheme.primaryColor;
    final inactiveColor = widget.isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: List.generate(_types.length, (i) {
          final t = _types[i];
          final isActive = _selected == i;
          return Column(
            children: [
              if (i > 0) Container(height: 0.5, color: border),
              Material(
                color: isActive ? activeColor.withOpacity(0.1) : bg,
                borderRadius: i == 0
                    ? const BorderRadius.vertical(top: Radius.circular(12))
                    : i == _types.length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(12))
                        : BorderRadius.zero,
                child: InkWell(
                  onTap: () {
                    setState(() => _selected = i);
                    js.context.callMethod('setMapType', [t['type']]);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(t['icon'] as IconData, size: 18,
                        color: isActive ? activeColor : inactiveColor),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}