import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/merchant_shell.dart';

/// Every screen the shell opens on start answers empty; the inbox answers two conversations with
/// three unread messages between them.
class _Gateway implements HttpClientAdapter {
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    final String body = options.path == '/api/chat/shop-threads/inbox'
        ? '[{"id":"t1","storeId":"s1","storeName":"Abu Hassan","yourSide":"SHOP","open":true,'
            '"lastSequence":2,"unread":2},'
            '{"id":"t2","storeId":"s1","storeName":"Abu Hassan","yourSide":"SHOP","open":true,'
            '"lastSequence":1,"unread":1}]'
        : options.path.contains('orders') || options.path.contains('products')
            ? '{"content":[],"totalElements":0}'
            : '{}';
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// That a shop can SEE a customer wrote without opening the inbox to find out.
///
/// There is no push for these messages. Before this the only sign was the inbox itself, reached
/// through Settings — and since reading the inbox is what tells the server who owns the shop, not
/// even a live message arrived before the merchant happened to open it. The shell now asks from the
/// start and hands the number to the row.
void main() {
  testWidgets("Settings' messages row shows how many customer messages are unread, asked from the start",
      (WidgetTester tester) async {
    final _Gateway gateway = _Gateway();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
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
        shopChatApi: ShopChatApi(dio),
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.merchant},
          subject: 'merchant-sub',
        ),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(gateway.calls, contains('GET /api/chat/shop-threads/inbox'),
        reason: 'Asked on start, not on the first visit to the inbox.');

    final DeliveryStrings t = DeliveryStrings.of(tester.element(find.byType(MerchantShell)));
    await tester.tap(find.text(t.navSettings).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
        find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == t.chatShopUnreadCount(3)),
        findsOneWidget);
  });
}
