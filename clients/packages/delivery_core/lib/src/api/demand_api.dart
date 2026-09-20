import 'package:dio/dio.dart';

import '../models/demand_models.dart';

/// The merchant Demand Radar's two reads: how busy the areas around one shop are, and what those
/// areas looked for and could not find.
///
/// MERCHANT for their own shop (BACKOFFICE for any). The shop is named by id because an account can
/// hold more than one; the server checks that it is the caller's and answers 404 otherwise. Which
/// areas are counted is decided on the server from the shop, so nothing sent from here can widen
/// them — and nothing personal travels in either query: a store id and a window, never a location
/// and never a customer.
///
/// Two services answer them. Density is Order Manager's, off orders; the unmet words are Product
/// Service's, off the search log. One class because they are one screen and one idea — what the
/// neighbourhood is doing — and because a merchant who could read one but not the other would get a
/// half-answer with no way to tell which half was missing.
class DemandApi {
  DemandApi(this._dio);

  final Dio _dio;

  /// The windows the screen offers, and the only ones the server answers: anything else is a 400.
  /// Each answer is the snapshot for the window's last fixed boundary — the quarter hour for the
  /// hour, the hour for the day, midnight UTC for the week — so asking more often changes nothing.
  static const int lastHour = 60;
  static const int lastDay = 24 * 60;
  static const int lastWeek = 7 * 24 * 60;

  Future<DemandDensity> density({required String storeId, int windowMinutes = lastHour}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/orders/demand/density',
      queryParameters: <String, dynamic>{'storeId': storeId, 'windowMinutes': windowMinutes},
    );
    return DemandDensity.fromJson(response.data as Map<String, dynamic>);
  }

  /// What the shop's own areas searched for and could not find, this week and last.
  ///
  /// No window to choose: a week is the unit, because a word is only shown once enough different
  /// searches asked for it in one, and a shorter window would either never reach that floor or
  /// reach it with too few people behind it. The server decides both weeks from its own calendar,
  /// so the client cannot ask for a slice of its own choosing.
  Future<UnmetDemand> unmet({required String storeId}) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/products/demand/unmet/$storeId');
    return UnmetDemand.fromJson(response.data as Map<String, dynamic>);
  }
}
