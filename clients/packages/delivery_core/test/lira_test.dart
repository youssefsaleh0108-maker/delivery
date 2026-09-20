import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// RECON-14: the one lira rule the apps convert with, against transfer-service's own.
///
/// The server's rule, in exact decimals: `HALF_UP(usd x rate / 1000) x 1000`
/// (`MoneyTransfer.lbpFaceOf`). Here it is in integers, and the halfway cases — where the `double`
/// version fell a note short — are the point.
void main() {
  /// The server's arithmetic, written as the deep test wrote it.
  int server(int cents, int rate) => ((cents * rate + 50000) ~/ 100000) * 1000;

  test('the halves the double version lost', () {
    // 1.15 x 90,000 = 103,500 exactly: the note above, as the ledger and the rider say.
    expect(lbpFaceOf(1.15, 90000), 104000);
    expect(lbpFaceOf(0.35, 90000), 32000);
    expect(lbpFaceOf(19.65, 90000), 1769000);
  });

  test('every cent from 0.01 to 200.00 converts as the server does, at three rates', () {
    for (final int rate in <int>[90000, 89500, 1]) {
      final List<String> wrong = <String>[];
      for (int cents = 1; cents <= 20000; cents++) {
        final int expected = server(cents, rate);
        if (lbpFaceOfCents(cents, rate) != expected ||
            lbpFaceOf(cents / 100, rate) != expected) {
          wrong.add('$cents at $rate');
        }
      }
      expect(wrong, isEmpty, reason: '${wrong.length} differ, e.g. ${wrong.take(5)}');
    }
  });

  test('dollars become cents first, exactly as the server rounds them', () {
    expect(usdCents(1.15), 115);
    expect(usdCents(0.005), 1);
    expect(usdCents(10.004999), 1000);
    expect(usdCents(10.005001), 1001);
    // A sum of doubles that lands a hair below its cent is still that cent.
    expect(usdCents(0.1 + 0.2), 30);
  });

  test('no rate converts to nothing, and zero is zero', () {
    expect(lbpFaceOf(19.50, 0), 0);
    expect(lbpFaceOf(0, 90000), 0);
    expect(lbpFaceOfCents(0, 90000), 0);
  });

  test('a negative amount rounds away from zero, as HALF_UP does', () {
    expect(lbpFaceOf(-1.15, 90000), -104000);
    expect(lbpFaceOf(-0.35, 90000), -32000);
  });

  test('every answer is a note that exists', () {
    for (int cents = 1; cents <= 500; cents++) {
      expect(lbpFaceOfCents(cents, 89500) % lbpNote, 0);
    }
  });
}
