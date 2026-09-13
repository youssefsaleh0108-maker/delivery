import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two things the nearby search's answer now carries besides its shops: whether the search
/// reached its candidate ceiling, and, per shop, whether its power declaration still counts as now.
void main() {
  Map<String, dynamic> card({bool? powerCurrent, String? powerUpdatedAt}) => <String, dynamic>{
        'id': 's1',
        'slug': 's1',
        'name': 'Abu Hassan Mini Market',
        'vertical': 'GROCERY',
        'availability': 'OPEN',
        'powerStatus': 'GENERATOR',
        if (powerCurrent != null) 'powerCurrent': powerCurrent,
        if (powerUpdatedAt != null) 'powerUpdatedAt': powerUpdatedAt,
      };

  group('a nearby page', () {
    test('says whether the search reached its ceiling, and what the ceiling is', () {
      final NearbyPage page = NearbyPage.fromJson(<String, dynamic>{
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'store': card(),
            'latitude': 33.8975,
            'longitude': 35.5241,
            'distanceMetres': 350,
          },
        ],
        'page': 0,
        'totalElements': 1,
        'totalPages': 1,
        'truncated': true,
        'candidateLimit': 500,
      });

      expect(page.content.single.distanceMetres, 350);
      expect(page.totalElements, 1);
      expect(page.truncated, isTrue);
      expect(page.candidateLimit, 500);
    });

    test('from a server that does not say, was not truncated', () {
      final NearbyPage page = NearbyPage.fromJson(<String, dynamic>{
        'content': <dynamic>[],
        'page': 0,
        'totalElements': 0,
        'totalPages': 0,
      });

      expect(page.truncated, isFalse);
      expect(page.candidateLimit, isNull);
    });
  });

  group('a power declaration', () {
    test('carries when it was made and whether it still counts as now', () {
      final StoreCard fresh =
          StoreCard.fromJson(card(powerCurrent: true, powerUpdatedAt: '2026-09-13T08:00:00Z'));

      expect(fresh.powerCurrent, isTrue);
      expect(fresh.powerUpdatedAt, DateTime.utc(2026, 9, 13, 8));
    });

    test('from a server that does not say is not presented as current', () {
      final StoreCard unsaid = StoreCard.fromJson(card());

      expect(unsaid.powerCurrent, isFalse);
      expect(unsaid.powerUpdatedAt, isNull);
    });

    test('survives the full store becoming a card, and a favourite toggle', () {
      final Store store =
          Store.fromJson(card(powerCurrent: true, powerUpdatedAt: '2026-09-13T08:00:00Z'));

      expect(store.toCard().powerCurrent, isTrue);
      expect(store.toCard().powerUpdatedAt, DateTime.utc(2026, 9, 13, 8));
      expect(store.copyWith(favorite: true).powerCurrent, isTrue);
      expect(StoreCard.fromJson(card(powerCurrent: true)).copyWith(favorite: true).powerCurrent,
          isTrue);
    });
  });
}
