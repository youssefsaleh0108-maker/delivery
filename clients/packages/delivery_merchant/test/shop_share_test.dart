import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share your shop: the link, the QR code and the printable poster.
///
/// The shop page has been live since it was built and a merchant had no way to reach it — no
/// address shown anywhere in the app, and the QR code the owner asked for reachable only by typing
/// a URL nobody had been told. What is pinned here is the whole of that gap:
///
/// * a live, pinned shop gets the address in full, a scannable code and three ways to pass it on;
/// * a shop with **no page** — no pin, or not published — is told which one thing fixes it and is
///   shown no code, because a QR printed and taped to a counter that leads to a 404 is worse than
///   none;
/// * sharing uses the host's own sheet where there is one and the clipboard where there is not, so
///   the same widget is correct on the phone and on the web portal;
/// * the poster opens the address the service really serves it at, in the merchant's language.
///
/// The QR itself never loads under `flutter_test` — the test HttpClient refuses every request — so
/// what is asserted is the image the screen asked for, which is the part that can be wrong.
const String _origin = 'https://www.youdrop.shop';

class _StoreAdapter implements HttpClientAdapter {
  _StoreAdapter({
    this.pinned = true,
    this.listed = true,
    this.shops = 1,
    this.tables = 0,
    this.ordering = false,
  });

  final bool pinned;
  final bool listed;

  /// How many shops this merchant has, for the first-of-mine rule the suite follows.
  final int shops;

  /// How many tables the shop starts with — what a merchant who has already generated codes sees.
  int tables;

  /// Whether the shop takes orders at those tables — the switch the web basket reads.
  bool ordering;

  /// Every `PUT /api/stores/{id}/tables` this screen made, in order.
  final List<int> tablesSaved = <int>[];

  /// And what each of them said about ordering; null when the body left it out.
  final List<bool?> orderingSaved = <bool?>[];

  /// Set to refuse the table save, which is the case the stepper has to put back.
  bool refuseTables = false;

  Map<String, dynamic> _store(int index) => <String, dynamic>{
        'id': 'store-$index',
        'slug': index == 0 ? 'falafel-king' : 'falafel-king-$index',
        'name': index == 0 ? 'Falafel King' : 'Falafel King $index',
        'vertical': 'RESTAURANT',
        'availability': 'OPEN',
        'status': listed ? 'ACTIVE' : 'DRAFT',
        'address': 'Hamra Street, Beirut',
        'deliveryFee': 2.5,
        'minOrder': 10.0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
        'tableCount': tables,
        'tableOrdering': ordering,
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.path.endsWith('/tables')) {
      if (refuseTables) {
        return ResponseBody.fromString('{"detail":"nope"}', 500,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            });
      }
      final Map<String, dynamic> body = options.data as Map<String, dynamic>;
      final int asked = body['tables'] as int;
      tablesSaved.add(asked);
      orderingSaved.add(body['ordering'] as bool?);
      tables = asked;
      // What the server does: no tables means nobody can order at them.
      ordering = asked == 0 ? false : (body['ordering'] as bool? ?? ordering);
      return ResponseBody.fromString(jsonEncode(_store(0)), 200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType]
          });
    }
    final Object body = options.path.endsWith('/mine')
        ? <String, dynamic>{
            'content': <Map<String, dynamic>>[
              for (int i = 0; i < shops; i++) _store(i),
            ],
            'page': 0,
            'size': 20,
            'totalElements': shops,
            'totalPages': 1,
          }
        : _store(0);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// What reached the clipboard, and what the app asked a browser to open.
class _Spy {
  final List<String> copied = <String>[];
  final List<String> launched = <String>[];

  void install(WidgetTester tester) {
    final TestDefaultBinaryMessenger messenger =
        tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
      }
      return null;
    });
    // url_launcher's own channel. The plugin is not registered in a widget test, so the platform
    // interface is still the method-channel one and this is the call it makes.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        final Object? arguments = call.arguments;
        if (arguments is Map<Object?, Object?> && arguments['url'] is String) {
          launched.add(arguments['url']! as String);
        }
        return true;
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'), null);
    });
  }
}

/// The adapter the last [_pump] built, for the tests that ask what the screen sent.
late _StoreAdapter _server;

Future<_Spy> _pump(
  WidgetTester tester, {
  bool pinned = true,
  bool listed = true,
  int shops = 1,
  int tables = 0,
  bool ordering = false,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 1600),
  Future<bool> Function(String text)? onShare,
  VoidCallback? onShopProfile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Spy spy = _Spy()..install(tester);
  _server = _StoreAdapter(
      pinned: pinned, listed: listed, shops: shops, tables: tables, ordering: ordering);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _server;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: ShopShareScreen(
      api: StoreApi(dio),
      onShare: onShare,
      onShopProfile: onShopProfile,
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

/// The URL of the one network image on screen, or null when there is none.
String? _qrUrl(WidgetTester tester) {
  final Iterable<Image> images = tester.widgetList<Image>(find.byType(Image));
  for (final Image image in images) {
    final ImageProvider<Object> provider = image.image;
    if (provider is NetworkImage) return provider.url;
  }
  return null;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  // ---------------------------------------------------------------- a shop with a page

  testWidgets('a live, pinned shop gets its address, its code and three ways to pass them on',
      (WidgetTester tester) async {
    await _pump(tester);

    // In full and selectable: a merchant reads it out over the phone as often as they tap it.
    expect(find.text('$_origin/s/falafel-king'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(_qrUrl(tester), '$_origin/s/falafel-king/qr.png');
    // Copy is the icon beside the address now, as the design draws it; the three tiles under it
    // are download, print and share.
    expect(find.byTooltip(en.merchShareCopyLink), findsOneWidget);
    expect(find.text(en.merchShareDownloadQr), findsOneWidget);
    expect(find.text(en.merchSharePrintQr), findsOneWidget);
    expect(find.text(en.merchShareShare), findsOneWidget);
    // What the merchant is handing over, before they hand it over.
    expect(find.text(en.merchShareWhatTheySee), findsOneWidget);
  });

  testWidgets('the code is big enough to scan off the screen', (WidgetTester tester) async {
    await _pump(tester);

    // Somebody else's phone reads this across a counter. A 64px thumbnail would not be read at all.
    final Size drawn = tester.getSize(find.byType(Image).first);
    expect(drawn.width, greaterThanOrEqualTo(180));
  });

  testWidgets('a merchant with several shops sees the one the rest of the suite shows',
      (WidgetTester tester) async {
    await _pump(tester, shops: 3);

    // First of `mine`, exactly as Shop Profile resolves it. A second shop's page here would be a
    // merchant printing the wrong QR code.
    expect(find.text('$_origin/s/falafel-king'), findsOneWidget);
  });

  testWidgets('Copy link puts the address on the clipboard and says so',
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester);

    await tester.tap(find.byTooltip(en.merchShareCopyLink));
    await tester.pumpAndSettle();

    expect(spy.copied, <String>['$_origin/s/falafel-king']);
    expect(find.text(en.merchShareLinkCopied), findsOneWidget);
  });

  testWidgets("Share uses the phone's own sheet when the host has one",
      (WidgetTester tester) async {
    final List<String> shared = <String>[];
    final _Spy spy = await _pump(tester, onShare: (String text) async {
      shared.add(text);
      return true;
    });

    await tester.tap(find.text(en.merchShareShare));
    await tester.pumpAndSettle();

    // The link alone, with no sentence in front of it: every chat app draws its own preview card
    // from the page's Open Graph tags, and our prose would be something to delete.
    expect(shared, <String>['$_origin/s/falafel-king']);
    // The sheet did the sharing, so nothing was quietly copied as well.
    expect(spy.copied, isEmpty);
  });

  testWidgets('on the web, where there is no sheet, Share copies and confirms',
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester);

    await tester.tap(find.text(en.merchShareShare));
    await tester.pumpAndSettle();

    expect(spy.copied, <String>['$_origin/s/falafel-king']);
    expect(find.text(en.merchShareLinkCopied), findsOneWidget);
  });

  testWidgets('a sheet that would not open still leaves the link on the clipboard',
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester, onShare: (String text) async => false);

    await tester.tap(find.text(en.merchShareShare));
    await tester.pumpAndSettle();

    expect(spy.copied, <String>['$_origin/s/falafel-king']);
  });

  testWidgets("Print the poster opens the sheet the service serves, in the merchant's language",
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester, locale: const Locale('ar'));

    await tester.tap(find.text(ar.merchSharePrintQr));
    await tester.pumpAndSettle();

    expect(spy.launched, <String>['$_origin/s/falafel-king/poster?lang=ar']);
  });

  // ---------------------------------------------------------------- a shop with no page

  testWidgets('a shop with no pin is told to place it, and shown no code',
      (WidgetTester tester) async {
    bool opened = false;
    await _pump(tester, pinned: false, onShopProfile: () => opened = true);

    expect(find.text(en.merchShareNoPageTitle), findsOneWidget);
    expect(find.text(en.merchShareNeedsPin), findsOneWidget);
    // The whole point: no dead QR code, and no address that answers 404.
    expect(_qrUrl(tester), isNull);
    expect(find.byTooltip(en.merchShareCopyLink), findsNothing);

    await tester.tap(find.text(en.merchSharePlaceOnMap));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('a pinned shop that is not live yet is told to publish it',
      (WidgetTester tester) async {
    await _pump(tester, listed: false, onShopProfile: () {});

    expect(find.text(en.merchShareNeedsPublish), findsOneWidget);
    expect(find.text(en.merchSharePublishYourShop), findsOneWidget);
    expect(_qrUrl(tester), isNull);
  });

  testWidgets('with nowhere to send them, the fix is stated but not offered as a dead button',
      (WidgetTester tester) async {
    await _pump(tester, pinned: false);

    expect(find.text(en.merchShareNeedsPin), findsOneWidget);
    expect(find.text(en.merchSharePlaceOnMap), findsNothing);
  });

  // ---------------------------------------------------------------- where a merchant finds it

  testWidgets('the Settings list carries a row straight to it', (WidgetTester tester) async {
    bool opened = false;
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        accountName: 'Rima Haddad',
        onShopProfile: () {},
        onShareShop: () => opened = true,
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Beside Shop Profile, which is where a merchant already looks for their shop.
    expect(find.text(en.merchShareTitle), findsOneWidget);
    await tester.tap(find.text(en.merchShareTitle));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('a host that has not wired it draws no row at all', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        accountName: 'Rima Haddad',
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(en.merchShareTitle), findsNothing);
  });

  // ---------------------------------------------------------------- Arabic, on a small phone

  testWidgets('it reads in Arabic on a 320dp phone, and the address still reads left to right',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'), size: const Size(320, 1800));

    expect(Directionality.of(tester.element(find.byType(ShopShareCard))), TextDirection.rtl);
    expect(find.byTooltip(ar.merchShareCopyLink), findsOneWidget);
    expect(find.text(ar.merchShareDownloadQr), findsOneWidget);
    expect(find.text(ar.merchSharePrintQr), findsOneWidget);
    expect(find.text(ar.merchShareShare), findsOneWidget);
    expect(find.text(ar.merchShareWhatTheySee), findsOneWidget);

    // A URL mirrored by the page's direction is a URL typed back wrong.
    final SelectableText address = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(address.textDirection, TextDirection.ltr);

    // Nothing overflowed the narrowest phone the suite supports.
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------- table QR codes

  testWidgets('a shop that has asked for no tables is offered the stepper and nothing to print',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text(en.merchTablesTitle), findsOneWidget);
    expect(find.text(en.merchTablesHowMany), findsOneWidget);
    // Nothing to print until the shop has said how many tables it has: the codes are generated
    // from that number, and the server refuses a card for a table nobody declared.
    expect(find.text(en.merchTablesSave), findsOneWidget);
    expect(find.text(en.merchTablesPrintSheet), findsNothing);
    expect(find.text(en.merchTablesReprintOne), findsNothing);
  });

  testWidgets('twelve taps of plus saves twelve, and twelve reprint chips appear',
      (WidgetTester tester) async {
    await _pump(tester, size: const Size(400, 2200));

    for (int i = 0; i < 12; i++) {
      await tester.tap(find.bySemanticsLabel(en.merchTablesMore));
      await tester.pump();
    }
    await tester.tap(find.text(en.merchTablesSave));
    await tester.pumpAndSettle();

    // The number is saved whole, not as twelve nudges: two devices each sending a delta would
    // leave the room with tables nobody has.
    expect(_server.tablesSaved, <int>[12]);
    expect(find.text(en.merchTablesSaved(12)), findsOneWidget);
    // One chip per table, so a merchant replacing the card on table 7 taps 7.
    for (int table = 1; table <= 12; table++) {
      expect(find.byTooltip(en.merchTablesReprintTable(table)), findsOneWidget);
    }
    expect(find.text(en.merchTablesPrintSheet), findsOneWidget);
  });

  testWidgets('the sheet and a single reprint open the service, carrying the table parameter',
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester, tables: 12, size: const Size(400, 2200));

    await tester.tap(find.text(en.merchTablesPrintSheet));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(en.merchTablesReprintTable(7)));
    await tester.pumpAndSettle();

    // `t`, and the table's own number — the parameter the printed code carries and the web basket
    // reads back. A second spelling here would be a card that scans to a page with no table on it.
    expect(spy.launched, <String>[
      '$_origin/s/falafel-king/tables?lang=en',
      '$_origin/s/falafel-king/tables?lang=en&t=7',
    ]);
  });

  testWidgets('Download QR opens the image the service draws', (WidgetTester tester) async {
    final _Spy spy = await _pump(tester);

    await tester.tap(find.text(en.merchShareDownloadQr));
    await tester.pumpAndSettle();

    expect(spy.launched, <String>['$_origin/s/falafel-king/qr.png']);
  });

  testWidgets('a refused save puts the number back to what the shop still has',
      (WidgetTester tester) async {
    await _pump(tester, tables: 4, size: const Size(400, 2200));
    _server.refuseTables = true;

    await tester.tap(find.bySemanticsLabel(en.merchTablesMore));
    await tester.pump();
    expect(find.bySemanticsLabel(en.merchTablesCount(5)), findsOneWidget);

    await tester.tap(find.text(en.merchTablesSave));
    await tester.pumpAndSettle();

    // A screen that kept the 5 would be telling the merchant they have a card for table 5.
    expect(find.text(en.merchTablesCouldNotSave), findsOneWidget);
    expect(find.bySemanticsLabel(en.merchTablesCount(4)), findsOneWidget);
  });

  // -------------------------------------------- taking orders at the table

  testWidgets('a shop with no tables is not asked whether it takes orders at them',
      (WidgetTester tester) async {
    await _pump(tester);

    // There would be nothing for an order to say it came from: every one carries the number off
    // the card it was scanned from, and there are no cards.
    expect(find.text(en.merchTablesOrderingTitle), findsNothing);
  });

  testWidgets('the switch is off until the shop says otherwise, and saves with the count',
      (WidgetTester tester) async {
    await _pump(tester, tables: 6, size: const Size(400, 2400));

    // Off is where a shop starts. Printing cards is not a promise that somebody is watching a
    // screen, and a default of on would have made that promise for shops that never asked.
    expect(find.text(en.merchTablesOrderingOff), findsOneWidget);

    await tester.tap(find.byType(MerchantAvailabilitySwitch));
    await tester.pump();
    expect(find.text(en.merchTablesOrderingOn), findsOneWidget);

    await tester.tap(find.text(en.merchTablesSave));
    await tester.pumpAndSettle();

    // One call for both, because they are one decision on one screen.
    expect(_server.tablesSaved, <int>[6]);
    expect(_server.orderingSaved, <bool?>[true]);
  });

  testWidgets('a shop already taking orders says so when the screen opens',
      (WidgetTester tester) async {
    await _pump(tester, tables: 6, ordering: true, size: const Size(400, 2400));

    expect(find.text(en.merchTablesOrderingOn), findsOneWidget);
    // Nothing to save: the screen opened on what the shop already is.
    expect(find.text(en.merchTablesPrintSheet), findsOneWidget);
  });

  testWidgets('taking the tables to none takes the ordering with them',
      (WidgetTester tester) async {
    await _pump(tester, tables: 1, ordering: true, size: const Size(400, 2400));

    await tester.tap(find.bySemanticsLabel(en.merchTablesFewer));
    await tester.pump();
    await tester.tap(find.text(en.merchTablesSave));
    await tester.pumpAndSettle();

    // The server turns it off with them, and the screen settles on the server's answer rather than
    // on what it sent: a shop advertising ordering at tables it has said it does not have is a
    // diner at a card that leads nowhere.
    expect(_server.tablesSaved, <int>[0]);
    expect(find.text(en.merchTablesOrderingTitle), findsNothing);
    expect(find.text(en.merchTablesPrintSheet), findsNothing);
  });

  testWidgets('the table block reads in Arabic on a 320dp phone', (WidgetTester tester) async {
    await _pump(tester, tables: 3, locale: const Locale('ar'), size: const Size(320, 2400));

    expect(find.text(ar.merchTablesTitle), findsOneWidget);
    expect(find.text(ar.merchTablesHowMany), findsOneWidget);
    expect(find.text(ar.merchTablesPrintSheet), findsOneWidget);
    // Western digits, left to right: this is the number printed on the card and in its address.
    final Text number = tester.widget<Text>(find.text('3').first);
    expect(number.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shop with no page is offered no table codes either',
      (WidgetTester tester) async {
    await _pump(tester, pinned: false);

    // The cards point at the page. A shop with no page must not be able to print one.
    expect(find.text(en.merchTablesTitle), findsNothing);
  });

  testWidgets('the not-ready state reads in Arabic too on a 320dp phone',
      (WidgetTester tester) async {
    await _pump(tester,
        pinned: false,
        locale: const Locale('ar'),
        size: const Size(320, 1800),
        onShopProfile: () {});

    expect(find.text(ar.merchShareNoPageTitle), findsOneWidget);
    expect(find.text(ar.merchSharePlaceOnMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
