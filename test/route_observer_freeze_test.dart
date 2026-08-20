// Bu test loyihaning HAQIQIY `routeObserver` va `freezeRouteObserver`
// obyektlarini ishlatadi (app_router.dart'dan import qilinadi, yangisi
// yaratilmaydi) — maqsad: ClientHomeScreen'dagi "xaritani muzlatish"
// mexanizmi buyurtma-modali (showModalBottomSheet) ochilganda/yopilganda
// haqiqatan RouteAware xabarnomalarini olishini isbotlash.
//
// Fon: RouteObserver<R>.didPush/didPop faqat
//   `route is R && previousRoute is R`
// bo'lganda ishlaydi (flutter/lib/src/widgets/routes.dart). Loyihadagi
// eski `routeObserver` — `RouteObserver<PageRoute>` — Home'ning
// `_showTopPanel`ini boshqarish uchun ishlatiladi va faqat haqiqiy sahifa
// o'tishlarini (GoRoute -> PageRoute) ko'radi. `showModalBottomSheet`
// esa `ModalBottomSheetRoute` (PopupRoute'dan, ya'ni PageRoute EMAS)
// yaratadi — shu sabab eski observer buni UMUMAN ko'rmaydi. Shuning
// uchun "xarita muzlatish" alohida `freezeRouteObserver`
// (`RouteObserver<ModalRoute<void>>`) orqali ishlaydi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goway_app/core/router/app_router.dart'
    show routeObserver, freezeRouteObserver;

class _FreezeAware with RouteAware {
  _FreezeAware({required this.onPushNext, required this.onPopNext});
  final VoidCallback onPushNext;
  final VoidCallback onPopNext;

  @override
  void didPushNext() => onPushNext();

  @override
  void didPopNext() => onPopNext();
}

/// ClientHomeScreen'ning RouteAware ulanishini soddalashtirib takrorlaydi:
/// eski `routeObserver`ga o'zi (`_showTopPanel` uchun) va yangi
/// `freezeRouteObserver`ga alohida `_FreezeAware` yordamchisi orqali
/// (xarita muzlatish uchun) obuna bo'ladi — xaritasiz, tarmoqsiz, Riverpodsiz.
class _RecordingPage extends StatefulWidget {
  const _RecordingPage({super.key});
  @override
  State<_RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<_RecordingPage> with RouteAware {
  int legacyPushNext = 0;
  int legacyPopNext = 0;
  int freezePushNext = 0;
  int freezePopNext = 0;

  late final _FreezeAware _freezeAware = _FreezeAware(
    onPushNext: () => freezePushNext++,
    onPopNext: () => freezePopNext++,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
    freezeRouteObserver.subscribe(_freezeAware, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    freezeRouteObserver.unsubscribe(_freezeAware);
    super.dispose();
  }

  @override
  void didPushNext() => legacyPushNext++;

  @override
  void didPopNext() => legacyPopNext++;

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

void main() {
  testWidgets(
    'BUG: legacy routeObserver<PageRoute> does NOT fire for a showModalBottomSheet push/pop',
    (tester) async {
      final key = GlobalKey<_RecordingPageState>();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [routeObserver, freezeRouteObserver],
        home: _RecordingPage(key: key),
      ));
      await tester.pumpAndSettle();

      final ctx = key.currentContext!;
      showModalBottomSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 80));
      await tester.pumpAndSettle();

      expect(
        key.currentState!.legacyPushNext,
        0,
        reason: 'ModalBottomSheetRoute PageRoute emas (u PopupRoute) — '
            'RouteObserver<PageRoute> buni ko\'rmasligi kerak.',
      );

      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();

      expect(key.currentState!.legacyPopNext, 0);
    },
  );

  testWidgets(
    'FIX: freezeRouteObserver<ModalRoute<void>> DOES fire for a showModalBottomSheet push/pop',
    (tester) async {
      final key = GlobalKey<_RecordingPageState>();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [routeObserver, freezeRouteObserver],
        home: _RecordingPage(key: key),
      ));
      await tester.pumpAndSettle();

      final ctx = key.currentContext!;
      showModalBottomSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 80));
      await tester.pumpAndSettle();

      expect(key.currentState!.freezePushNext, 1);

      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();

      expect(key.currentState!.freezePopNext, 1);
    },
  );

  testWidgets(
    'nested modal-on-modal (order form -> truck picker) does not double-notify or unfreeze early',
    (tester) async {
      final key = GlobalKey<_RecordingPageState>();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [routeObserver, freezeRouteObserver],
        home: _RecordingPage(key: key),
      ));
      await tester.pumpAndSettle();

      final homeCtx = key.currentContext!;

      // Tashqi modal — order_form_modal.dart dagi showOrderFormModal()ga o'xshab.
      late BuildContext outerModalCtx;
      showModalBottomSheet<void>(
        context: homeCtx,
        builder: (innerCtx) {
          outerModalCtx = innerCtx;
          return const SizedBox(height: 80);
        },
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.freezePushNext, 1);

      // Ichki modal — _TruckPickerSheet kabi, TASHQI modal contextidan ochiladi.
      showModalBottomSheet<void>(context: outerModalCtx, builder: (_) => const SizedBox(height: 40));
      await tester.pumpAndSettle();

      expect(
        key.currentState!.freezePushNext,
        1,
        reason: 'ichki modal Home ga qo\'shimcha push xabari bermasligi kerak '
            '(RouteObserver faqat DARHOL ustidagi/ostidagi juftlikni bog\'laydi)',
      );

      // Ichki modalni yopamiz — tashqi modal hali ekranda.
      Navigator.of(outerModalCtx).pop();
      await tester.pumpAndSettle();

      expect(
        key.currentState!.freezePopNext,
        0,
        reason: 'ichki modal yopilishi Home ni erta tiklab yubormasligi kerak',
      );

      // Endi tashqi modalni ham yopamiz — shundagina Home tiklanadi.
      Navigator.of(homeCtx).pop();
      await tester.pumpAndSettle();

      expect(key.currentState!.freezePopNext, 1);
    },
  );
}
