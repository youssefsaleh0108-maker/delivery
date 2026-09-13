/// Neighbourhood rooms and their moderation, mirroring App Notification's
/// `NeighbourhoodChatController`, `RoomMessageView` and `ChatModerationController`.
library;

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// The caller's neighbourhood room: one per delivery area, placed by the server from the area of the
/// caller's delivery address. The app never picks a room; it says which area its address is in.
class NeighbourhoodRoom {
  const NeighbourhoodRoom({
    required this.id,
    required this.zoneId,
    required this.name,
    required this.memberCount,
    required this.lastSequence,
    required this.yourHandle,
    this.yourName,
    this.mutedUntil,
    this.moveBlockedUntil,
    this.posting = RoomPosting.open,
  });

  final String id;
  final String zoneId;

  /// The delivery area's name as the platform names it — the room is the area.
  final String name;

  /// Neighbours in the room: people in it now who may speak there, because an order of theirs was
  /// delivered in the area recently. Membership, not presence — nothing on the platform knows how
  /// many are "active" — and not everybody reading, so the header counts neighbours, not visitors.
  final int memberCount;

  /// The newest message's number, 0 for an empty room.
  final int lastSequence;

  /// The caller's own per-room handle; a neighbour's messages carry theirs.
  final String yourHandle;

  final String? yourName;

  /// Present only while a moderator's mute is in force.
  final DateTime? mutedUntil;

  /// Present only when the caller's address is in another area they cannot move to yet.
  final DateTime? moveBlockedUntil;

  /// Whether the caller may speak here. Reading needs nothing; see [RoomPosting].
  final RoomPosting posting;

  bool isMutedAt(DateTime now) => mutedUntil != null && now.isBefore(mutedUntil!);

  NeighbourhoodRoom withMutedUntil(DateTime? until) => _copy(mutedUntil: until, posting: posting);

  NeighbourhoodRoom withPosting(RoomPosting value) => _copy(mutedUntil: mutedUntil, posting: value);

  NeighbourhoodRoom _copy({required DateTime? mutedUntil, required RoomPosting posting}) =>
      NeighbourhoodRoom(
        id: id,
        zoneId: zoneId,
        name: name,
        memberCount: memberCount,
        lastSequence: lastSequence,
        yourHandle: yourHandle,
        yourName: yourName,
        mutedUntil: mutedUntil,
        moveBlockedUntil: moveBlockedUntil,
        posting: posting,
      );

  factory NeighbourhoodRoom.fromJson(Map<String, dynamic> json) => NeighbourhoodRoom(
        id: json['id'] as String,
        zoneId: json['zoneId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
        lastSequence: (json['lastSequence'] as num?)?.toInt() ?? 0,
        yourHandle: json['yourHandle'] as String? ?? '',
        yourName: json['yourName'] as String?,
        mutedUntil: _date(json['mutedUntil']),
        moveBlockedUntil: _date(json['moveBlockedUntil']),
        posting: RoomPosting.fromWire(json['posting'] as String?),
      );
}

/// Whether the caller may speak in the room they are reading, as the server decided it.
///
/// Any customer may read the room of the area they choose. Speaking needs an order of theirs
/// delivered in that area recently — the platform's own evidence that they live there, where the
/// area on an address is only their say-so.
enum RoomPosting {
  /// A recent delivery in the area: the composer is theirs.
  open('OPEN'),

  /// No such delivery: they read, and may post after their first delivery to the area.
  needsDelivery('NEEDS_DELIVERY'),

  /// The platform could not check just now. Posting waits rather than guessing either way.
  unverified('UNVERIFIED');

  const RoomPosting(this.wire);

  final String wire;

  /// Anything unrecognised reads as [open]. The server refuses what it refuses regardless, and a
  /// refusal turns the composer read-only with the reason ([RoomPostingLockedException]).
  static RoomPosting fromWire(String? value) => RoomPosting.values
      .firstWhere((RoomPosting p) => p.wire == value, orElse: () => RoomPosting.open);
}

enum RoomMessageKind {
  text('TEXT'),

  /// Removed by a moderator: the row keeps its place, and has no words and no author name.
  hidden('HIDDEN');

  const RoomMessageKind(this.wire);

  final String wire;

  static RoomMessageKind fromWire(String? value) =>
      value == hidden.wire ? RoomMessageKind.hidden : RoomMessageKind.text;
}

/// One message in a room, in a history page and in a live frame alike.
///
/// No account id anywhere: an author is a per-room [authorHandle] and a first name with a last
/// initial. Enough to tell two neighbours apart, and to report or block one of them.
class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.sequence,
    required this.authorHandle,
    required this.mine,
    required this.kind,
    this.authorName,
    this.text,
    this.sentAt,
  });

  final String id;
  final String roomId;
  final int sequence;
  final String authorHandle;

  /// Null when the author's account carries no usable name, and on a removed message.
  final String? authorName;

  /// Computed per viewer by the server.
  final bool mine;

  final RoomMessageKind kind;

  /// Null on a removed message.
  final String? text;

  final DateTime? sentAt;

  bool get isHidden => kind == RoomMessageKind.hidden;

  factory RoomMessage.fromJson(Map<String, dynamic> json) => RoomMessage(
        id: json['id'] as String,
        roomId: json['roomId'] as String? ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        authorHandle: json['authorHandle'] as String? ?? '',
        authorName: json['authorName'] as String?,
        mine: json['mine'] as bool? ?? false,
        kind: RoomMessageKind.fromWire(json['kind'] as String?),
        text: json['text'] as String?,
        sentAt: _date(json['sentAt']),
      );
}

/// A page of history, oldest first, and whether more exist in the direction asked.
class RoomHistoryPage {
  const RoomHistoryPage({required this.messages, required this.more});

  final List<RoomMessage> messages;
  final bool more;

  factory RoomHistoryPage.fromJson(Map<String, dynamic> json) => RoomHistoryPage(
        messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => RoomMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        more: json['more'] as bool? ?? false,
      );
}

/// Why a neighbour flags a message. The four the server accepts.
enum RoomReportReason {
  spam('SPAM'),
  abuse('ABUSE'),
  personalInfo('PERSONAL_INFO'),
  other('OTHER');

  const RoomReportReason(this.wire);

  final String wire;

  static RoomReportReason fromWire(String? value) => RoomReportReason.values
      .firstWhere((RoomReportReason r) => r.wire == value, orElse: () => RoomReportReason.other);
}

/// Somebody the caller blocked: an opaque block id and the name they went by — never who they are.
class BlockedNeighbour {
  const BlockedNeighbour({required this.id, this.name, this.blockedAt});

  final String id;
  final String? name;
  final DateTime? blockedAt;

  factory BlockedNeighbour.fromJson(Map<String, dynamic> json) => BlockedNeighbour(
        id: json['id'] as String,
        name: json['name'] as String?,
        blockedAt: _date(json['blockedAt']),
      );
}

enum NoNeighbourhoodReason {
  /// The delivery address names no area.
  noZone,

  /// The area it names is not one the platform offers, or it was retired.
  unknownZone,
}

/// The caller has no room to be placed in, and why — so the screen can ask for an area instead of
/// showing an error.
class NoNeighbourhoodException implements Exception {
  const NoNeighbourhoodException(this.reason);

  final NoNeighbourhoodReason reason;

  @override
  String toString() => 'NoNeighbourhoodException($reason)';
}

/// A post refused because a moderator muted the caller in this room.
class RoomMutedException implements Exception {
  const RoomMutedException(this.mutedUntil);

  final DateTime? mutedUntil;

  @override
  String toString() => 'RoomMutedException(until $mutedUntil)';
}

/// A post refused because no order of the caller's has been delivered in the room's area recently
/// enough. The room stays readable; the composer says what would open it.
class RoomPostingLockedException implements Exception {
  const RoomPostingLockedException();

  @override
  String toString() => 'RoomPostingLockedException()';
}

/// A post refused for sending too fast; shop threads use it too.
class ChatRateLimitedException implements Exception {
  const ChatRateLimitedException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'ChatRateLimitedException(retry after $retryAfter)';
}

/// One line of the Backoffice moderation queue.
class ReportedRoomMessage {
  const ReportedRoomMessage({
    required this.messageId,
    required this.roomId,
    required this.authorHandle,
    required this.text,
    required this.hidden,
    required this.reportCount,
    required this.reasons,
    this.roomName,
    this.authorName,
    this.sentAt,
    this.firstReportedAt,
    this.lastReportedAt,
    this.authorMutedUntil,
  });

  final String messageId;
  final String roomId;
  final String? roomName;
  final String authorHandle;
  final String? authorName;

  /// The words, even when already removed — a moderator deciding on a mute has to read them.
  final String text;

  final DateTime? sentAt;
  final bool hidden;
  final int reportCount;
  final List<RoomReportReason> reasons;
  final DateTime? firstReportedAt;
  final DateTime? lastReportedAt;

  /// Present only while the author is muted — wherever they are now, since a mute follows the person.
  final DateTime? authorMutedUntil;

  factory ReportedRoomMessage.fromJson(Map<String, dynamic> json) => ReportedRoomMessage(
        messageId: json['messageId'] as String,
        roomId: json['roomId'] as String? ?? '',
        roomName: json['roomName'] as String?,
        authorHandle: json['authorHandle'] as String? ?? '',
        authorName: json['authorName'] as String?,
        text: json['text'] as String? ?? '',
        sentAt: _date(json['sentAt']),
        hidden: json['hidden'] as bool? ?? false,
        reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
        reasons: (json['reasons'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => RoomReportReason.fromWire(e as String?))
            .toList(),
        firstReportedAt: _date(json['firstReportedAt']),
        lastReportedAt: _date(json['lastReportedAt']),
        authorMutedUntil: _date(json['authorMutedUntil']),
      );
}
