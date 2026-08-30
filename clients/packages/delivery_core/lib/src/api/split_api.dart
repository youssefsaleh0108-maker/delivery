import 'package:dio/dio.dart';

/// Group split payment (Figma 83:*): the host's plan, the invitees' answers, the rider's
/// checklist. The wire addresses people by USERNAME — the token's own preferred_username is what
/// matches an invitee to their share.
class SplitApi {
  SplitApi(this._dio);

  final Dio _dio;

  Future<SplitPlan> create({
    required String mode,
    required double totalUsd,
    String? storeName,
    required List<SplitShareDraft> shares,
  }) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/transfers/splits', data: <String, dynamic>{
      'mode': mode,
      'totalUsd': totalUsd,
      if (storeName != null) 'storeName': storeName,
      'shares': shares
          .map((SplitShareDraft s) => <String, dynamic>{
                if (s.username != null) 'username': s.username,
                'name': s.name,
                'amountUsd': s.amountUsd,
                if (s.itemsCount != null) 'itemsCount': s.itemsCount,
              })
          .toList(),
    });
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<SplitPlan>> mine() => _list('/api/transfers/splits/mine');

  /// The invitations waiting on this account — what the home banner polls.
  Future<List<SplitPlan>> requests() => _list('/api/transfers/splits/requests');

  Future<List<SplitPlan>> _list(String path) async {
    final Response<dynamic> response = await _dio.get<dynamic>(path);
    return (response.data as List<dynamic>)
        .map((dynamic e) => SplitPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SplitPlan> read(String id) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/transfers/splits/$id');
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }

  /// Pays the caller's own share via [method], or declines when [accept] is false.
  Future<SplitPlan> answer(String id, {required bool accept, String? method}) async {
    final Response<dynamic> response = await _dio
        .post<dynamic>('/api/transfers/splits/$id/answer', data: <String, dynamic>{
      'accept': accept,
      if (method != null) 'method': method,
    });
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SplitPlan> cover(String id) => _act(id, 'cover');

  Future<SplitPlan> remind(String id) => _act(id, 'remind');

  Future<SplitPlan> cancel(String id) => _act(id, 'cancel');

  Future<SplitPlan> attachOrder(String id, String orderId) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/transfers/splits/$id/attach-order',
        data: <String, dynamic>{'orderId': orderId});
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }

  /// The plan behind an order — the rider's cash checklist and the completion summary.
  Future<SplitPlan> forOrder(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/transfers/splits/for-order/$orderId');
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SplitPlan> _act(String id, String verb) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/transfers/splits/$id/$verb');
    return SplitPlan.fromJson(response.data as Map<String, dynamic>);
  }
}

/// A share as the host proposes it.
class SplitShareDraft {
  const SplitShareDraft({
    this.username,
    required this.name,
    required this.amountUsd,
    this.itemsCount,
  });

  /// Null = a guest with no app, committed as cash at the door.
  final String? username;
  final String name;
  final double amountUsd;
  final int? itemsCount;
}

/// One person's slice, as the server tells it.
class SplitShare {
  const SplitShare({
    required this.id,
    this.username,
    required this.name,
    required this.amountUsd,
    this.itemsCount,
    required this.status,
    this.method,
  });

  final String id;
  final String? username;
  final String name;
  final double amountUsd;
  final int? itemsCount;

  /// PENDING / PAID / DECLINED / COVERED.
  final String status;

  /// CASH_ON_DELIVERY / WHISH / OMT / BOB / CASH_AT_DOOR / HOST_ORDER; null while pending.
  final String? method;

  bool get settled => status != 'PENDING';

  factory SplitShare.fromJson(Map<String, dynamic> json) => SplitShare(
        id: json['id'] as String,
        username: json['username'] as String?,
        name: json['name'] as String? ?? '',
        amountUsd: (json['amountUsd'] as num?)?.toDouble() ?? 0,
        itemsCount: (json['itemsCount'] as num?)?.toInt(),
        status: json['status'] as String? ?? 'PENDING',
        method: json['method'] as String?,
      );
}

/// The whole plan.
class SplitPlan {
  const SplitPlan({
    required this.id,
    required this.hostUsername,
    required this.hostName,
    this.storeName,
    this.orderId,
    required this.mode,
    required this.status,
    required this.totalUsd,
    required this.rateUsed,
    this.expiresAt,
    required this.shares,
  });

  final String id;
  final String hostUsername;
  final String hostName;
  final String? storeName;
  final String? orderId;

  /// EVEN or ITEMIZED.
  final String mode;

  /// COLLECTING / READY / PLACED / CANCELLED / EXPIRED.
  final String status;
  final double totalUsd;
  final double rateUsed;
  final DateTime? expiresAt;
  final List<SplitShare> shares;

  int get paidCount => shares.where((SplitShare s) => s.settled && s.status != 'DECLINED').length;

  double get collectedUsd => shares
      .where((SplitShare s) => s.settled && s.status != 'DECLINED')
      .fold(0, (double sum, SplitShare s) => sum + s.amountUsd);

  factory SplitPlan.fromJson(Map<String, dynamic> json) => SplitPlan(
        id: json['id'] as String,
        hostUsername: json['hostUsername'] as String? ?? '',
        hostName: json['hostName'] as String? ?? '',
        storeName: json['storeName'] as String?,
        orderId: json['orderId'] as String?,
        mode: json['mode'] as String? ?? 'EVEN',
        status: json['status'] as String? ?? 'COLLECTING',
        totalUsd: (json['totalUsd'] as num?)?.toDouble() ?? 0,
        rateUsed: (json['rateUsed'] as num?)?.toDouble() ?? 0,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'] as String),
        shares: (json['shares'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => SplitShare.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
