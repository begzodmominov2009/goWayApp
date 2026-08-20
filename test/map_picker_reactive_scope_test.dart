// map_address_picker.dart (_MapAddressPickerState) da setState() o'rniga
// ValueNotifier + ValueListenableBuilder ishlatilishining ikki jihatini
// tekshiradi:
//
// 1) REBUILD QAMROVI (4-band): avval kamera harakati (yoki qidiruv
//    matni) HAR o'zgarganda BUTUN ekran (jumladan YandexMap joylashgan
//    daraxt) qayta qurilardi (setState() shu Statega tegishli BARCHA
//    build()ni qayta ishga tushiradi). Endi faqat tegishli kichik
//    subtree (pin YOKI panel) qayta quriladi.
//
// 2) PANEL SHAFFOFLIGI MANTIG'I (2-band, ENG MUHIM): kamera
//    onCameraPositionChanged(reason, finished) chaqiruvidan qanday
//    shaffoflik qarori chiqarilishi — reason==gestures && !finished bo'lsa
//    shaffof, finished bo'lsa (har qanday reason'da) darhol shaffof emas,
//    reason==application && !finished bo'lsa (masalan "o'zini topish"
//    tugmasi bosilgan kamera animatsiyasi) shaffof BO'LMASLIGI kerak.
//
// _MapAddressPickerState fayl-private (YandexMap platform-view talab
// qilgani uchun uni to'g'ridan-to'g'ri vidjet testida ishga tushirish
// ham amaliy emas — platform kanal mock qilishni talab qiladi). Shuning
// uchun bu test map_address_picker.dart dagi bilan AYNAN bir xil
// naqshni (ValueNotifier + ValueListenableBuilder, xuddi shu shaffoflik
// qarori formulasi) mustaqil, YandexMap'siz reproduksiyada tekshiradi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Reason { gestures, application }

// map_address_picker.dart._onCameraPositionChanged() dagi bilan AYNAN
// bir xil qaror formulasi.
bool? _panelTransparencyDecision({required _Reason reason, required bool finished, required bool? previous}) {
  if (!finished) {
    if (reason == _Reason.gestures) return true;
    return previous; // application && !finished => o'zgarishsiz qoladi
  }
  return false; // finished => har doim (har qanday reason'da) darhol false
}

void main() {
  group('2-band: panel shaffoflik qarori formulasi', () {
    test('gestures + !finished => shaffof (true)', () {
      expect(_panelTransparencyDecision(reason: _Reason.gestures, finished: false, previous: false), isTrue);
    });

    test('finished (gestures bilan boshlangan bo\'lsa ham) => darhol shaffof EMAS', () {
      expect(_panelTransparencyDecision(reason: _Reason.gestures, finished: true, previous: true), isFalse);
    });

    test('application + !finished ("o\'zini topish" tugmasi) => o\'zgarmaydi, shaffof BO\'LMAYDI', () {
      expect(_panelTransparencyDecision(reason: _Reason.application, finished: false, previous: false), isFalse);
    });

    test('application + finished => shaffof EMAS (allaqachon false, o\'zgarishsiz)', () {
      expect(_panelTransparencyDecision(reason: _Reason.application, finished: true, previous: false), isFalse);
    });
  });

  group('4-band: rebuild qamrovi — OLDIN (setState, butun subtree) vs KEYIN (ValueNotifier, faqat tegishli qism)', () {
    testWidgets('OLDIN naqsh: bitta setState() MAP + PIN + PANEL uchtalasini ham qayta quradi', (tester) async {
      int mapBuilds = 0, pinBuilds = 0, panelBuilds = 0;
      late VoidCallback triggerCameraMove;

      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            mapBuilds++;
            pinBuilds++;
            panelBuilds++;
            triggerCameraMove = () => setState(() {});
            return const SizedBox();
          },
        ),
      ));
      expect(mapBuilds, 1);
      expect(pinBuilds, 1);
      expect(panelBuilds, 1);

      for (var i = 0; i < 5; i++) {
        triggerCameraMove();
        await tester.pump();
      }

      // ignore: avoid_print
      print('OLDIN (setState): 5 ta kamera-kadr yangilanishidan keyin — '
          'map: $mapBuilds, pin: $pinBuilds, panel: $panelBuilds (hammasi birga o\'sadi)');
      expect(mapBuilds, 6, reason: 'YandexMap joylashgan daraxt HAM qayta qurilgan bo\'lardi');
      expect(pinBuilds, 6);
      expect(panelBuilds, 6, reason: 'pastdagi panel HAM aloqasi yo\'q sababdan qayta qurilgan bo\'lardi');
    });

    testWidgets('KEYIN naqsh: ValueNotifier faqat PIN subtree\'ni qayta quradi, MAP/PANEL tegilmaydi',
        (tester) async {
      int outerBuilds = 0, pinBuilds = 0, panelBuilds = 0;
      final cameraMovingNotifier = ValueNotifier<bool>(false);
      addTearDown(cameraMovingNotifier.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          outerBuilds++; // YandexMap shu darajada e'lon qilinadi — endi kamdan-kam ishlaydi
          return Column(children: [
            ValueListenableBuilder<bool>(
              valueListenable: cameraMovingNotifier,
              builder: (context, moving, _) {
                pinBuilds++;
                return const SizedBox();
              },
            ),
            Builder(builder: (context) {
              panelBuilds++; // pastdagi panel — kamera harakatiga ALOQASI yo'q
              return const SizedBox();
            }),
          ]);
        }),
      ));
      expect(outerBuilds, 1);
      expect(pinBuilds, 1);
      expect(panelBuilds, 1);

      for (var i = 0; i < 5; i++) {
        cameraMovingNotifier.value = !cameraMovingNotifier.value;
        await tester.pump();
      }

      // ignore: avoid_print
      print('KEYIN (ValueNotifier): 5 ta kamera-kadr yangilanishidan keyin — '
          'outer(map joylashgan): $outerBuilds, pin: $pinBuilds, panel: $panelBuilds');
      expect(outerBuilds, 1, reason: 'tashqi build (YandexMap shu yerda) UMUMAN qayta ishlamadi');
      expect(pinBuilds, 6, reason: 'faqat pin subtree\'si ValueNotifier orqali yangilandi');
      expect(panelBuilds, 1, reason: 'panel kamera harakatiga aloqasi yo\'q, tegilmadi');
    });
  });
}
