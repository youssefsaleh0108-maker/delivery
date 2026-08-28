import 'package:dio/dio.dart';

import '../models/activity_models.dart';
import '../models/catalog_models.dart';

/// Client for the Backoffice activity feed.
///
/// A poll, not a push: re-request page zero on an interval. Entries are immutable, so new rows only
/// ever prepend — a refresh that finds the same first row has found nothing new.
class ActivityApi {
  ActivityApi(this._dio);

  final Dio _dio;

  /// One page of the feed, newest first. BACKOFFICE only.
  Future<Paged<ActivityEntry>> feed({int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/orders/activity',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<ActivityEntry>.fromJson(
        response.data as Map<String, dynamic>, ActivityEntry.fromJson);
  }
}
