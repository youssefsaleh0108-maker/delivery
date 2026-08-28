import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's bank record.
///
/// The Settings row for it wore a "Soon" chip on the claim that no merchant payout or bank record
/// exists anywhere on the platform. It does: it is filed against the *application*, and
/// `GET /api/onboarding/applications/mine/payout` resolves that application from the caller's
/// token rather than from a role, so it answers a merchant exactly as it answers a rider.
///
/// What these pin is the pair of facts that the chip got wrong and that a future edit could get
/// wrong again — the row is a live route when the host wires the client, and the page shows the
/// record the server actually holds — plus the two failure modes that matter on a page about
/// somebody's money: a 404 is "nothing was filed", and a *failure* is never allowed to read as
/// "nothing was filed".
class _PayoutAdapter implements HttpClientAdapter {
  _PayoutAdapter({this.status = 200});

  /// 200 with a record, 404 for an account that never did the bank step, 500 for a bad day.
  final int status;

  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (status != 200) {
      return ResponseBody.fromString('{}', status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'accountHolder': 'Falafel King SARL',
        'iban': 'LB62099900000001001901229114',
        'verificationState': 'CHECKSUM_ONLY',
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<_PayoutAdapter> _pumpPage(WidgetTester tester, {int status = 200}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _PayoutAdapter adapter = _PayoutAdapter(status: status);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantPayoutScreen(api: DocumentsApi(dio)),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

Future<void> _pumpSettings(WidgetTester tester, {DocumentsApi? documents}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantSettingsScreen(
      locale: LocaleController(
        read: () async => 'en',
        write: (_) async {},
      ),
      accountName: 'Falafel King',
      documents: documents,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  group('the Settings row', () {
    testWidgets('is a live route once the host wires the client',
        (WidgetTester tester) async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
        ..httpClientAdapter = _PayoutAdapter();
      await _pumpSettings(tester, documents: DocumentsApi(dio));

      expect(find.text(en.merchbPaymentBankDetails), findsOneWidget);
      // The whole point: no chip on THIS row any more. The two that remain belong to the
      // analytics and notification rows, which this harness deliberately leaves unwired.
      expect(find.byType(YdComingSoon), findsNWidgets(2));

      await tester.tap(find.text(en.merchbPaymentBankDetails));
      await tester.pumpAndSettle();
      expect(find.byType(MerchantPayoutScreen), findsOneWidget);
    });

    testWidgets('still says so when the host wired nothing',
        (WidgetTester tester) async {
      await _pumpSettings(tester);

      // A chip here is now a statement about this host's wiring, not about the platform — and it
      // must stay, because a row that silently does nothing is worse than one that says it cannot.
      // Three rows unwired instead of two.
      expect(find.byType(YdComingSoon), findsNWidgets(3));
    });
  });

  group('the page', () {
    testWidgets('reads the applicant route and shows the record',
        (WidgetTester tester) async {
      final _PayoutAdapter adapter = await _pumpPage(tester);

      expect(adapter.calls,
          contains('GET /api/onboarding/applications/mine/payout'));
      expect(find.text('Falafel King SARL'), findsOneWidget);
      // YdBadge uppercases by design.
      expect(find.text(en.payoutFormatChecked.toUpperCase()), findsOneWidget);
    });

    testWidgets('masks all but the last four of the number',
        (WidgetTester tester) async {
      await _pumpPage(tester);

      // The wizard shows the whole number, because there the owner is checking one they just
      // typed. Here they are being reminded which account is on file, and this screen can be open
      // on a counter with customers on the other side of it.
      expect(find.textContaining('001901229114'), findsNothing);
      expect(find.textContaining('9114'), findsOneWidget);
    });

    testWidgets('says the step was never done when the server has no record',
        (WidgetTester tester) async {
      await _pumpPage(tester, status: 404);

      expect(find.text(en.merchbBankNoneFiled), findsOneWidget);
      expect(find.text(en.riderPayoutCouldNotLoad), findsNothing);
    });

    testWidgets('never reads a failed request as an empty bank record',
        (WidgetTester tester) async {
      await _pumpPage(tester, status: 500);

      // The distinction this test exists for: "we could not ask" and "you never told us" are
      // different sentences, and telling a shop owner the second when the first is true sends
      // them looking for a problem that is not theirs.
      expect(find.text(en.riderPayoutCouldNotLoad), findsOneWidget);
      expect(find.text(en.merchbBankNoneFiled), findsNothing);
      expect(find.text(en.tryAgain), findsOneWidget);
    });
  });
}
