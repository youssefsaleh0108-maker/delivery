/// Rider rating models mirroring the Order Manager `RiderRatingController`.
library;

/// What a customer left on one order, mirroring `RiderRatingController.RatingResponse`.
///
/// Returned to the customer who left it, so the app can show the stars already given rather than
/// offering to rate again.
class RiderRatingEntry {
  const RiderRatingEntry({
    required this.orderId,
    required this.riderId,
    required this.score,
    this.comment,
    this.createdAt,
  });

  final String orderId;
  final String riderId;

  /// 1 to 5, bounded server-side.
  final int score;

  /// Optional free text, stripped of markup before it was stored. Null when the customer wrote
  /// nothing.
  final String? comment;

  final DateTime? createdAt;

  factory RiderRatingEntry.fromJson(Map<String, dynamic> json) => RiderRatingEntry(
        orderId: json['orderId'] as String,
        riderId: json['riderId'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        createdAt: _date(json['createdAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// A rider's aggregate, mirroring `RiderRatingController.StandingResponse`.
///
/// The number the design puts next to a rider's name. Nothing individual is in here — no comments,
/// no customer ids, no single scores.
class RiderStanding {
  const RiderStanding({
    required this.riderId,
    required this.ratings,
    required this.stars,
    this.average,
  });

  final String riderId;

  /// Null when nobody has rated them yet. A new rider is unrated, not terrible — render "new",
  /// never a zero, because a zero shown as a score is a lie about somebody's livelihood.
  final double? average;

  /// How many ratings [average] is built from.
  final int ratings;

  /// How many of each score, keyed 1–5. The server always sends all five keys; missing ones read
  /// as zero all the same.
  final Map<int, int> stars;

  /// Whether there is a number to draw at all.
  bool get isRated => average != null;

  factory RiderStanding.fromJson(Map<String, dynamic> json) => RiderStanding(
        riderId: json['riderId'] as String? ?? '',
        average: (json['average'] as num?)?.toDouble(),
        ratings: (json['ratings'] as num?)?.toInt() ?? 0,
        stars: (json['stars'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
            (String k, dynamic v) =>
                MapEntry<int, int>(int.tryParse(k) ?? 0, (v as num?)?.toInt() ?? 0)),
      );
}

/// One written comment as a supervisor sees it, mirroring `RiderRatingController.CommentResponse`.
///
/// BACKOFFICE only, and deliberately without a customer id — see the controller.
class RiderRatingComment {
  const RiderRatingComment({required this.score, this.comment, this.createdAt});

  final int score;

  /// Null when the customer left stars without words.
  final String? comment;

  final DateTime? createdAt;

  factory RiderRatingComment.fromJson(Map<String, dynamic> json) => RiderRatingComment(
        score: (json['score'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        createdAt: RiderRatingEntry._date(json['createdAt']),
      );
}
