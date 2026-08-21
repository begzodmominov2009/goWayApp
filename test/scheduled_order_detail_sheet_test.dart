// client_scheduled_orders_screen.dart dagi _ClientOrderDetailSheet va
// _DetailRow FAYL-PRIVATE (leading underscore) — Dart'da bunday klasslarga
// boshqa fayldan (shu jumladan test fayllaridan) TO'G'RIDAN-TO'G'RI kirish
// mumkin emas. Shuning uchun bu fayl, loyihada allaqachon o'rnashgan naqshga
// mos (masalan truck_picker_height_test.dart, map_picker_reactive_scope_test.dart),
// AYNAN o'sha ikkita texnikani MUSTAQIL, mexanizm darajasida takrorlaydi va
// tekshiradi:
//
//   1-band: ConstrainedBox(maxHeight) + Column(mainAxisSize:min,
//     [qattiq sarlavha, Flexible(SingleChildScrollView(qatorlar)),
//     qattiq "Bekor qilish" tugmasi]) — turli ekran balandliklarida
//     overflow YO'Qligini va tugma DOIM ko'rinishini isbotlaydi.
//
//   3-band: TextPainter(maxLines:1)..layout(maxWidth)..didExceedMaxLines —
//     "ko'z" ikonkasi ko'rsatish qarori uchun ishlatiladigan HAQIQIY
//     o'lchov texnikasi — belgilangan uzunlik taxminiga EMAS.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// client_scheduled_orders_screen.dart._ClientOrderDetailSheetState.build()
// dagi bilan AYNAN bir xil qobiq: ConstrainedBox(maxHeight: 0.9*ekran) ->
// Container -> Column(mainAxisSize:min, [qattiq header, Flexible(scroll),
// qattiq footer]).
const _kShellKey = Key('detail_sheet_shell');

class _DetailSheetShell extends StatelessWidget {
  final int rowCount;
  final Key footerKey;
  const _DetailSheetShell({required this.rowCount, required this.footerKey});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        key: _kShellKey,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 64, color: Colors.grey, child: const Text('header')), // qattiq sarlavha
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(
                      rowCount,
                      (i) => Container(height: 60, margin: const EdgeInsets.only(bottom: 12), color: Colors.blue[(i % 9 + 1) * 100]),
                    ),
                  ),
                ),
              ),
              Container(key: footerKey, height: 56, color: Colors.red, child: const Text('Bekor qilish')), // qattiq footer
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpAtHeight(WidgetTester tester, {required double height, required int rowCount, required Key footerKey}) async {
  await tester.binding.setSurfaceSize(Size(400, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(400, height)),
      child: _DetailSheetShell(rowCount: rowCount, footerKey: footerKey),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('1-band: ConstrainedBox(maxHeight) + Flexible scroll shell', () {
    testWidgets('QISQA balandlikda (568dp, kichik telefon) KO\'P qator bo\'lsa ham overflow YO\'Q, footer ko\'rinadi', (tester) async {
      const footerKey = Key('footer');
      await _pumpAtHeight(tester, height: 568, rowCount: 10, footerKey: footerKey);

      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow yoki boshqa render xatosi bo\'lmasligi kerak');
      expect(find.byKey(footerKey), findsOneWidget, reason: '"Bekor qilish" tugmasi HAR DOIM daraxtda bo\'lishi kerak (scroll ichida emas)');

      // Footer'ning pastki chegarasi ekran balandligidan oshmasligi kerak —
      // ya'ni u chindan HAM ko'rinadigan hududda, ekrandan tashqarida emas.
      final footerBottom = tester.getBottomLeft(find.byKey(footerKey)).dy;
      expect(footerBottom, lessThanOrEqualTo(568.5));
    });

    testWidgets('BALAND ekranda (900dp) HAM overflow YO\'Q, footer ko\'rinadi', (tester) async {
      const footerKey = Key('footer');
      await _pumpAtHeight(tester, height: 900, rowCount: 10, footerKey: footerKey);

      expect(tester.takeException(), isNull);
      expect(find.byKey(footerKey), findsOneWidget);
    });

    testWidgets('QISQA mazmunda (2 ta qator) sheet balandligi maxHeight chegarasidan KICHIK bo\'ladi — ortiqcha bo\'sh joy/"sakrash" yo\'q', (tester) async {
      const footerKey = Key('footer');
      const screenHeight = 800.0;
      await _pumpAtHeight(tester, height: screenHeight, rowCount: 2, footerKey: footerKey);

      expect(tester.takeException(), isNull);
      final renderedHeight = tester.getSize(find.byKey(_kShellKey)).height;
      // 2 ta qator (60+12 balandlikda) + header(64) + footer(56) — bu
      // aniq maxHeight (800*0.9=720) dan ANCHA kichik bo'lishi kerak —
      // ya'ni Column FractionallySizedBox kabi majburiy to'liq
      // cho'zilmagan, kontentga qarab qisqargan (mainAxisSize.min +
      // Flexible, Expanded EMAS, natijasi).
      expect(renderedHeight, lessThan(screenHeight * 0.9),
          reason: 'qisqa mazmunda konteyner maksimal chegaragacha cho\'zilmasligi kerak');
    });

    testWidgets('KO\'P qator (20 ta) bo\'lsa sheet aynan maxHeight chegarasida to\'xtaydi (scroll ichida qoladi)', (tester) async {
      const footerKey = Key('footer');
      const screenHeight = 800.0;
      await _pumpAtHeight(tester, height: screenHeight, rowCount: 20, footerKey: footerKey);

      expect(tester.takeException(), isNull);
      final renderedHeight = tester.getSize(find.byKey(_kShellKey)).height;
      expect(renderedHeight, closeTo(screenHeight * 0.9, 0.5));
    });
  });

  group('3-band: TextPainter(maxLines:1)-based haqiqiy qisqarish o\'lchovi ("ko\'z" ikonkasi qarori)', () {
    // _DetailRow._isTruncated() dagi bilan AYNAN bir xil texnika.
    bool isTruncated(String text, TextStyle style, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      return painter.didExceedMaxLines;
    }

    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

    test('QISQA matn, KENG joy — qisqarmaydi, "ko\'z" ko\'rinmasligi kerak', () {
      expect(isTruncated('19:03', style, 200), isFalse);
    });

    test('UZUN matn (to\'liq manzil), TOR joy — qisqaradi, "ko\'z" ko\'rinishi kerak', () {
      const longAddress = "O'zbekiston, Farg'ona viloyati, Toshloq tumani, Jorqishloq mahallasi, Mustaqillik ko'chasi 128-uy";
      expect(isTruncated(longAddress, style, 120), isTrue);
    });

    test('BIR XIL uzun matn, LEKIN yetarlicha KENG joy berilsa — qisqarmaydi', () {
      const text = 'ISUZI_TENT_5T';
      expect(isTruncated(text, style, 500), isFalse);
    });

    test('chegaradagi holat: matn aynan sig\'adigan kenglikda — qisqarmaydi, biroz torroqda — qisqaradi', () {
      const text = 'Toshkent shahri';
      final painter = TextPainter(
        text: const TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final naturalWidth = painter.width;

      expect(isTruncated(text, style, naturalWidth + 5), isFalse, reason: 'tabiiy kenglikdan katta joyda qisqarmasligi kerak');
      expect(isTruncated(text, style, naturalWidth * 0.5), isTrue, reason: 'tabiiy kenglikning yarmida albatta qisqarishi kerak');
    });
  });
}
