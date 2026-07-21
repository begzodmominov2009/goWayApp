import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

/// Yandex/Uber uslubidagi "pin" (tomchi shaklidagi belgi) yaratadi.
/// Barcha pinlar YUQORI RESOLUTSIYADA (3x) chiziladi, keyin xaritada
/// kichikroq scale bilan ko'rsatiladi — natijada tiniq, xira bo'lmagan
/// ikonka olinadi (past piksel zichligida chizib, kattalashtirilsa
/// xira ko'rinar edi).
///
/// Barcha pinlar ILOVA ISHGA TUSHGANDA, BIR MARTA (preloadAll orqali)
/// tayyorlanadi va statik o'zgaruvchilarda saqlanadi (runtime kesh —
/// shu SESSIYA davomida qayta chizilmaydi).
///
/// Bundan tashqari, tayyor PNG baytlar shared_preferences'ga (disk)
/// ham saqlanadi — ilova YOPILIB QAYTA OCHILGANDA ham, og'ir chizish/
/// rasterizatsiya jarayoni (Canvas -> Image -> PNG encode) QAYTARILMAYDI,
/// buning o'rniga saqlangan baytlar to'g'ridan-to'g'ri o'qiladi (tezkor
/// base64 decode, chizish yo'q). `path_provider` paketi loyihada yo'qligi
/// sabab, fayl tizimiga (disk faylga) emas, shared_preferences orqali
/// (u ham diskka yozadi — Android'da XML, iOS'da plist) saqlanadi.
class MapIconHelper {
  static final Map<String, BitmapDescriptor> _cache = {};

  // Har bir pin nomi bo'yicha, ENDIGINA chizilgan (yoki diskdan o'qilgan)
  // PNG baytlar — disk keshiga yozish uchun ishlatiladi.
  static final Map<String, Uint8List> _pngBytes = {};

  // Yuqori resolutsiya koeffitsienti — chizishda ishlatiladi, keyin
  // xaritada shunga mos ravishda kichikroq scale beriladi (masalan
  // resolutsiya 3x bo'lsa, scale ham ~3x kichraytiriladi)
  static const double _resolutionMultiplier = 3.0;

  static BitmapDescriptor? truckIconReady;
  static BitmapDescriptor? finishIconReady;
  static BitmapDescriptor? driverIconReady;
  static BitmapDescriptor? myLocationIconReady;
  static bool _preloaded = false;
  static bool get isPreloaded => _preloaded;

  // Disk-kesh versiyasi — pin chizish mantig'i (rang/shakl/o'lcham)
  // o'zgarsa, bu qiymatni oshirib, eski (mos kelmaydigan) saqlangan
  // baytlarni avtomatik bekor qilish mumkin.
  static const String _diskCacheVersion = 'v1';
  static const String _doneKey = 'map_icons_preloaded_$_diskCacheVersion';
  static const String _truckDiskKey = 'map_icon_truck_$_diskCacheVersion';
  static const String _finishDiskKey = 'map_icon_finish_$_diskCacheVersion';
  static const String _driverDiskKey = 'map_icon_driver_$_diskCacheVersion';
  static const String _myLocationDiskKey = 'map_icon_myloc_$_diskCacheVersion';

  /// Ilova ishga tushganda (main.dart'da) BIR MARTA chaqiriladi.
  static Future<void> preloadAll() async {
    if (_preloaded) return;

    // Avval disk keshini tekshiramiz — agar avvalgi ishga tushirishda
    // muvaffaqiyatli saqlangan bo'lsa, og'ir chizish jarayoni UMUMAN
    // ishlamaydi, faqat tezkor base64-decode qilinadi.
    if (await _tryLoadFromDisk()) {
      _preloaded = true;
      return;
    }

    final results = await Future.wait([
      truckPin(),
      finishPin(),
      driverPin(),
      myLocationDot(),
    ]);
    truckIconReady = results[0];
    finishIconReady = results[1];
    driverIconReady = results[2];
    myLocationIconReady = results[3];
    _preloaded = true;

    // Keyingi safar (ilova qayta ochilganda) og'ir chizish jarayonini
    // takrorlamaslik uchun, tayyor PNG baytlarni diskka (shared_preferences)
    // saqlaymiz. Xato bo'lsa ham muhim emas — keyingi safar oddiy chizish
    // jarayoniga qaytiladi.
    await _saveToDisk();
  }

  static Future<bool> _tryLoadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_doneKey) != true) return false;

      final truckB64 = prefs.getString(_truckDiskKey);
      final finishB64 = prefs.getString(_finishDiskKey);
      final driverB64 = prefs.getString(_driverDiskKey);
      final myLocB64 = prefs.getString(_myLocationDiskKey);
      if (truckB64 == null || finishB64 == null || driverB64 == null || myLocB64 == null) {
        return false;
      }

      truckIconReady = BitmapDescriptor.fromBytes(base64Decode(truckB64));
      finishIconReady = BitmapDescriptor.fromBytes(base64Decode(finishB64));
      driverIconReady = BitmapDescriptor.fromBytes(base64Decode(driverB64));
      myLocationIconReady = BitmapDescriptor.fromBytes(base64Decode(myLocB64));
      return true;
    } catch (_) {
      // Saqlangan ma'lumot buzilgan/mos emas — pastda oddiy chizish
      // jarayoniga o'tiladi (o'zini-o'zi tuzatish).
      return false;
    }
  }

  static Future<void> _saveToDisk() async {
    final truckBytes = _pngBytes['truck'];
    final finishBytes = _pngBytes['finish'];
    final driverBytes = _pngBytes['driver'];
    final myLocBytes = _pngBytes['myLocation'];
    if (truckBytes == null || finishBytes == null || driverBytes == null || myLocBytes == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_truckDiskKey, base64Encode(truckBytes)),
        prefs.setString(_finishDiskKey, base64Encode(finishBytes)),
        prefs.setString(_driverDiskKey, base64Encode(driverBytes)),
        prefs.setString(_myLocationDiskKey, base64Encode(myLocBytes)),
      ]);
      await prefs.setBool(_doneKey, true);
    } catch (_) {}
  }

  /// Pin chizadi — logikaviy o'lcham (masalan 180) beriladi, lekin
  /// ichida _resolutionMultiplier orqali yuqori piksel zichligida
  /// chiziladi (tiniqlik uchun).
  static Future<BitmapDescriptor> buildPin({
    required IconData icon,
    required Color color,
    double size = 180,
    // Berilsa — chizilgan PNG baytlar _pngBytes[name] ga saqlanadi (disk
    // keshiga yozish uchun, preloadAll._saveToDisk() shundan o'qiydi).
    String? name,
  }) async {
    final cacheKey = 'pin_${icon.codePoint}_${color.value}_$size';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final logicalWidth = size;
    final logicalHeight = size * 1.3;
    final width = logicalWidth * _resolutionMultiplier;
    final height = logicalHeight * _resolutionMultiplier;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_resolutionMultiplier);

    final circleRadius = logicalWidth / 2 * 0.85;
    final circleCenter = Offset(logicalWidth / 2, circleRadius + logicalWidth * 0.05);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    canvas.drawCircle(circleCenter.translate(0, 5), circleRadius, shadowPaint);

    final tailPath = Path();
    final tailWidth = logicalWidth * 0.24;
    tailPath.moveTo(circleCenter.dx - tailWidth / 2, circleCenter.dy + circleRadius * 0.5);
    tailPath.lineTo(circleCenter.dx, logicalHeight - logicalWidth * 0.02);
    tailPath.lineTo(circleCenter.dx + tailWidth / 2, circleCenter.dy + circleRadius * 0.5);
    tailPath.close();
    canvas.drawPath(tailPath, Paint()..color = color);

    canvas.drawCircle(circleCenter, circleRadius, Paint()..color = color);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = logicalWidth * 0.05;
    canvas.drawCircle(circleCenter, circleRadius - logicalWidth * 0.025, borderPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: circleRadius * 1.1,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(circleCenter.dx - textPainter.width / 2, circleCenter.dy - textPainter.height / 2),
    );

    canvas.drawCircle(
      Offset(circleCenter.dx, logicalHeight - logicalWidth * 0.02),
      logicalWidth * 0.018,
      Paint()..color = color,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    if (name != null) _pngBytes[name] = bytes;

    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _cache[cacheKey] = descriptor;
    return descriptor;
  }

  static Future<BitmapDescriptor> truckPin() =>
      buildPin(icon: Icons.local_shipping, color: const Color(0xFF2563EB), size: 200, name: 'truck');

  static Future<BitmapDescriptor> finishPin() =>
      buildPin(icon: Icons.flag, color: const Color(0xFF059669), size: 200, name: 'finish');

  static Future<BitmapDescriptor> driverPin() =>
      buildPin(icon: Icons.local_shipping, color: const Color(0xFF1E3A8A), size: 190, name: 'driver');

  /// "O'zim turgan joyim" belgisi — endi Google Maps uslubidagi
  /// aniq, katta, yuqori kontrastli ikonka (joylashuv strelkasi bilan,
  /// oddiy ko'k nuqta emas — ko'rish osonroq bo'lishi uchun).
  static Future<BitmapDescriptor> myLocationDot({double size = 160}) async {
    final cacheKey = 'my_loc_v3_$size';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final logicalSize = size;
    final pixelSize = logicalSize * _resolutionMultiplier;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_resolutionMultiplier);

    final radius = logicalSize / 2;
    const color = Color(0xFF2563EB);

    // Tashqi yorqin porlash halqasi — ko'zga tashlanishi uchun kattaroq
    final glowPaint = Paint()
      ..color = color.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12);
    canvas.drawCircle(Offset(radius, radius), radius * 0.95, glowPaint);

    // Soya
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);
    canvas.drawCircle(Offset(radius, radius + 3), radius * 0.5, shadowPaint);

    // Oq tashqi doira — kontrast uchun
    canvas.drawCircle(Offset(radius, radius), radius * 0.52, Paint()..color = Colors.white);

    // Ichki to'liq quyuq ko'k doira
    canvas.drawCircle(Offset(radius, radius), radius * 0.42, Paint()..color = color);

    // Markazda kichik oq nuqta — yo'nalish/aniqlik hissi beradi
    canvas.drawCircle(Offset(radius, radius), radius * 0.12, Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize.toInt(), pixelSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    _pngBytes['myLocation'] = bytes;

    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _cache[cacheKey] = descriptor;
    return descriptor;
  }
}