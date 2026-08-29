import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/merchant_shell.dart';

/// That the shop can actually REACH the screens this shell owns.
///
/// Written because one of them could not. The merchant statement screen, its Arabic strings and its
/// "this figure is not a payment" notice were built, tested and exported — and shipped dead, because
/// [MerchantShell] never took a [StatementsApi] and the settings row hides itself when unwired. The
/// screen's own tests passed the whole time: they constructed it directly and wired the client
/// themselves, so nothing anywhere failed while the only real host on the phone did not pass it.
///
/// So what is pinned here is not what the screen renders. It is that the shell HANDS IT OVER — the
/// join between a finished screen and the app that is supposed to open it, which is exactly the seam
/// a green suite cannot see.
class _StubAdapter implements HttpClientAdapter {
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    // Empty collections and a bare object satisfy every screen the shell builds on open.
    final String body = options.path.contains('orders') || options.path.contains('products')
        ? '{"content":[],"totalElements":0}'
        : '{}';
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _StubAdapter adapter;

  setUp(() {
    adapter = _StubAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  });

  Future<void> pumpSettingsTab(WidgetTester tester, {required bool wireStatements}) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantShell(
        orderApi: OrderApi(dio),
        storeApi: StoreApi(dio),
        catalogApi: CatalogApi(dio),
        statementsApi: wireStatements ? StatementsApi(dio) : null,
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.merchant},
          subject: 'merchant-sub',
        ),
        locale: LocaleController(
          read: () async => 'en',
          write: (String _) async {},
        ),
        onSignOut: () async {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The Settings tab, reached the way a merchant reaches it: through the shell's own bottom bar.
    final DeliveryStrings t =
        DeliveryStrings.of(tester.element(find.byType(MerchantShell)));
    await tester.tap(find.text(t.navSettings).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the shop can open its own statement from Settings', (WidgetTester tester) async {
    await pumpSettingsTab(tester, wireStatements: true);

    // The row the app shipped without. Its title comes from the statement screen's own words, so
    // this also proves the two halves agree about what it is called.
    expect(find.text(MerchantStatementWords.of(
            tester.element(find.byType(MerchantShell)))
        .title), findsOneWidget);
  });

  testWidgets('and the row hides rather than dying when a host does not wire it',
      (WidgetTester tester) async {
    await pumpSettingsTab(tester, wireStatements: false);

    // The optional-client convention this shell uses throughout: no client, no row. Correct on its
    // own — it is only a problem when the real host forgets, which the test above now catches.
    expect(find.text(MerchantStatementWords.of(
            tester.element(find.byType(MerchantShell)))
        .title), findsNothing);
  });
}
