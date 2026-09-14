import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalogue the list reads: the products the test hands it, and no categories.
class _FakeCatalog extends CatalogApi {
  _FakeCatalog(this.products) : super(Dio());

  final List<Product> products;

  @override
  Future<Paged<Product>> myProducts({
    String? storeId,
    ProductStatus? status,
    int page = 0,
    int size = 20,
  }) async =>
      Paged<Product>(
        content: products,
        page: 0,
        totalElements: products.length,
        totalPages: 1,
      );

  @override
  Future<List<Category>> categories() async => const <Category>[];
}

Product _product(String name, ProductStatus status) => Product(
      id: 'id-$name',
      merchantId: 'merchant-1',
      name: name,
      price: 4.5,
      status: status,
    );

void main() {
  /// PAUSED arrived with service offers, after this list was written for DRAFT, ACTIVE and ARCHIVED.
  /// The list reads every product the merchant owns, not one shop's, so a merchant who also runs a
  /// service shop sees a paused offer in it. The offer is off sale for now with nothing to fix, so it
  /// reads "Off-shelf", as an archived product does, and never "Draft", which tells the merchant
  /// something is missing.
  testWidgets('a paused service offer reads Off-shelf, beside a live product and a draft',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: ProductListScreen(
        api: _FakeCatalog(<Product>[
          _product('Business cards', ProductStatus.paused),
          _product('Flyers', ProductStatus.active),
          _product('Posters', ProductStatus.draft),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Business cards'), findsOneWidget);
    // One row per status, so each word appearing exactly once pins the paused row to "Off-shelf":
    // were it labelled as a draft, "Draft" would appear twice and "Off-shelf" not at all.
    expect(find.text('Off-shelf'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
