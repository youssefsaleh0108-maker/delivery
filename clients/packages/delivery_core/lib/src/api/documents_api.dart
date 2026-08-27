import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/onboarding_models.dart';

/// Client for the onboarding documents and payout-details endpoints.
///
/// Two audiences, mirroring the server. The applicant half is all `mine` — the application is
/// resolved from the token, so there is no id anywhere an applicant could tamper with. The
/// reviewer half takes ids, because a reviewer legitimately reads other people's applications, and
/// the server gates those by role and, for a carrier, by whose company it is.
class DocumentsApi {
  DocumentsApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- applicant: documents

  /// Step 1: a one-shot URL to PUT one document straight to storage.
  Future<DocumentUploadTicket> presign(ApplicantDocumentKind kind, String contentType) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/mine/documents/presign',
      data: <String, dynamic>{'kind': kind.wire, 'contentType': contentType},
    );
    return DocumentUploadTicket.fromJson(response.data as Map<String, dynamic>);
  }

  /// Step 3: the bytes landed. (Step 2 is the client's own PUT, which never touches the backend.)
  ///
  /// Confirming a kind that already has a live document replaces it — the old one is superseded,
  /// not deleted, so a verdict already reached stays on the record. That is also why there is no
  /// separate "replace" call: replacing is uploading again.
  Future<ApplicantDocument> confirm(String fileId, ApplicantDocumentKind kind) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/mine/documents/$fileId/confirm',
      data: <String, dynamic>{'kind': kind.wire},
    );
    return ApplicantDocument.fromJson(response.data as Map<String, dynamic>);
  }

  /// All three steps in one call, mirroring how `StoreApi.uploadImage` does it: presign, PUT the
  /// bytes to storage with a bare Dio, confirm. Uploading a kind that already exists replaces it.
  ///
  /// Throws [ArgumentError] before any network traffic when the file is over the server's limit.
  Future<ApplicantDocument> upload({
    required ApplicantDocumentKind kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final DocumentUploadTicket ticket = await presign(kind, contentType);
    if (ticket.maxSizeBytes > 0 && bytes.length > ticket.maxSizeBytes) {
      throw ArgumentError(
          'Document is ${bytes.length} bytes; the limit is ${ticket.maxSizeBytes}');
    }

    // A separate, bare Dio: S3-compatible storage rejects a presigned request that also carries an
    // Authorization header, because that is two conflicting auth mechanisms on one request.
    final Dio bare = Dio();
    await bare.put<void>(
      ticket.uploadUrl,
      data: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
      options: Options(headers: <String, dynamic>{
        'Content-Type': ticket.contentType,
        Headers.contentLengthHeader: bytes.length,
      }),
    );

    return confirm(ticket.fileId, kind);
  }

  /// The applicant's own documents and how each one fared. Reviewer notes are never in this shape.
  Future<List<ApplicantDocument>> myDocuments() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/applications/mine/documents');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ApplicantDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- applicant: payout

  /// The bank step: account holder and IBAN, as typed — spaces and all. The server normalises and
  /// mod-97 checks it. PUT semantics: submitting twice corrects the first attempt.
  Future<PayoutDetails> setMyPayout({
    required String accountHolder,
    required String iban,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/onboarding/applications/mine/payout',
      data: <String, dynamic>{'accountHolder': accountHolder, 'iban': iban},
    );
    return PayoutDetails.fromJson(response.data as Map<String, dynamic>);
  }

  /// The applicant reading back their own details — in full, unmasked: it is their own number and
  /// they are being asked to confirm it is correct. Null when the step has not been done yet.
  ///
  /// Everyone who is not the applicant or a deciding reviewer only ever sees [PayoutSummary],
  /// which arrives on the application view, not through this call.
  Future<PayoutDetails?> myPayout() async {
    try {
      final Response<dynamic> response =
          await _dio.get<dynamic>('/api/onboarding/applications/mine/payout');
      return PayoutDetails.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------- reviewers: backoffice

  /// One application's documents, with view URLs. BACKOFFICE only.
  Future<List<ReviewedDocument>> applicationDocuments(String applicationId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/onboarding/applications/$applicationId/documents');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ReviewedDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Accepts one document. [note] is reviewer-to-reviewer and never shown to the applicant.
  Future<ReviewedDocument> approveDocument(String applicationId, String documentId,
      {String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/$applicationId/documents/$documentId/approve',
      data: <String, dynamic>{if (note != null) 'note': note},
    );
    return ReviewedDocument.fromJson(response.data as Map<String, dynamic>);
  }

  /// Refuses one document. [reason] is shown to the applicant and the server refuses it blank — a
  /// refusal nobody can see the reason for produces the same photograph uploaded again unchanged.
  Future<ReviewedDocument> rejectDocument(String applicationId, String documentId,
      {required String reason, String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/$applicationId/documents/$documentId/reject',
      data: <String, dynamic>{'reason': reason, if (note != null) 'note': note},
    );
    return ReviewedDocument.fromJson(response.data as Map<String, dynamic>);
  }

  /// One application's payout details, unmasked, for the reviewer deciding it. Null when the
  /// applicant has not done the bank step.
  Future<PayoutDetails?> applicationPayout(String applicationId) =>
      _payoutOrNull('/api/onboarding/applications/$applicationId/payout');

  // ---------------------------------------------------------------- reviewers: carrier console

  /// A company reviewing its own rider applicant's documents. The company id travels in the path
  /// and the server checks it against who actually runs what.
  Future<List<ReviewedDocument>> companyApplicantDocuments(
      String providerId, String applicationId) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/onboarding/applications/for-company/$providerId/$applicationId/documents');
    return (response.data as List<dynamic>)
        .map((dynamic e) => ReviewedDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ReviewedDocument> approveCompanyApplicantDocument(
      String providerId, String applicationId, String documentId,
      {String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/for-company/$providerId/$applicationId'
      '/documents/$documentId/approve',
      data: <String, dynamic>{if (note != null) 'note': note},
    );
    return ReviewedDocument.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ReviewedDocument> rejectCompanyApplicantDocument(
      String providerId, String applicationId, String documentId,
      {required String reason, String? note}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/onboarding/applications/for-company/$providerId/$applicationId'
      '/documents/$documentId/reject',
      data: <String, dynamic>{'reason': reason, if (note != null) 'note': note},
    );
    return ReviewedDocument.fromJson(response.data as Map<String, dynamic>);
  }

  /// A company reading its own rider applicant's payout details. Null when not yet supplied.
  Future<PayoutDetails?> companyApplicantPayout(String providerId, String applicationId) =>
      _payoutOrNull(
          '/api/onboarding/applications/for-company/$providerId/$applicationId/payout');

  // ---------------------------------------------------------------- internals

  Future<PayoutDetails?> _payoutOrNull(String path) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(path);
      return PayoutDetails.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}
