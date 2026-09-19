import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/hyperlocal_screen.dart';

import 'store_home_fixtures.dart';

/// Home's two neighbourhood doors: the browse (Figma 112:1941) and the chat room (Figma 121:102).
///
/// They used to be two full-width cards stacked above the banner rail. The owner asked for them
/// "beside each other under the banner". They share one row there when every word of both titles
/// fits a half tile, and stack as the full-width cards when one would not. Where that line falls
/// is a question about the real font, so the shapes at real phone widths are pinned in
/// store_home_screen_rubik_test.dart, which loads it.
///
/// These tests run in the test font, where every glyph is a full em wide. That is harsher than any
/// real text, which is what an overflow check wants. They pin:
/// - the browse alone across the whole row when there is no chat room, not half a row and a hole;
/// - with glyphs that wide, the doors stack rather than break a word, and nothing overflows;
/// - a row that still fits, and still mirrors, on a 320dp phone, with large text, in Arabic;
/// - doors that are still doors: a tap opens what each names.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('with no chat room, the browse takes the whole row rather than half of it',
      (WidgetTester tester) async {
    await pumpHome(tester, withChat: false);

    expect(find.text(en.chatRoomEntryTitle), findsNothing);
    final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
    expect(browse.left, homeGutter);
    expect(browse.right, 390 - homeGutter);
    expect(browse.top, greaterThanOrEqualTo(tester.getRect(bannerRail()).bottom));
    // The full-width card it was drawn as: the words beside the disc, not under it.
    final Rect disc =
        tester.getRect(inDoor(en.dekkaneBrowseTitle, find.byIcon(Icons.storefront_rounded)));
    expect(tester.getRect(find.text(en.dekkaneBrowseTitle)).left, greaterThan(disc.right));
  });

  for (final double textScale in <double>[1.0, 1.3]) {
    testWidgets('at 320dp with text at x$textScale, full-em letters make a title word too wide for '
        'a half tile, so the doors stack under the rail; nothing overflows',
        (WidgetTester tester) async {
      await pumpHome(tester, width: 320, textScale: textScale);

      expect(tester.takeException(), isNull);
      final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
      final Rect chat = tester.getRect(doorOf(en.chatRoomEntryTitle));
      expect(browse.top, greaterThanOrEqualTo(tester.getRect(bannerRail()).bottom));
      for (final Rect door in <Rect>[browse, chat]) {
        expect(door.left, homeGutter);
        expect(door.right, 320 - homeGutter);
      }
      expect(chat.top - browse.bottom, homeDoorGap);
    });
  }

  testWidgets('in Arabic the row mirrors, the browse at the start on the right, and fits at 320dp '
      'with large text', (WidgetTester tester) async {
    await pumpHome(tester, locale: const Locale('ar'), width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
    final Rect browse = tester.getRect(doorOf(ar.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(doorOf(ar.chatRoomEntryTitle));
    expect(browse.right, 320 - homeGutter);
    expect(chat.left, homeGutter);
    expect(browse.left - chat.right, homeDoorGap);
    expect(chat.top, browse.top);
    expect(chat.height, browse.height);
    // Inside the tile too: the disc at the start on the right, the chevron at the end, mirrored
    // by the icon itself exactly once so that it points the way the tile opens.
    final Rect disc =
        tester.getRect(inDoor(ar.dekkaneBrowseTitle, find.byIcon(Icons.storefront_rounded)));
    final Finder chevron = inDoor(ar.dekkaneBrowseTitle, find.byIcon(Icons.chevron_right));
    expect(disc.center.dx, greaterThan(tester.getRect(chevron).center.dx));
    final Iterable<Transform> flips = tester
        .widgetList<Transform>(find.descendant(of: chevron, matching: find.byType(Transform)));
    expect(flips, hasLength(1));
    expect(flips.single.transform.storage[0], -1);
  });

  testWidgets('the browse door opens the neighbourhood browse over the shell',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(find.byType(HyperlocalScreen), findsNothing);
    await tester.tap(doorOf(en.dekkaneBrowseTitle));
    await tester.pumpAndSettle();

    expect(find.byType(HyperlocalScreen), findsOneWidget);
  });
}
