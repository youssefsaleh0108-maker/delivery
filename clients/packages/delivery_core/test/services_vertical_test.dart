import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SERVICES vertical on the client.
///
/// Two failures are pinned here. An app reads an unknown vertical as a restaurant, so SERVICES must
/// parse as itself. And every goods picker iterated `StoreVertical.values`, so the day the enum learned
/// the word, Home would have grown a Services chip and a goods merchant a vertical the server refuses
/// to move them into — which is what `pickerVerticals` is for.
void main() {
  group('StoreVertical', () {
    test('SERVICES parses as services, not as the restaurant an unknown vertical falls back to', () {
      expect(StoreVertical.fromWire('SERVICES'), StoreVertical.services);
      expect(StoreVertical.maybeFromWire('SERVICES'), StoreVertical.services);
      expect(StoreVertical.fromWire('SOMETHING_NEWER'), StoreVertical.restaurant);
    });

    test('pickerVerticals is every goods vertical, in the order Home always showed, and never services',
        () {
      expect(StoreVertical.pickerVerticals, <StoreVertical>[
        StoreVertical.restaurant,
        StoreVertical.coffee,
        StoreVertical.grocery,
        StoreVertical.convenience,
        StoreVertical.pharmacy,
        StoreVertical.electronics,
        StoreVertical.flowersGifts,
      ]);
      expect(StoreVertical.pickerVerticals, isNot(contains(StoreVertical.services)));
    });

    test('pickerVerticals cannot be changed by a screen that holds it', () {
      expect(() => StoreVertical.pickerVerticals.add(StoreVertical.services), throwsUnsupportedError);
    });
  });

  group('ServiceCategory', () {
    test('every wire value round-trips, and the taxonomy matches the server', () {
      for (final ServiceCategory category in ServiceCategory.values) {
        expect(ServiceCategory.maybeFromWire(category.wireValue), category);
      }
      expect(ServiceCategory.values.map((ServiceCategory c) => c.wireValue), <String>[
        'PRINTING',
        'TAILORING',
        'REPAIRS',
        'PHOTOGRAPHY',
        'CLEANING',
        'BEAUTY',
        'TUTORING',
      ]);
    });

    test('a category this app does not know is null, never filed under another one', () {
      expect(ServiceCategory.maybeFromWire('KNITTING'), isNull);
      expect(ServiceCategory.maybeFromWire(null), isNull);
    });

    test('every category and the vertical have a real label in English and in Arabic', () {
      final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
      final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
      for (final ServiceCategory category in ServiceCategory.values) {
        expect(category.labelIn(en), isNotEmpty);
        expect(category.labelIn(ar), isNot(category.labelIn(en)),
            reason: '${category.wireValue} has no Arabic label');
      }
      expect(ServiceCategory.tailoring.labelIn(en), 'Tailoring & alterations');
      expect(StoreVertical.services.labelIn(en), 'Services');
      expect(StoreVertical.services.labelIn(ar), 'خدمات');
    });

    test('Tailoring is scissors, no category wears a close or error glyph, and none shares one', () {
      expect(ServiceCategory.tailoring.icon, Icons.content_cut_rounded);
      final Set<IconData> closeOrError = <IconData>{
        Icons.cancel,
        Icons.cancel_outlined,
        Icons.highlight_off,
        Icons.close,
        Icons.close_rounded,
        Icons.error_outline,
      };
      for (final ServiceCategory category in ServiceCategory.values) {
        expect(closeOrError, isNot(contains(category.icon)), reason: category.wireValue);
      }
      expect(ServiceCategory.values.map((ServiceCategory c) => c.icon).toSet(),
          hasLength(ServiceCategory.values.length));
    });
  });

  group('the storefront API', () {
    late List<RequestOptions> requests;
    late Object? Function(RequestOptions) answer;

    Map<String, dynamic> page() => <String, dynamic>{
          'content': <dynamic>[],
          'page': 0,
          'totalElements': 0,
          'totalPages': 0,
          'truncated': false,
          'candidateLimit': 500,
        };

    StoreApi api() {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          handler.resolve(
              Response<dynamic>(requestOptions: options, statusCode: 200, data: answer(options)));
        },
      ));
      return StoreApi(dio);
    }

    setUp(() {
      requests = <RequestOptions>[];
      answer = (RequestOptions _) => page();
    });

    test('Home browse sends neither a vertical nor a service category', () async {
      await api().browseWith(const StoreFilters());

      expect(requests.single.queryParameters.containsKey('vertical'), isFalse);
      expect(requests.single.queryParameters.containsKey('serviceCategory'), isFalse);
    });

    test('a services browse sends both', () async {
      await api().browseWith(const StoreFilters(
          vertical: StoreVertical.services, serviceCategory: ServiceCategory.printing));

      expect(requests.single.queryParameters, containsPair('vertical', 'SERVICES'));
      expect(requests.single.queryParameters, containsPair('serviceCategory', 'PRINTING'));
    });

    test('near me sends them only when asked', () async {
      await api().nearby(33.8977, 35.4829);
      await api().nearby(33.8977, 35.4829,
          vertical: StoreVertical.services, serviceCategory: ServiceCategory.tailoring);

      expect(requests[0].queryParameters.containsKey('vertical'), isFalse);
      expect(requests[0].queryParameters.containsKey('serviceCategory'), isFalse);
      expect(requests[1].queryParameters, containsPair('vertical', 'SERVICES'));
      expect(requests[1].queryParameters, containsPair('serviceCategory', 'TAILORING'));
    });

    test('the open categories leave out a name this app cannot label', () async {
      answer = (RequestOptions _) => <String>['PRINTING', 'KNITTING', 'TAILORING'];

      expect(await api().serviceCategories(),
          <ServiceCategory>[ServiceCategory.printing, ServiceCategory.tailoring]);
      expect(requests.single.path, '/api/stores/service-categories');
    });

    test('a profile save sends the category only when it names one', () async {
      answer = (RequestOptions _) =>
          <String, dynamic>{'id': 's1', 'name': 'Al Fakhry Press', 'vertical': 'SERVICES'};

      await api().updateProfile('s1', name: 'Al Fakhry Press', vertical: StoreVertical.services);
      await api().updateProfile('s1',
          name: 'Al Fakhry Press',
          vertical: StoreVertical.services,
          serviceCategory: ServiceCategory.photography);

      expect((requests[0].data as Map<String, dynamic>).containsKey('serviceCategory'), isFalse);
      expect(requests[1].data, containsPair('serviceCategory', 'PHOTOGRAPHY'));
    });
  });

  group('the models', () {
    test('a service card and store say what the shop does, and a goods card says nothing', () {
      final StoreCard card = StoreCard.fromJson(<String, dynamic>{
        'id': 's1',
        'name': 'Al Fakhry Press',
        'vertical': 'SERVICES',
        'serviceCategory': 'PRINTING',
      });
      expect(card.vertical, StoreVertical.services);
      expect(card.serviceCategory, ServiceCategory.printing);
      expect(card.copyWith(favorite: true).serviceCategory, ServiceCategory.printing);

      final Store store = Store.fromJson(<String, dynamic>{
        'id': 's1',
        'name': 'Al Fakhry Press',
        'vertical': 'SERVICES',
        'serviceCategory': 'PRINTING',
      });
      expect(store.serviceCategory, ServiceCategory.printing);
      expect(store.toCard().serviceCategory, ServiceCategory.printing);
      expect(store.copyWith(favorite: true).serviceCategory, ServiceCategory.printing);

      expect(
          StoreCard.fromJson(<String, dynamic>{'id': 's2', 'name': 'Abu Hassan', 'vertical': 'GROCERY'})
              .serviceCategory,
          isNull);
    });

    test('clearing the refinements keeps the category a screen is about', () {
      const StoreFilters filters = StoreFilters(
          vertical: StoreVertical.services, serviceCategory: ServiceCategory.repairs, minRating: 4);

      expect(filters.cleared().serviceCategory, ServiceCategory.repairs);
      expect(filters.cleared().minRating, isNull);
      expect(filters.copyWith(clearServiceCategory: true).serviceCategory, isNull);
    });
  });
}
