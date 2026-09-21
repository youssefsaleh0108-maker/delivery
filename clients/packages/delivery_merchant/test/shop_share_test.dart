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
  _StoreAdapter({this.pinned = true, this.listed = true, this.shops = 1});

  final bool pinned;
  final bool listed;

  /// How many shops this merchant has, for the first-of-mine rule the suite follows.
  final int shops;

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
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
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

Future<_Spy> _pump(
  WidgetTester tester, {
  bool pinned = true,
  bool listed = true,
  int shops = 1,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 1600),
  Future<bool> Function(String text)? onShare,
  VoidCallback? onShopProfile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Spy spy = _Spy()..install(tester);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StoreAdapter(pinned: pinned, listed: listed, shops: shops);

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
    expect(find.text(en.merchShareCopyLink), findsOneWidget);
    expect(find.text(en.merchShareShare), findsOneWidget);
    expect(find.text(en.merchSharePrintPoster), findsOneWidget);
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

    await tester.tap(find.text(en.merchShareCopyLink));
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

    await tester.tap(find.text(ar.merchSharePrintPoster));
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
    expect(find.text(en.merchShareCopyLink), findsNothing);

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
    expect(find.text(ar.merchShareCopyLink), findsOneWidget);
    expect(find.text(ar.merchShareShare), findsOneWidget);
    expect(find.text(ar.merchSharePrintPoster), findsOneWidget);
    expect(find.text(ar.merchShareWhatTheySee), findsOneWidget);

    // A URL mirrored by the page's direction is a URL typed back wrong.
    final SelectableText address = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(address.textDirection, TextDirection.ltr);

    // Nothing overflowed the narrowest phone the suite supports.
    expect(tester.takeException(), isNull);
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
