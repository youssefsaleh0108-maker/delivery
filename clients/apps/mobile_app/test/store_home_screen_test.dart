import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/hyperlocal_screen.dart';
import 'package:mobile_app/src/neighbourhood_chat_screen.dart';
import 'package:mobile_app/src/store_home_screen.dart';

import 'widget_test.dart' show sessionWith;

/// Home's two neighbourhood doors: the browse (Figma 112:1941) and the chat room (Figma 121:102).
///
/// They used to be two full-width cards stacked above the banner rail. The owner asked for them
/// "beside each other under the banner". These tests pin that:
/// - one row of two equal tiles under the rail, or in the rail's place when there is no banner;
/// - the browse alone across the whole row when there is no chat room, not half a row and a hole;
/// - a row that still fits, and still mirrors, on a 320dp phone, with large text, in Arabic;
/// - two tiles that are still doors: a tap anywhere on either opens what it names.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  /// The page gutter, and the house two-up gap the row puts between its tiles.
  const double gutter = DeliverySpacing.lg;
  const double gap = DeliverySpacing.md - DeliverySpacing.xs;

  late List<Map<String, dynamic>> banners;

  setUp(() {
    // Two, so the rail draws its dots as well: the row has to clear the whole rail.
    banners = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'b1', 'title': 'Ramadan at the corner shop', 'linkKind': 'NONE'},
      <String, dynamic>{'id': 'b2', 'title': 'Free delivery this weekend', 'linkKind': 'NONE'},
    ];
  });

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  final Map<String, dynamic> grocer = <String, dynamic>{
    'id': 's1',
    'slug': 's1',
    'name': 'Abu Hassan Mini Market',
    'vertical': 'GROCERY',
    'availability': 'OPEN',
    'rating': 4.6,
    'ratingCount': 12,
  };

  Object? answer(RequestOptions options) {
    if (options.path.startsWith('/api/orders')) return page(const <Map<String, dynamic>>[]);
    return switch (options.path) {
      '/api/stores' => page(<Map<String, dynamic>>[grocer]),
      '/api/stores/favorites' => page(const <Map<String, dynamic>>[]),
      '/api/banners' => banners,
      '/api/categories/chips' => const <dynamic>[],
      '/api/delivery-zones' => const <dynamic>[],
      '/api/notifications/unread-count' => const <String, dynamic>{'unread': 0},
      '/api/butler/mine' => page(const <Map<String, dynamic>>[]),
      _ => null,
    };
  }

  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final Object? body = options.method == 'GET' ? answer(options) : null;
        if (body == null) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: options, statusCode: 404),
          ));
          return;
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  /// Home through the real shell: the shell decides whether Home gets a chat room at all.
  Future<void> pumpHome(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool withChat = true,
    double width = 390,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = fakeServer();
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CustomerShell(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        notificationApi: NotificationApi(dio),
        butlerApi: ButlerApi(dio),
        zoneApi: DeliveryZoneApi(dio),
        offerApi: OfferApi(dio),
        neighbourhoodChatApi: withChat ? NeighbourhoodChatApi(dio) : null,
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(
            read: () async => locale.languageCode, write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder tileOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(YdCard));
  Finder bannerRail() =>
      find.descendant(of: find.byType(StoreHomeScreen), matching: find.byType(PageView));
  Finder inTile(String title, Finder matching) =>
      find.descendant(of: tileOf(title), matching: matching);
  Finder browseDisc(String title) => inTile(title, find.byIcon(Icons.storefront_rounded));
  Finder chevronIn(String title) => inTile(title, find.byIcon(Icons.chevron_right));

  testWidgets('the browse and the chat sit side by side, in one row under the banner rail',
      (WidgetTester tester) async {
    await pumpHome(tester);

    final Rect rail = tester.getRect(bannerRail());
    final Rect browse = tester.getRect(tileOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(tileOf(en.chatRoomEntryTitle));

    // Under the rail, not above it where they used to be.
    expect(browse.top, greaterThanOrEqualTo(rail.bottom));
    // One row of two equal columns: the same line, the same height, the same width.
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    expect(chat.width, browse.width);
    // On the page gutter, the browse first, the house gap between them.
    expect(browse.left, gutter);
    expect(chat.right, 390 - gutter);
    expect(chat.left - browse.right, gap);
    // In each tile, the disc and the chevron share the top line, with the words underneath.
    final Rect disc = tester.getRect(browseDisc(en.dekkaneBrowseTitle));
    final Rect chevron = tester.getRect(chevronIn(en.dekkaneBrowseTitle));
    expect(disc.center.dx, lessThan(chevron.center.dx));
    expect(tester.getRect(find.text(en.dekkaneBrowseTitle)).top, greaterThan(disc.bottom));
    // The rest of Home carries on underneath, in its old order.
    expect(tester.getRect(find.text(en.custActiveStoresNearby)).top, greaterThan(browse.bottom));
  });

  testWidgets('with no chat room, the browse takes the whole row rather than half of it',
      (WidgetTester tester) async {
    await pumpHome(tester, withChat: false);

    expect(find.text(en.chatRoomEntryTitle), findsNothing);
    final Rect browse = tester.getRect(tileOf(en.dekkaneBrowseTitle));
    expect(browse.left, gutter);
    expect(browse.right, 390 - gutter);
    expect(browse.top, greaterThanOrEqualTo(tester.getRect(bannerRail()).bottom));
    // The full-width card it was drawn as: the words beside the disc, not under it.
    final Rect disc = tester.getRect(browseDisc(en.dekkaneBrowseTitle));
    expect(tester.getRect(find.text(en.dekkaneBrowseTitle)).left, greaterThan(disc.right));
  });

  testWidgets('with no banner, the row takes the place the rail would have had',
      (WidgetTester tester) async {
    await pumpHome(tester);
    final double railTop = tester.getRect(bannerRail()).top;

    // The same Home again, from scratch, on a day the Backoffice has no banner up.
    banners = <Map<String, dynamic>>[];
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester);

    expect(bannerRail(), findsNothing);
    final Rect browse = tester.getRect(tileOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(tileOf(en.chatRoomEntryTitle));
    expect(browse.top, railTop);
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    expect(chat.left - browse.right, gap);
  });

  testWidgets('on a 320dp phone the row still fits, and each whole tile is a 48dp-plus target',
      (WidgetTester tester) async {
    await pumpHome(tester, width: 320);

    expect(tester.takeException(), isNull);
    final Rect browse = tester.getRect(tileOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(tileOf(en.chatRoomEntryTitle));
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    expect(chat.width, browse.width);
    expect(chat.right, 320 - gutter);
    for (final String title in <String>[en.dekkaneBrowseTitle, en.chatRoomEntryTitle]) {
      // The ripple covers the tile edge to edge, so the tap target is the tile itself.
      final Rect target = tester.getRect(inTile(title, find.byType(InkWell)));
      expect(target, tester.getRect(tileOf(title)));
      expect(target.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(target.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    }
  });

  testWidgets('with large text on a 320dp phone the tiles grow taller together; nothing overflows',
      (WidgetTester tester) async {
    await pumpHome(tester, width: 320);
    final double normalHeight = tester.getSize(tileOf(en.dekkaneBrowseTitle)).height;

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
    final Rect browse = tester.getRect(tileOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(tileOf(en.chatRoomEntryTitle));
    expect(browse.height, greaterThan(normalHeight));
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    expect(chat.left - browse.right, gap);
  });

  testWidgets('in Arabic the row mirrors, the browse at the start on the right, and fits at 320dp '
      'with large text', (WidgetTester tester) async {
    await pumpHome(tester, locale: const Locale('ar'), width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
    final Rect browse = tester.getRect(tileOf(ar.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(tileOf(ar.chatRoomEntryTitle));
    expect(browse.right, 320 - gutter);
    expect(chat.left, gutter);
    expect(browse.left - chat.right, gap);
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    // Inside the tile too: the disc at the start on the right, the chevron at the end, mirrored
    // by the icon itself exactly once so that it points the way the tile opens.
    final Rect disc = tester.getRect(browseDisc(ar.dekkaneBrowseTitle));
    final Finder chevron = chevronIn(ar.dekkaneBrowseTitle);
    expect(disc.center.dx, greaterThan(tester.getRect(chevron).center.dx));
    final Iterable<Transform> flips = tester
        .widgetList<Transform>(find.descendant(of: chevron, matching: find.byType(Transform)));
    expect(flips, hasLength(1));
    expect(flips.single.transform.storage[0], -1);
  });

  testWidgets('the browse tile opens the neighbourhood browse over the shell',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(find.byType(HyperlocalScreen), findsNothing);
    await tester.tap(tileOf(en.dekkaneBrowseTitle));
    await tester.pumpAndSettle();

    expect(find.byType(HyperlocalScreen), findsOneWidget);
  });

  testWidgets('the chat tile opens the neighbourhood room, even tapped low on the tile',
      (WidgetTester tester) async {
    await pumpHome(tester);

    // Below the words, where only the tile's own padding (and whatever height the row's stretch
    // added) is: still the chat's door, not a dead strip.
    await tester.tapAt(tester.getRect(tileOf(en.chatRoomEntryTitle)).bottomCenter -
        const Offset(0, DeliverySpacing.xs));
    await tester.pumpAndSettle();

    expect(find.byType(NeighbourhoodChatScreen), findsOneWidget);
  });

  group("with the app's own font", () {
    // Everything above runs in the test font, where every glyph is a full em wide. That is harsher
    // than any real text, which is what an overflow check wants. Whether a word is cut short is a
    // question about the real font, so this group loads the Rubik the theme names. It stays loaded
    // for the rest of this file, so this group stays last.
    setUpAll(() async {
      final FontLoader rubik = FontLoader(DeliveryTypography.fontFamily);
      for (final String face in <String>['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        rubik.addFont(rootBundle.load('packages/delivery_design_system/fonts/Rubik-$face.ttf'));
      }
      await rubik.load();
    });

    for (final double textScale in <double>[1.0, 1.3]) {
      testWidgets('at 320dp with text at x$textScale, no title or line on either tile is cut short',
          (WidgetTester tester) async {
        await pumpHome(tester, width: 320, textScale: textScale);

        for (final String text in <String>[
          en.dekkaneBrowseTitle,
          en.dekkaneEntrySub,
          en.chatRoomEntryTitle,
          en.chatRoomEntrySub,
        ]) {
          expect(tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines, isFalse,
              reason: '"$text" loses its end to an ellipsis at 320dp, text x$textScale');
        }
      });
    }

    testWidgets('at 320dp a title wraps between words, never inside one',
        (WidgetTester tester) async {
      await pumpHome(tester, width: 320);

      for (final String title in <String>[en.dekkaneBrowseTitle, en.chatRoomEntryTitle]) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.text(title));
        for (final String word in title.split(' ')) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: word, style: paragraph.text.style),
            textScaler: paragraph.textScaler,
            textDirection: TextDirection.ltr,
          )..layout();
          expect(painter.width, lessThanOrEqualTo(paragraph.constraints.maxWidth),
              reason: '"$word" is wider than the tile and would break in the middle');
          painter.dispose();
        }
      }
    });
  });
}
