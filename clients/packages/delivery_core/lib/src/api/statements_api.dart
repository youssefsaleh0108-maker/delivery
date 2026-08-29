import 'package:dio/dio.dart';

import '../models/statement_models.dart';

/// Client for the counterparty statements API.
///
/// Two audiences on two sets of routes, and the split is the point. The Backoffice routes name a
/// counterparty because an operator is by definition looking at somebody else's money; [mine] names
/// nobody, because whose statement it returns is decided by the token and can never be steered by a
/// parameter. There is deliberately no method here that lets a merchant or a rider pass a ref — the
/// server would refuse it, and offering it in the client would invite somebody to try.
///
/// Nothing here computes a total. Every figure on screen is a string the ledger wrote; see [Money].
class StatementsApi {
  StatementsApi(this._dio);

  final Dio _dio;

  /// The longest range the server will accept. Enforced here too — see [_range].
  static const int maxRangeDays = 366;

  // ---------------------------------------------------------------- backoffice

  /// Everyone with activity between [from] and [to] inclusive, with their headline figure and
  /// whatever could not be attributed to anybody.
  ///
  /// BACKOFFICE only; 403 for anyone else. Read [CounterpartyListing.unattributed] as well as the
  /// rows — money that names no counterparty is still money, and a list that only shows the rows
  /// balances on screen and not in the bank.
  Future<CounterpartyListing> counterparties({
    required DateTime from,
    required DateTime to,
  }) =>
      _counterparties(_range(from, to));

  /// One counterparty's statement. BACKOFFICE only.
  ///
  /// [kind] is the wire string — `CounterpartyKind.wire`, or `kindWire` straight off a listing row.
  /// A string rather than the enum on purpose: a kind the server adds after this build shipped
  /// still appears in the listing, and a screen that can show a row must be able to open it.
  Future<Statement> statement({
    required String kind,
    required String ref,
    required DateTime from,
    required DateTime to,
  }) =>
      _statement(_statementPath(kind, ref), _range(from, to));

  /// Sends the statement for that range to the counterparty. BACKOFFICE only.
  ///
  /// [recipient] overrides the address the server resolved. Leave it null to use the resolved one —
  /// and expect a 409 when there is none, which is the server saying "tell me where to send it",
  /// not that anything went wrong. [CounterpartySummary.needsRecipient] answers that before the
  /// operator presses anything.
  ///
  /// This puts a statement in front of a real business. It is the one method on this client with a
  /// consequence outside the browser, so nothing should call it without an explicit human press.
  Future<StatementDispatch> sendStatement({
    required String kind,
    required String ref,
    required DateTime from,
    required DateTime to,
    String? recipient,
  }) =>
      _send('${_statementPath(kind, ref)}/send', _range(from, to), recipient);

  // ---------------------------------------------------------------- self-serve

  /// The caller's own statement, for the merchant app, the rider app and a carrier reading their
  /// own console.
  ///
  /// The kind is resolved server-side from the realm role, which is why there is no parameter for
  /// it. A role with no statement of its own — a customer — gets 403; that is a correct answer, not
  /// a fault, and a screen should not offer the route to those roles in the first place.
  Future<Statement> mine({required DateTime from, required DateTime to}) =>
      _statement('/api/accounting/statements/mine', _range(from, to));

  // ---------------------------------------------------------------- internals

  Future<CounterpartyListing> _counterparties(Map<String, dynamic> range) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/accounting/statements/counterparties',
      queryParameters: range,
    );
    return CounterpartyListing.fromJson(response.data as Map<String, dynamic>);
  }

  /// Both statement routes return the same shape, because they differ in who may call them rather
  /// than in what comes back.
  Future<Statement> _statement(String path, Map<String, dynamic> range) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>(path, queryParameters: range);
    return Statement.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StatementDispatch> _send(
      String path, Map<String, dynamic> range, String? recipient) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      path,
      queryParameters: range,
      // `to` in the body is the address, not the end of the range — the range travels in the query
      // and only there. An empty body is the documented way to say "use whoever you resolved".
      data: <String, dynamic>{
        if (recipient != null && recipient.isNotEmpty) 'to': recipient,
      },
    );
    return StatementDispatch.fromJson(response.data as Map<String, dynamic>);
  }

  /// Both segments are encoded. A ref is a server-issued id today, but a path built by
  /// concatenation is one odd id away from addressing a different endpoint entirely.
  static String _statementPath(String kind, String ref) =>
      '/api/accounting/statements/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(ref)}';

  /// The inclusive range as the two query parameters, refusing what the server would refuse.
  ///
  /// The server is the authority and answers 400 on both of these. Checking here as well turns a
  /// round trip that cannot succeed into an immediate failure, and it is raised synchronously —
  /// before the async gap — because an inverted range is two date pickers wired the wrong way
  /// round. That should throw where it was written, not arrive later as a failed future that a
  /// screen renders next to genuine network errors.
  static Map<String, dynamic> _range(DateTime from, DateTime to) {
    final DateTime start = _dayOf(from);
    final DateTime end = _dayOf(to);
    if (end.isBefore(start)) {
      throw ArgumentError('Statement range is inverted: $from is after $to');
    }
    // Inclusive, so a single day spans zero days of difference.
    final int days = end.difference(start).inDays + 1;
    if (days > maxRangeDays) {
      throw ArgumentError('Statement range is $days days; the server allows $maxRangeDays');
    }
    return <String, dynamic>{'from': _isoDate(from), 'to': _isoDate(to)};
  }

  /// Midnight UTC of the same calendar day, used only for counting days. UTC so that a range
  /// crossing a daylight-saving change is not 366 days and one hour.
  static DateTime _dayOf(DateTime value) => DateTime.utc(value.year, value.month, value.day);

  /// `yyyy-MM-dd` from the date the caller actually picked.
  ///
  /// Deliberately not `toUtc().toIso8601String()`: for a reader east of Greenwich that turns the
  /// first of the month into the last of the previous one, and the statement is then short a day at
  /// one end and long at the other.
  static String _isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';
}
