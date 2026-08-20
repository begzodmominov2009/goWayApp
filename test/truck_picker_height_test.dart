// order_form_modal.dart dagi _TruckPickerSheet ro'yxati balandligi haqida
// IKKI bosqichli tarix:
//
// 1) Avval `ListView.separated(shrinkWrap: true, ...)`, `ConstrainedBox(
//    maxHeight: ekran*0.5)` ichida edi.
// 2) Keyin shrinkWrap: true "taxminiy" `_kTruckRowHeight = 48.0`
//    konstantasi asosida HISOBLANGAN `SizedBox(height: ...)` bilan
//    almashtirilgan edi (har bir qator SizedBox(height: 48) ichiga
//    qattiq o'ralib).
// 3) BU TEST FAYLI aynan shu (2)-yondashuvni tekshirib, uni RAD ETGAN:
//    vidjet testi bilan o'lchov ko'rsatdiki, foydalanuvchi shrift
//    o'lchamini kattalashtirsa (MediaQuery textScaler — Android/iOS'ning
//    "Katta matn" ostirilma sozlamasi, keng tarqalgan, 1.3x-2.0x oralig'i),
//    qatordagi matn ustuni 48px'dan OSHIB KETADI va RenderFlex OVERFLOW
//    (sariq-qora chiziqlar) yuzaga keladi — bu taxminiy balandlikning kam
//    chiqishidan (kutilmagan scroll) ko'ra YOMONROQ ko'rinish nuqsoni.
//    Shu sabab order_form_modal.dart (1)-holatga QAYTARILDI:
//    shrinkWrap: true — bu HAR QANDAY shrift o'lchamida (istalgan
//    textScaler'da) qatorning HAQIQIY balandligini o'zi to'g'ri
//    hisoblaydi, hech qachon kesilmaydi.
//
// _TruckPickerSheet order_form_modal.dart ichida fayl-private, shuning
// uchun bu test AYNAN o'sha ikkala yondashuvni (shrinkWrap vs qattiq
// SizedBox) mustaqil reproduksiyada, bir xil widget daraxti bilan
// solishtiradi — nega shrinkWrap tanlanganini KOD DARAJASIDA isbotlaydi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _rowHeight = 48.0;
const double _rowSpacing = 10.0;

Widget _truckRow(int i) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 22, height: 22, color: Colors.blue),
        const SizedBox(width: 16),
        Container(width: 48, height: 48, color: Colors.green),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mashina turi $i',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              const Text('12.0 t', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );

/// order_form_modal.dart dagi HOZIRGI (yakuniy, shrinkWrap: true bilan)
/// naqsh — har qator o'z tabiiy (shrift o'lchamiga moslashuvchi)
/// balandligida.
Widget _shrinkWrapList(int count, double maxHeight) {
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: ListView.separated(
      shrinkWrap: true,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: _rowSpacing),
      itemBuilder: (ctx, i) => _truckRow(i),
    ),
  );
}

/// RAD ETILGAN naqsh (taqqoslash uchun saqlanadi) — har qator qattiq
/// SizedBox(height: 48) ichiga o'ralgan.
Widget _fixedHeightList(int count, double maxHeight) {
  final contentHeight = count == 0 ? 0.0 : count * _rowHeight + (count - 1) * _rowSpacing;
  final listHeight = contentHeight < maxHeight ? contentHeight : maxHeight;
  return SizedBox(
    height: listHeight,
    child: ListView.separated(
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: _rowSpacing),
      itemBuilder: (ctx, i) => SizedBox(height: _rowHeight, child: _truckRow(i)),
    ),
  );
}

Future<FlutterError?> _pumpAndCaptureOverflow(
  WidgetTester tester, Widget child, double textScale,
) async {
  FlutterError? caught;
  final original = FlutterError.onError;
  FlutterError.onError = (details) => caught ??= details.exception as FlutterError;

  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: child))),
  ));
  await tester.pump();

  FlutterError.onError = original;
  return caught;
}

void main() {
  const maxHeight = 400.0;

  testWidgets('shrinkWrap: true — oddiy shrift o\'lchamida (1.0x) overflow YO\'Q, kam elementda kontent balandligi',
      (tester) async {
    final key = GlobalKey();
    final error = await _pumpAndCaptureOverflow(
      tester, KeyedSubtree(key: key, child: _shrinkWrapList(3, maxHeight)), 1.0,
    );
    expect(error, isNull, reason: 'oddiy shrift o\'lchamida overflow bo\'lmasligi kerak');

    final renderedHeight = tester.getSize(find.byKey(key)).height;
    expect(renderedHeight, lessThan(maxHeight),
        reason: 'kam elementda ro\'yxat har doim maxHeight (400px) EMAS, kontent balandligida bo\'lishi kerak');
  });

  testWidgets(
    'shrinkWrap: true — KATTA shrift o\'lchamida (2.0x, "Katta matn" sozlamasi) HAM overflow YO\'Q',
    (tester) async {
      final error = await _pumpAndCaptureOverflow(tester, _shrinkWrapList(3, maxHeight), 2.0);
      expect(error, isNull,
          reason: 'shrinkWrap: true qatorning HAQIQIY balandligini o\'zi hisoblagani uchun '
              'shrift qanchalik kattalashsa ham matn kesilib qolmasligi kerak');
    },
  );

  testWidgets(
    'QARSHI-MISOL (RAD ETILGAN yondashuv): qattiq SizedBox(height: 48) KATTA shrift o\'lchamida OVERFLOW beradi',
    (tester) async {
      final error = await _pumpAndCaptureOverflow(tester, _fixedHeightList(3, maxHeight), 2.0);
      expect(error, isNotNull,
          reason: 'bu naqsh ATAYLAB RAD ETILGAN — aynan shuning uchun ham order_form_modal.dart '
              'shrinkWrap: true ga qaytarildi (taxminiy konstantaga tayanish xavfli edi)');
      expect(error.toString(), contains('overflowed'));
    },
  );

  testWidgets('shrinkWrap: true — KO\'P elementda (50 ta) ro\'yxat maxHeight\'da to\'xtaydi',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: KeyedSubtree(key: key, child: _shrinkWrapList(50, maxHeight)))),
    ));
    await tester.pumpAndSettle();

    final renderedHeight = tester.getSize(find.byKey(key)).height;
    expect(renderedHeight, maxHeight,
        reason: 'ko\'p elementda ro\'yxat maxHeight (50% ekran) dan oshmasligi kerak (ichida scroll bo\'ladi)');
  });
}
