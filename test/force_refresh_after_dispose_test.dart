// order_form_modal.dart dagi _AddressSearchModalState._selectPlace() da
// topilgan nuqson: fon rejimidagi (unawaited) tarmoq so'rovi tugagach
// keshni forceRefresh() qilish, `ref.read(...)` ni `.then()` ICHIDA,
// `mounted` tekshiruvi bilan chaqirardi. Lekin shu metoddan DARHOL keyin
// `Navigator.pop(context, place)` chaqirilib, modal (widget) yopila
// boshlaydi — agar POST javobi widget haqiqatan dispose bo'lgandan KEYIN
// kelsa, `.then()` ishlaganda `mounted` false bo'lib, forceRefresh() UMUMAN
// chaqirilmay qoladi (tarmoq sekin bo'lsa yoki sheet yopilish animatsiyasi
// tez tugasa — real, lekin bir maromda takrorlanmaydigan/aniqlash qiyin
// bo'lgan poyga sharoiti).
//
// Tuzatish: notifier ASYNC chaqiruvdan OLDIN (hali widget mounted paytida)
// ushlab olinadi; keyin `mounted` tekshiruvisiz, to'g'ridan-to'g'ri o'sha
// notifier orqali chaqiriladi — notifier ProviderScope'da yashaydi
// (keepAlive), widget dispose bo'lishi unga ta'sir qilmaydi.
//
// Test "widget haqiqatan dispose bo'lgan" holatni ANIQ va DETERMINISTIK
// qilish uchun Navigator/route yopilish animatsiyasiga tayanmaydi (u
// muddat kutish talab qiladi va sinovni beqaror qilardi) — buning o'rniga
// widget'ni daraxtdan to'g'ridan-to'g'ri (tester.pumpWidget bilan boshqa
// tree bilan almashtirib) olib tashlaydi, xuddi Navigator.pop() route'ni
// olib tashlagandagidek State.dispose() chaqiriladi.
//
// _AddressSearchModalState/_selectPlace order_form_modal.dart ichida
// fayl-private, shuning uchun bu test AYNAN o'sha naqshni (XATO va
// TUZATILGAN variant) alohida, mustaqil reproduksiyada — lekin bir xil
// Riverpod mexanizmi (Notifier + ProviderScope + widget dispose) bilan —
// isbotlaydi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CallCounterNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void forceRefresh() => state++;
}

final _counterProvider = NotifierProvider<_CallCounterNotifier, int>(_CallCounterNotifier.new);

/// XATO naqsh (tuzatishdan oldin order_form_modal.dart._selectPlace()):
/// `ref.read(...)` `.then()` ICHIDA, `mounted` (context.mounted) tekshiruvi
/// bilan chaqiriladi.
class _BadPatternWidget extends ConsumerWidget {
  const _BadPatternWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 30)).then((_) {
            // context.mounted — State.mounted bilan bir xil narsa.
            if (context.mounted) {
              ref.read(_counterProvider.notifier).forceRefresh();
            }
          }),
        );
      },
      child: const Text('select'),
    );
  }
}

/// TUZATILGAN naqsh: notifier oldindan ushlab olinadi, mounted tekshiruvi
/// olib tashlanadi.
class _FixedPatternWidget extends ConsumerWidget {
  const _FixedPatternWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        final counterNotifier = ref.read(_counterProvider.notifier);
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 30)).then((_) {
            counterNotifier.forceRefresh();
          }),
        );
      },
      child: const Text('select'),
    );
  }
}

void main() {
  testWidgets(
    'BUG (tuzatishdan oldingi naqsh): mounted-guarded ref.read() widget dispose bo\'lgach forceRefresh chaqirmaydi',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _BadPatternWidget())),
      ));

      await tester.tap(find.text('select'));
      await tester.pump(); // onPressed ishlaydi, Future.delayed boshlanadi

      // Widget'ni DARHOL daraxtdan olib tashlaymiz — xuddi Navigator.pop()
      // modalni yopib, State.dispose() chaqirganidek (bu yerda animatsiya
      // muddatiga bog'liq bo'lib qolmaslik uchun to'g'ridan-to'g'ri).
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ));

      // Endi "tarmoq javobi" keladi — widget ALLAQACHON dispose bo'lgan.
      await tester.pump(const Duration(milliseconds: 40));

      expect(container.read(_counterProvider), 0,
          reason: 'widget dispose bo\'lgani uchun mounted false bo\'ladi va '
              'forceRefresh() chaqirilmay qoladi — bu NUQSON edi');
    },
  );

  testWidgets(
    'FIX: oldindan ushlab olingan notifier widget dispose bo\'lgandan keyin ham forceRefresh chaqiradi',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _FixedPatternWidget())),
      ));

      await tester.tap(find.text('select'));
      await tester.pump();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ));

      await tester.pump(const Duration(milliseconds: 40));

      expect(container.read(_counterProvider), 1,
          reason: 'notifier widget mounted paytida ushlab olingani uchun, widget '
              'allaqachon dispose bo\'lgan bo\'lsa ham forceRefresh() muvaffaqiyatli chaqiriladi');
    },
  );
}
