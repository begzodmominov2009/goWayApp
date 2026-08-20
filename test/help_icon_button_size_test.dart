// order_form_modal.dart dagi "Mashina turini tanlang"/"Yuk og'irligi"/
// "Yuklash turi"/"Qachon" sarlavhalarida "?" IconButton bor, "Yuk turi"da
// yo'q — foydalanuvchi shu ikkalasi orasidagi sarlavha->input oralig'ini
// har xil deb sezgan edi, garchi ikkalasida ham bir xil SizedBox(height: 6)
// ishlatilgan bo'lsa ham.
//
// Sabab: Material 3'da IconButton'ga `padding: EdgeInsets.zero` +
// `constraints: BoxConstraints()` berilsa ham, u platforma standart
// teginish maydoni (48x48, `MaterialTapTargetSize.padded`, ThemeData
// standart qiymati) uchun KO'RINMAS qo'shimcha joy ajratishda davom etadi
// — bu joy Row'ning cross-axis balandligiga ta'sir qiladi, garchi hech
// narsa chizilmasa ham. Natijada "?" bor sarlavha qatori 48px, "?" siz
// qator esa faqat matn balandligi (~17px) bo'lib chiqadi.
//
// Tuzatish: IconButton'ga `style: IconButton.styleFrom(tapTargetSize:
// MaterialTapTargetSize.shrinkWrap)` qo'shildi — bu ko'rinmas paddingni
// olib tashlaydi; bosish maydoni `constraints: BoxConstraints(minWidth:
// 32, minHeight: 32)` bilan qulay saqlanadi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _titleRow({required bool fixed}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Mashina turini tanlang',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.help_outline, size: 16),
          padding: EdgeInsets.zero,
          constraints: fixed ? const BoxConstraints(minWidth: 32, minHeight: 32) : const BoxConstraints(),
          style: fixed ? IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap) : null,
          onPressed: () {},
        ),
      ],
    );

const Widget _plainTitleRow = Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text('Yuk turi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
  ],
);

Future<double> _rowHeight(WidgetTester tester, Widget row) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: KeyedSubtree(key: key, child: row))),
  ));
  return tester.getSize(find.byKey(key)).height;
}

void main() {
  testWidgets('REGRESSION (documents the framework gotcha): unfixed "?" IconButton row balloons to 48px',
      (tester) async {
    final iconHeight = await _rowHeight(tester, _titleRow(fixed: false));
    final plainHeight = await _rowHeight(tester, _plainTitleRow);

    expect(iconHeight, 48.0,
        reason: 'Material 3 IconButton — padding:zero + constraints:BoxConstraints() berilsa ham, '
            'MaterialTapTargetSize.padded tufayli 48px min hit-target saqlanadi.');
    expect(iconHeight - plainHeight, greaterThan(25),
        reason: 'shu ko\'rinmas padding aynan foydalanuvchi sezgan katta oraliqni keltirib chiqargan');
  });

  testWidgets('FIX: tapTargetSize.shrinkWrap + constraints(min 32) shrinks the row while staying tappable',
      (tester) async {
    final fixedHeight = await _rowHeight(tester, _titleRow(fixed: true));
    final plainHeight = await _rowHeight(tester, _plainTitleRow);

    expect(fixedHeight, lessThan(40),
        reason: 'tuzatilgandan keyin qator balandligi 48px dan sezilarli kichik bo\'lishi kerak');
    expect(fixedHeight, greaterThanOrEqualTo(32),
        reason: 'bosish maydoni kamida 32x32 (barmoq bilan qulay bosish uchun) saqlanishi kerak');
    expect(fixedHeight - plainHeight, lessThan(20),
        reason: '"?" bor va yo\'q sarlavhalar orasidagi farq sezilarli kamayishi kerak (avval 31px edi)');
  });
}
