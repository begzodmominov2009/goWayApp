// order_form_modal.dart dagi _buildSuggestions() (manzil qidiruv modali —
// "Saqlangan manzillar" + "Qidiruv tarixi") ilgari
// `ListView(children: [...savedAddresses.map(...), ..._history.map(...)])`
// bilan qurilgan edi — bu N ta elementning HAMMASINI (ko'rinmaydiganlarini
// ham) darhol quradi. Endi `CustomScrollView` + `SliverList.builder`ga
// o'tkazildi (xuddi shu faylda), bu esa faqat ko'rinadigan elementlarni
// quradi.
//
// `_AddressResultTile`/`_buildSuggestions` order_form_modal.dart ichida
// PRIVATE (`_` prefiksli) — Dart'da bu FAYLGA xos maxfiylik, shuning uchun
// bu tashqi test faylidan ularni to'g'ridan-to'g'ri import qilib
// o'lchab bo'lmaydi. Shu sabab bu test production widget'ning O'ZINI
// emas, xuddi shu STRUKTURAVIY NAQSHNI (eager ListView.children vs lazy
// SliverList.builder) alohida, minimal reproduksiyada o'lchaydi — bir xil
// item soni, bir xil viewport balandligi, itemBuilder chaqirilganda
// hisoblagich oshiriladi. Bu mexanizmning o'zini (necha item quriladi)
// aniq va tekshiriladigan tarzda ko'rsatadi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _buildCount = 0;

Widget _row(int i) {
  _buildCount++;
  return SizedBox(key: ValueKey(i), height: 40, child: Text('item $i'));
}

/// "OLDIN" — order_form_modal.dart dagi eski _buildSuggestions() bilan bir
/// xil naqsh: ListView(children: [...list.map((i) => _row(i))]).
Widget _eagerListBefore(int count) {
  return ListView(
    padding: EdgeInsets.zero,
    children: [for (final i in List.generate(count, (i) => i)) _row(i)],
  );
}

/// "KEYIN" — order_form_modal.dart dagi yangi _buildSuggestions() bilan bir
/// xil naqsh: CustomScrollView + SliverList.builder.
Widget _lazySliverAfter(int count) {
  return CustomScrollView(
    slivers: [
      SliverList.builder(
        itemCount: count,
        itemBuilder: (ctx, i) => _row(i),
      ),
    ],
  );
}

void main() {
  const itemCount = 50;
  const viewportHeight = 600.0; // ~40px/item => taxminan 15 ta ko'rinadi

  Widget harness(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(height: viewportHeight, child: child),
        ),
      );

  testWidgets('BEFORE: eager ListView(children:) builds ALL $itemCount items even off-screen',
      (tester) async {
    _buildCount = 0;
    await tester.pumpWidget(harness(_eagerListBefore(itemCount)));
    await tester.pumpAndSettle();

    // eslint-disable-next-line: hisobot uchun konsolga chiqaramiz.
    // ignore: avoid_print
    print('BEFORE (eager ListView.children) — built widgets for $itemCount items: $_buildCount');
    expect(_buildCount, itemCount,
        reason: 'eager ListView.children barcha elementlarni, ko\'rinmaydiganlarini ham, darhol quradi');
  });

  testWidgets('AFTER: lazy SliverList.builder builds only the visible subset of $itemCount items',
      (tester) async {
    _buildCount = 0;
    await tester.pumpWidget(harness(_lazySliverAfter(itemCount)));
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('AFTER (SliverList.builder) — built widgets for $itemCount items: $_buildCount');
    expect(_buildCount, lessThan(itemCount),
        reason: 'lazy SliverList.builder faqat ko\'rinadigan elementlarni qurishi kerak');
    // Taxminan 15 ta ko'rinadi (600px / 40px), Flutter bir oz kengroq
    // "cacheExtent" bilan atrofdagilarni ham oldindan quradi — shuning
    // uchun aniq songa emas, YUQORI CHEGARAGA tekshiramiz.
    expect(_buildCount, lessThanOrEqualTo(25));
  });
}
