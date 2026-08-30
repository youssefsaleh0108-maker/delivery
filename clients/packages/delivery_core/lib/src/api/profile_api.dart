import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../util/image_prep.dart';

/// Client for the signed-in account's own profile — today just the avatar.
///
/// Every endpoint is `/me`: the server resolves the owner from the token, so there is no id
/// anywhere a caller could tamper with.
class ProfileApi {
  ProfileApi(this._dio);

  final Dio _dio;

  /// The viewing URL for the account's picture, or null when there is none.
  ///
  /// The URL is presigned and short-lived — the avatars bucket is private — so it is fetched
  /// when the screen opens rather than stored.
  /// Username search for the split-payment friend picker: [{username, name}], capped small
  /// server-side. Under two characters the server answers nothing on principle.
  Future<List<Map<String, String>>> search(String query) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/profile/search',
      queryParameters: <String, dynamic>{'q': query},
    );
    return (response.data as List<dynamic>)
        .map((dynamic e) => (e as Map<String, dynamic>)
            .map((String k, dynamic v) => MapEntry<String, String>(k, '$v')))
        .toList();
  }

  Future<String?> myAvatarUrl() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/profile/me');
    return (response.data as Map<String, dynamic>)['avatarUrl'] as String?;
  }

  /// Uploads the account's picture: presign, PUT to storage, confirm. Returns the fresh URL.
  ///
  /// The bytes go through [ImagePrep] first with a deliberately small cap — a selfie off a
  /// phone camera is several megabytes for a picture drawn 64px wide.
  Future<String?> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final PreparedImage prepared =
        ImagePrep.forUpload(bytes, contentType, maxBytes: 512 * 1024);
    final Uint8List sending = prepared.bytes;

    final Response<dynamic> presign = await _dio.post<dynamic>(
      '/api/profile/me/avatar/presign',
      data: <String, dynamic>{'contentType': prepared.contentType},
    );
    final Map<String, dynamic> upload = presign.data as Map<String, dynamic>;
    final String uploadUrl = upload['uploadUrl'] as String;
    final String fileId = upload['fileId'] as String;

    // A separate, bare Dio: S3-compatible storage rejects a presigned request that also carries
    // an Authorization header — two conflicting auth mechanisms on one request.
    final Dio bare = Dio();
    await bare.put<void>(
      uploadUrl,
      data: Stream<List<int>>.fromIterable(<List<int>>[sending]),
      options: Options(headers: <String, dynamic>{
        'Content-Type': prepared.contentType,
        Headers.contentLengthHeader: sending.length,
      }),
    );

    final Response<dynamic> confirmed = await _dio.post<dynamic>(
      '/api/profile/me/avatar/confirm',
      data: <String, dynamic>{'fileId': fileId},
    );
    return (confirmed.data as Map<String, dynamic>)['avatarUrl'] as String?;
  }

  Future<void> removeAvatar() => _dio.delete<void>('/api/profile/me/avatar');
}
