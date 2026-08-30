import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The platform's display rates — today, LBP per USD.
///
/// Every price is stored and paid in USD; the Lebanese frames draw each one twice —
/// "$3.50 (315,000 LBP)" — and the second figure is a CONVERSION at one platform-wide rate the
/// server owns. This holder is fetched once per session and read by every price on screen, which
/// is why it is a singleton [ChangeNotifier] rather than a value threaded through a dozen
/// constructors: the rate is one fact about the market, not a property of any screen.
///
/// Unknown (never fetched, or the server said zero) renders NO second figure. A price without its
/// LBP line is incomplete; a price with a stale invented rate is wrong, which is worse.
class MarketRates extends ChangeNotifier {
  MarketRates._();

  static final MarketRates instance = MarketRates._();

  double _lbpPerUsd = 0;

  double get lbpPerUsd => _lbpPerUsd;

  bool get hasLbp => _lbpPerUsd > 0;

  /// Fetches the rate through the given client. Quiet on failure: the app works USD-only until a
  /// later fetch lands, exactly as it would on a market with no second currency.
  Future<void> load(Dio dio) async {
    try {
      final Response<dynamic> response = await dio.get<dynamic>('/api/market/config');
      final num? rate = (response.data as Map<String, dynamic>)['lbpPerUsd'] as num?;
      if (rate != null && rate.toDouble() != _lbpPerUsd) {
        _lbpPerUsd = rate.toDouble();
        notifyListeners();
      }
    } catch (_) {
      // USD-only until a retry lands.
    }
  }

  /// "315,000 LBP" for a dollar amount, or null when there is no rate to convert with.
  ///
  /// Rounded to the nearest thousand — the design's own figures do exactly that, and no LBP note
  /// smaller than a thousand exists to be owed.
  String? lbp(double usd) {
    if (!hasLbp) return null;
    final int thousands = (usd * _lbpPerUsd / 1000).round();
    return '${_group(thousands * 1000)} LBP';
  }

  /// "(315,000 LBP)" — the parenthesised secondary form most rows use.
  String? lbpParen(double usd) {
    final String? value = lbp(usd);
    return value == null ? null : '($value)';
  }

  static String _group(int amount) {
    final String digits = amount.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
