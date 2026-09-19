import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/neighbourhood_chat_screen.dart';

import 'store_home_fixtures.dart';

/// Home's two neighbourhood doors, the browse (Figma 112:1941) and the chat room (Figma 121:102),
/// in the app's own font.
///
/// The owner asked for them "beside each other under the banner". They share one row there when
/// every word of both titles fits a half tile. When a word would not fit, it would break in the
/// middle, so the doors stack as the two full-width cards instead. Whether a word fits is a
/// question about the real font, so this file loads the Rubik the theme names, once, for all of it.
/// Each test file runs on its own, so the font never reaches the rest of the suite, which runs in
/// the test font (store_home_screen_test.dart covers the doors there).
///
/// A half tile leaves its words (width - 108) / 2 dp: 106 at 320dp, 126 at 360dp, 141 at 390dp.
/// The widest title word in the tile's 13sp is "Neighbourhood": 104dp at normal text size, 134dp
/// at text x1.3.
void main() {
  setUpAll(() async {
    final FontLoader rubik = FontLoader(DeliveryTypography.fontFamily);
    for (final String face in <String>['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      rubik.addFont(rootBundle.load('packages/delivery_design_system/fonts/Rubik-$face.ttf'));
    }
    await rubik.load();
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final List<String> titles = <String>[en.dekkaneBrowseTitle, en.chatRoomEntryTitle];
  final List<String> subtitles = <String>[en.dekkaneEntrySub, en.chatRoomEntrySub];

  /// The two doors share one row: the same line, the same height and width, the browse first on
  /// the page gutter, the house gap between them.
  void expectSideBySide(WidgetTester tester, double width) {
    final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(doorOf(en.chatRoomEntryTitle));
    expect(chat.top, browse.top, reason: 'side by side, the doors start on the same line');
    expect(chat.height, browse.height);
    expect(chat.width, browse.width);
    expect(browse.left, homeGutter);
    expect(chat.right, width - homeGutter);
    expect(chat.left - browse.right, homeDoorGap);
  }

  /// The two doors are the full-width cards, the browse over the chat room with the house gap
  /// between them.
  void expectStacked(WidgetTester tester, double width) {
    final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(doorOf(en.chatRoomEntryTitle));
    for (final Rect door in <Rect>[browse, chat]) {
      expect(door.left, homeGutter, reason: 'stacked, each door spans the page');
      expect(door.right, width - homeGutter, reason: 'stacked, each door spans the page');
    }
    expect(chat.top - browse.bottom, homeDoorGap);
  }

  /// No word of [text] broken in the middle: the boxes its letters are drawn in share one line. A
  /// word that breaks puts its end on the next line down.
  void expectNoWordBroken(WidgetTester tester, String text, String where) {
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    for (final RegExpMatch word in RegExp(r'\S+').allMatches(text)) {
      final Set<double> lines = paragraph
          .getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end))
          .map((TextBox box) => box.top)
          .toSet();
      expect(lines, hasLength(1), reason: '"${word[0]}" breaks in the middle $where');
    }
  }

  void expectNotCutShort(WidgetTester tester, String text, String where) {
    expect(tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines, isFalse,
        reason: '"$text" loses its end to an ellipsis $where');
  }

  testWidgets('the browse and the chat sit side by side, in one row under the banner rail',
      (WidgetTester tester) async {
    await pumpHome(tester);

    final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
    // Under the rail, not above it where they used to be.
    expect(browse.top, greaterThanOrEqualTo(tester.getRect(bannerRail()).bottom));
    expectSideBySide(tester, 390);
    // In each tile, the disc and the chevron share the top line, with the words underneath.
    final Rect disc =
        tester.getRect(inDoor(en.dekkaneBrowseTitle, find.byIcon(Icons.storefront_rounded)));
    final Rect chevron =
        tester.getRect(inDoor(en.dekkaneBrowseTitle, find.byIcon(Icons.chevron_right)));
    expect(disc.center.dx, lessThan(chevron.center.dx));
    expect(tester.getRect(find.text(en.dekkaneBrowseTitle)).top, greaterThan(disc.bottom));
    // The rest of Home carries on underneath, in its old order.
    expect(tester.getRect(find.text(en.custActiveStoresNearby)).top, greaterThan(browse.bottom));
  });

  testWidgets('where a title word will not fit a half tile, the doors stack as the full-width '
      'cards, still under the banner rail', (WidgetTester tester) async {
    // 360dp is the width most Android phones have and x1.3 the commonest larger text. A half tile
    // would leave its words 126dp there, and "Neighbourhood" needs 134dp.
    await pumpHome(tester, width: 360, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expectStacked(tester, 360);
    final Rect browse = tester.getRect(doorOf(en.dekkaneBrowseTitle));
    final Rect chat = tester.getRect(doorOf(en.chatRoomEntryTitle));
    expect(browse.top, greaterThanOrEqualTo(tester.getRect(bannerRail()).bottom));
    // The full-width card: the words beside the disc, not under it.
    for (final (String title, IconData glyph) in <(String, IconData)>[
      (en.dekkaneBrowseTitle, Icons.storefront_rounded),
      (en.chatRoomEntryTitle, Icons.forum_rounded),
    ]) {
      final Rect disc = tester.getRect(inDoor(title, find.byIcon(glyph)));
      expect(tester.getRect(find.text(title)).left, greaterThan(disc.right));
    }
    expect(tester.getRect(find.text(en.custActiveStoresNearby)).top, greaterThan(chat.bottom));

    // Stacked, they are still the doors they were: the chat card opens the room.
    await tester.tap(doorOf(en.chatRoomEntryTitle));
    await tester.pumpAndSettle();
    expect(find.byType(NeighbourhoodChatScreen), findsOneWidget);
  });

  testWidgets('with no banner, the row takes the place the rail would have had',
      (WidgetTester tester) async {
    await pumpHome(tester);
    final double railTop = tester.getRect(bannerRail()).top;

    // The same Home again, from scratch, on a day the Backoffice has no banner up.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, banners: const <Map<String, dynamic>>[]);

    expect(bannerRail(), findsNothing);
    expect(tester.getRect(doorOf(en.dekkaneBrowseTitle)).top, railTop);
    expectSideBySide(tester, 390);
  });

  testWidgets('on a 320dp phone at normal text size the titles still fit the row, and each whole '
      'tile is a 48dp-plus target', (WidgetTester tester) async {
    await pumpHome(tester, width: 320);

    expect(tester.takeException(), isNull);
    expectSideBySide(tester, 320);
    for (final String title in titles) {
      // The ripple covers the tile edge to edge, so the tap target is the tile itself.
      final Rect target = tester.getRect(inDoor(title, find.byType(InkWell)));
      expect(target, tester.getRect(doorOf(title)));
      expect(target.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(target.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    }
  });

  testWidgets('with large text on a 390dp phone the titles still fit, and the tiles grow taller '
      'together', (WidgetTester tester) async {
    await pumpHome(tester);
    final double normalHeight = tester.getSize(doorOf(en.dekkaneBrowseTitle)).height;

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expectSideBySide(tester, 390);
    expect(tester.getSize(doorOf(en.dekkaneBrowseTitle)).height, greaterThan(normalHeight));
  });

  testWidgets('the chat tile opens the neighbourhood room, even tapped low on the tile',
      (WidgetTester tester) async {
    await pumpHome(tester);

    // Below the words, where only the tile's own padding (and whatever height the row's stretch
    // added) is: still the chat's door, not a dead strip.
    await tester.tapAt(tester.getRect(doorOf(en.chatRoomEntryTitle)).bottomCenter -
        const Offset(0, DeliverySpacing.xs));
    await tester.pumpAndSettle();

    expect(find.byType(NeighbourhoodChatScreen), findsOneWidget);
  });

  // Every width and text size the row has to decide at: side by side exactly where every title
  // word fits a half tile, stacked where one does not, and never a word broken or a line lost.
  for (final (double width, double textScale, bool sideBySide) in <(double, double, bool)>[
    (320, 1.0, true), // 104dp in 106
    (360, 1.0, true), // 104 in 126
    (390, 1.0, true), // 104 in 141
    (390, 1.3, true), // 134 in 141
    (320, 1.3, false), // 134 in 106
    (360, 1.3, false), // 134 in 126
  ]) {
    final String where = 'at ${width.round()}dp with text at x$textScale';
    testWidgets('$where the doors are ${sideBySide ? 'side by side' : 'stacked'}, and no word '
        'on them is broken or cut short', (WidgetTester tester) async {
      await pumpHome(tester, width: width, textScale: textScale);

      expect(tester.takeException(), isNull);
      sideBySide ? expectSideBySide(tester, width) : expectStacked(tester, width);
      for (final String text in <String>[...titles, ...subtitles]) {
        expectNoWordBroken(tester, text, where);
        expectNotCutShort(tester, text, where);
      }
    });
  }

  // Text at x2: stacked at every phone width under 390dp, and a title word is then wider than even
  // the full card's line ("neighbourhood" is 233dp at the card's 15sp, the line 176dp at 320dp and
  // 216dp at 360dp), so it has to break inside the word. What it must not do is lose its end. The
  // feed is left empty here: the shop grid's cards have a fixed height of their own, which text at
  // x2 overflows whatever the doors do.
  for (final double width in <double>[320, 360]) {
    testWidgets('at ${width.round()}dp with text at x2 the doors stack, and no title is cut short',
        (WidgetTester tester) async {
      await pumpHome(tester, width: width, textScale: 2.0, withShops: false);

      expect(tester.takeException(), isNull);
      expectStacked(tester, width);
      for (final String title in titles) {
        expectNotCutShort(tester, title, 'at ${width.round()}dp with text at x2');
      }
    });
  }
}
