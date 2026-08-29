import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adding a photo to a product, and the failure that had no symptom.
///
/// Reported as "unable to add photos for product in merchant". The server was healthy the whole
/// time — presign, the PUT to storage and the confirm all answered, and the service log showed no
/// attempt from the device at all, which is what placed the fault before the network.
///
/// The cause was a shape, not a bug in the upload: `openFile` was called OUTSIDE the try that
/// wrapped everything after it. Anything the platform picker threw — a plugin missing, an OS that
/// refused to open the dialog — escaped the method as an unhandled async error. No snackbar, no
/// spinner, no message: the button simply did nothing, which is indistinguishable from a dead
/// control and impossible to report usefully.
///
/// So what is pinned here is not that uploading works. It is that a picker failure is VISIBLE, and
/// that a cancel is still not treated as one.
class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector({this.throws, this.returns});

  /// What `openFile` should throw, if anything.
  final Object? throws;

  /// What it should return otherwise. Null models the user cancelling the dialog.
  final XFile? returns;

  int calls = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls++;
    if (throws != null) throw throws!;
    return returns;
  }
}

/// Answers the product read that follows a successful upload. Never reached in these tests.
class _IdleAdapter implements HttpClientAdapter {
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    return ResponseBody.fromString('{}', 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _IdleAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = _IdleAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  });

  /// An EXISTING product: the dropzone is deliberately inert until the first save, so a new
  /// product could never have reproduced this.
  const Product saved = Product(
    id: '8f549de7-bff4-4715-8657-c62819db1ef4',
    merchantId: '7da2f05c-e5b5-476b-97d6-a45e49ad40b5',
    name: 'Margherita',
    description: 'Tomato, mozzarella, basil',
    price: 12.50,
    status: ProductStatus.draft,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: ProductFormScreen(api: CatalogApi(dio), existing: saved),
    ));
    // Fixed frames rather than pumpAndSettle: the form carries a continuous animation
    // (the dropzone's dashed border pulse), so settling never completes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapTheDropzone(WidgetTester tester) async {
    final Finder cta = find.text(DeliveryStrings.of(
            tester.element(find.byType(ProductFormScreen)))
        .merchbUploadImageCta);
    expect(cta, findsOneWidget, reason: 'the add-a-photo control should be on an existing product');
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a picker that throws is reported, not swallowed', (WidgetTester tester) async {
    final _FakeFileSelector picker =
        _FakeFileSelector(throws: Exception('MissingPluginException(openFile)'));
    FileSelectorPlatform.instance = picker;

    await pump(tester);
    await tapTheDropzone(tester);

    expect(picker.calls, 1);
    // The symptom that was reported: before the fix this assertion failed because NOTHING was
    // shown — the exception left the method and the screen sat there unchanged.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('MissingPluginException'), findsOneWidget,
        reason: 'the reason has to reach the screen, or nobody can report what went wrong');
    // And nothing was uploaded: the categories read the form does on open is the only traffic.
    expect(adapter.calls.where((String c) => c.contains("images")), isEmpty);
  });

  testWidgets('cancelling the dialog is silent, because it is not a failure',
      (WidgetTester tester) async {
    final _FakeFileSelector picker = _FakeFileSelector();
    FileSelectorPlatform.instance = picker;

    await pump(tester);
    await tapTheDropzone(tester);

    expect(picker.calls, 1);
    // The other half of the fix, and the easier one to get wrong: swallowing the throw into the
    // same "returned null" path would turn every real failure into a silent cancel again.
    expect(find.byType(SnackBar), findsNothing);
    expect(adapter.calls.where((String c) => c.contains("images")), isEmpty,
        reason: 'a cancel must not upload anything; the categories read on open is unrelated');
  });
}
