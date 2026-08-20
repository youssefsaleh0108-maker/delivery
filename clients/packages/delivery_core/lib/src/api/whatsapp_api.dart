import 'package:dio/dio.dart';

import '../models/store_models.dart';
import '../models/whatsapp_models.dart';

/// The merchant's WhatsApp front door.
///
/// Three things in one API because they are three steps of one job: read what the customer said,
/// build a draft from it, and confirm it into an order.
class WhatsAppApi {
  WhatsAppApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- the inbox

  /// This merchant's conversations, the ones waiting longest at the top.
  Future<List<WhatsAppConversation>> inbox({bool archived = false}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/whatsapp/conversations',
      queryParameters: <String, dynamic>{'archived': archived},
    );
    return (response.data as List<dynamic>)
        .map((dynamic j) => WhatsAppConversation.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// The thread, oldest first, which is how a conversation reads.
  Future<List<WhatsAppMessage>> thread(String conversationId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/whatsapp/conversations/$conversationId/messages');
    return (response.data as List<dynamic>)
        .map((dynamic j) => WhatsAppMessage.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<WhatsAppConversation> markRead(String conversationId) =>
      _conversation('/api/whatsapp/conversations/$conversationId/read');

  Future<WhatsAppConversation> archive(String conversationId) =>
      _conversation('/api/whatsapp/conversations/$conversationId/archive');

  /// Sends a reply. The result says whether it actually went out.
  Future<ReplyResult> reply(String conversationId, String body) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/whatsapp/conversations/$conversationId/reply',
      data: <String, dynamic>{'body': body},
    );
    return ReplyResult.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- connected numbers

  Future<List<ConnectedNumber>> numbers() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/whatsapp/numbers');
    return (response.data as List<dynamic>)
        .map((dynamic j) => ConnectedNumber.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ConnectedNumber> connectNumber({
    required String phoneNumberId,
    String? label,
    String? displayNumber,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/whatsapp/numbers',
      data: <String, dynamic>{
        'phoneNumberId': phoneNumberId,
        'label': label,
        'displayNumber': displayNumber,
      },
    );
    return ConnectedNumber.fromJson(response.data as Map<String, dynamic>);
  }

  /// Stops routing new messages here. Conversations survive.
  Future<void> disconnectNumber(String phoneNumberId) =>
      _dio.delete<dynamic>('/api/whatsapp/numbers/$phoneNumberId');

  // ---------------------------------------------------------------- drafts

  /// Everything still waiting to become an order.
  Future<List<DraftOrder>> openDrafts() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/whatsapp/drafts');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DraftOrder.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Every draft a conversation has produced, newest first — including the ones already placed.
  Future<List<DraftOrder>> draftsFor(String conversationId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/whatsapp/drafts/conversations/$conversationId');
    return (response.data as List<dynamic>)
        .map((dynamic j) => DraftOrder.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Opens a draft, or hands back the one already open for this conversation.
  Future<DraftOrder> openDraft(String conversationId, {String? requestText}) =>
      _draft('POST', '/api/whatsapp/drafts/conversations/$conversationId',
          <String, dynamic>{'requestText': requestText});

  Future<DraftOrder> addLine(
    String draftId, {
    required String productId,
    int qty = 1,
    List<String> optionIds = const <String>[],
  }) =>
      _draft('POST', '/api/whatsapp/drafts/$draftId/lines', <String, dynamic>{
        'productId': productId,
        'qty': qty,
        'optionIds': optionIds,
      });

  /// By line id, not product: with options the same product can be in the basket twice.
  Future<DraftOrder> removeLine(String draftId, String lineId) =>
      _draft('DELETE', '/api/whatsapp/drafts/$draftId/lines/$lineId', null);

  Future<DraftOrder> setDelivery(
    String draftId, {
    required String deliveryAddress,
    String? deliveryZoneId,
    String? contactPhone,
    String? notes,
  }) =>
      _draft('PUT', '/api/whatsapp/drafts/$draftId/delivery', <String, dynamic>{
        'deliveryAddress': deliveryAddress,
        'deliveryZoneId': deliveryZoneId,
        'contactPhone': contactPhone,
        'notes': notes,
      });

  /// The confirmation. The one step that costs money.
  Future<DraftOrder> place(String draftId) =>
      _draft('POST', '/api/whatsapp/drafts/$draftId/place', null);

  Future<DraftOrder> discard(String draftId) =>
      _draft('POST', '/api/whatsapp/drafts/$draftId/discard', null);

  /// What the merchant picks from when a product has options.
  ///
  /// The same [OptionGroup] the customer app renders — one shape, so the merchant taking an order
  /// by hand sees exactly the questions the customer would have been asked.
  Future<List<OptionGroup>> optionsFor(String productId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/whatsapp/drafts/products/$productId/options');
    return (response.data as List<dynamic>)
        .map((dynamic j) => OptionGroup.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<WhatsAppConversation> _conversation(String path) async {
    final Response<dynamic> response = await _dio.post<dynamic>(path);
    return WhatsAppConversation.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DraftOrder> _draft(String method, String path, Map<String, dynamic>? data) async {
    final Response<dynamic> response = await _dio.request<dynamic>(
      path,
      data: data,
      options: Options(method: method),
    );
    return DraftOrder.fromJson(response.data as Map<String, dynamic>);
  }
}
