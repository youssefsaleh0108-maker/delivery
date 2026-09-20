/// Lebanese lira, counted exactly as transfer-service counts them.
///
/// The server fixes a lira figure in exact decimals: dollars to the cent, the rate in whole lira,
/// and the product rounded HALF_UP to the nearest 1,000-lira note (`MoneyTransfer.lbpFaceOf`, and
/// the same rule over a split plan's shares). The apps did the same arithmetic in `double`, which
/// lands just short of a halfway figure: 1.15 x 90,000 is 103,499.99999999999 as a double, so a
/// customer saw 103,000 LBP where the ledger — and the rider at the door — say 104,000. Twenty-two
/// of the 2,000 cent amounts from 0.01 to 20.00 came out a note apart (RECON-14).
///
/// Integers have no such halves, so every lira figure in the apps comes from here.
library;

/// The smallest note in circulation. Nothing below it can be handed over, and there is no coinage
/// to settle a remainder with, so it is part of the amount rather than a presentation detail.
const int lbpNote = 1000;

/// [usd] in whole cents, HALF_UP — the scale every server figure is already held at, and the first
/// thing the server does with an amount it is given.
int usdCents(double usd) => (usd * 100).round();

/// The lira note [cents] US cents are handed over in, at [lbpPerUsd] lira to the dollar.
///
/// The server's rule in integers: `cents x rate` is hundredths of a lira exactly, and that is
/// rounded HALF_UP to the nearest note. The rate is taken as whole lira, as the server normalises
/// it; without one there is nothing to convert with and the answer is zero.
int lbpFaceOfCents(int cents, num lbpPerUsd) {
  final int rate = lbpPerUsd.round();
  if (rate <= 0) return 0;
  const int noteInHundredths = lbpNote * 100;
  final int hundredths = cents * rate;
  final int notes = (hundredths.abs() + noteInHundredths ~/ 2) ~/ noteInHundredths;
  return hundredths.isNegative ? -notes * lbpNote : notes * lbpNote;
}

/// The lira note [usd] is handed over in. Dollars become cents first, exactly as on the server.
int lbpFaceOf(double usd, num lbpPerUsd) => lbpFaceOfCents(usdCents(usd), lbpPerUsd);
