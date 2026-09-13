import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show ChatSendButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'delivery_address.dart';

/// A neighbourhood's public chat room (Figma 121:102).
///
/// **Which room.** The one for the delivery area of the customer's selected address. The screen sends
/// that area and nothing else; the server places the customer, keeps them in one room at a time, and
/// checks the membership on every read, post and live subscription. A customer whose address has no
/// area is asked to choose one rather than shown an error.
///
/// **What is drawn from the frame, and what is not.** The header (title from the area's name, the
/// LIVE pill bound to the socket actually being connected, and a real count of neighbours in the room
/// in place of the frame's invented "1.2k active"), the multi-author bubbles and the composer are
/// the frame's. Three things are deliberately left out: the "YouDrop Butler AI" recommendation card
/// (no recommender exists, and inventing its answers would be the opposite of the platform's
/// evidence-only rule), and the composer's camera and location buttons (photos have no upload or
/// moderation path yet, and broadcasting a precise location to a whole neighbourhood is a risk no
/// one has signed off). None of the three is drawn as a control that cannot work.
///
/// **Safety, which the frame does not draw and a room of strangers needs.** Long-press a neighbour's
/// message to report it or block its author; the Community tag opens the rules and the people you
/// blocked. A removed message stays in place as "This message was removed", and a muted neighbour
/// sees until when instead of a composer. All of it is enforced by the server — this screen only
/// makes it visible.
class NeighbourhoodChatScreen extends StatefulWidget {
  const NeighbourhoodChatScreen({
    super.key,
    required this.api,
    required this.addresses,
    this.socket,
    this.onChooseArea,
  });

  final NeighbourhoodChatApi api;

  /// The shell's address book; the selected address's area is the room.
  final DeliveryAddressStore addresses;

  /// Null loses only liveness: messages still load and send, and neighbours' replies appear on the
  /// next open rather than as they are written.
  final UserQueueSocket? socket;

  /// Opens the address sheet for a customer whose address names no area. Null leaves the
  /// explanation without a button rather than drawing one that goes nowhere.
  final Future<void> Function(BuildContext context)? onChooseArea;

  @override
  State<NeighbourhoodChatScreen> createState() => _NeighbourhoodChatScreenState();
}

enum _MessageAction { copy, report, block }

class _NeighbourhoodChatScreenState extends State<NeighbourhoodChatScreen> {
  /// The server refuses longer messages outright; saying so before sending saves a round trip.
  static const int _maxCodePoints = 1000;

  /// A bound on catching up after a reconnect, against a server that keeps saying there is more.
  static const int _maxCatchUpPages = 20;

  final TextEditingController _composer = TextEditingController();
  final Random _random = Random();

  NeighbourhoodRoom? _room;
  NoNeighbourhoodReason? _noRoom;
  bool _loading = true;
  bool _loadFailed = false;

  /// Oldest first; the list renders it reversed so the newest sits at the bottom.
  List<RoomMessage> _messages = <RoomMessage>[];
  bool _olderAvailable = false;
  bool _loadingOlder = false;
  bool _sending = false;

  /// The idempotency key of a send that got no answer, reused only for the same words.
  String? _pendingText;
  String? _pendingClientId;

  StreamSubscription<RoomMessage>? _live;
  bool _wasConnected = false;

  int get _cursor => _messages.isEmpty ? 0 : _messages.last.sequence;

  @override
  void initState() {
    super.initState();
    unawaited(_enter());
    final UserQueueSocket? socket = widget.socket;
    if (socket != null) {
      _wasConnected = socket.connected.value;
      socket.connected.addListener(_onConnectivity);
    }
  }

  @override
  void dispose() {
    widget.socket?.connected.removeListener(_onConnectivity);
    _live?.cancel();
    _composer.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------------------------ loading

  /// Asks for the caller's room from their address's area, then its newest page, then listens.
  Future<void> _enter() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _noRoom = null;
    });
    await _live?.cancel();
    _live = null;
    try {
      final NeighbourhoodRoom room =
          await widget.api.myRoom(zoneId: widget.addresses.selected?.zoneId);
      final RoomHistoryPage page = await widget.api.messages(room.id);
      if (!mounted) return;
      setState(() {
        _room = room;
        _messages = page.messages;
        _olderAvailable = page.more;
        _loading = false;
      });
      _listen(room);
    } on NoNeighbourhoodException catch (e) {
      if (!mounted) return;
      setState(() {
        _room = null;
        _noRoom = e.reason;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _listen(NeighbourhoodRoom room) {
    final UserQueueSocket? socket = widget.socket;
    if (socket == null) return;
    _live = NeighbourhoodChatApi.live(socket, room.id).listen((RoomMessage message) {
      if (message.roomId != room.id) return;
      _fold(<RoomMessage>[message]);
    });
  }

  /// On every false→true edge, fetch what arrived while the socket was down.
  void _onConnectivity() {
    final bool connected = widget.socket?.connected.value ?? false;
    if (connected && !_wasConnected && _room != null) {
      unawaited(_catchUp());
    }
    _wasConnected = connected;
  }

  Future<void> _catchUp() async {
    final NeighbourhoodRoom? room = _room;
    if (room == null) return;
    try {
      int cursor = _cursor;
      for (int page = 0; page < _maxCatchUpPages; page++) {
        final RoomHistoryPage result = await widget.api.messages(room.id, afterSequence: cursor);
        if (!mounted) return;
        _fold(result.messages);
        if (!result.more || result.messages.isEmpty) break;
        cursor = result.messages.last.sequence;
      }
    } catch (_) {
      // The next reconnect or reopen catches up; nothing is lost, the rows are on the server.
    }
  }

  Future<void> _loadOlder() async {
    final NeighbourhoodRoom? room = _room;
    if (room == null || _messages.isEmpty || _loadingOlder || !_olderAvailable) return;
    setState(() => _loadingOlder = true);
    try {
      final RoomHistoryPage page =
          await widget.api.messages(room.id, beforeSequence: _messages.first.sequence);
      if (!mounted) return;
      _fold(page.messages);
      setState(() => _olderAvailable = page.more);
    } catch (_) {
      // Scrolling back up retries.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Merges rows by id, so a moderator's removal replaces the message it removes and a frame and a
  /// refetch of the same message render once.
  void _fold(List<RoomMessage> incoming) {
    if (!mounted || incoming.isEmpty) return;
    setState(() {
      final Map<String, RoomMessage> byId = <String, RoomMessage>{
        for (final RoomMessage m in _messages) m.id: m,
        for (final RoomMessage m in incoming) m.id: m,
      };
      _messages = byId.values.toList()
        ..sort((RoomMessage a, RoomMessage b) => a.sequence.compareTo(b.sequence));
    });
  }

  // ------------------------------------------------------------------------------------ sending

  Future<void> _send() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final NeighbourhoodRoom? room = _room;
    final String text = _composer.text.trim();
    if (room == null || text.isEmpty || _sending || room.isMutedAt(DateTime.now())) return;
    if (text.runes.length > _maxCodePoints) {
      _say(t.chatTooLong);
      return;
    }
    if (_pendingText != text) {
      _pendingText = text;
      _pendingClientId = '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}';
    }

    setState(() => _sending = true);
    try {
      final RoomMessage sent =
          await widget.api.send(room.id, text, clientMessageId: _pendingClientId);
      if (!mounted) return;
      _pendingText = null;
      _pendingClientId = null;
      _composer.clear();
      _fold(<RoomMessage>[sent]);
    } on RoomMutedException catch (e) {
      if (!mounted) return;
      final DateTime? until = e.mutedUntil;
      if (until != null) {
        setState(() => _room = room.withMutedUntil(until));
      } else {
        _say(t.chatActionFailed);
      }
    } on ChatRateLimitedException {
      if (!mounted) return;
      _say(t.chatSlowDown);
    } catch (_) {
      if (!mounted) return;
      _say(t.chatCouldNotSend);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ------------------------------------------------------------------------ report, block, copy

  Future<void> _actionsFor(RoomMessage message) async {
    if (message.isHidden) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final _MessageAction? action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(t.chatRoomCopy),
              onTap: () => Navigator.of(sheet).pop(_MessageAction.copy),
            ),
            // Nobody reports or blocks themselves; the server refuses both, so neither is offered.
            if (!message.mine) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(t.chatRoomReport),
                onTap: () => Navigator.of(sheet).pop(_MessageAction.report),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text(t.chatRoomBlock),
                onTap: () => Navigator.of(sheet).pop(_MessageAction.block),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text ?? ''));
        if (mounted) _say(t.chatRoomCopied);
      case _MessageAction.report:
        await _report(message);
      case _MessageAction.block:
        await _block(message);
    }
  }

  Future<void> _report(RoomMessage message) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final RoomReportReason? reason = await showModalBottomSheet<RoomReportReason>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.sm),
              child: Text(
                t.chatRoomReportTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
              ),
            ),
            for (final RoomReportReason option in RoomReportReason.values)
              ListTile(
                title: Text(_reasonLabel(t, option)),
                onTap: () => Navigator.of(sheet).pop(option),
              ),
          ],
        ),
      ),
    );
    if (!mounted || reason == null) return;
    try {
      await widget.api.report(message.id, reason);
      if (mounted) _say(t.chatRoomReportSent);
    } catch (_) {
      if (mounted) _say(t.chatActionFailed);
    }
  }

  Future<void> _block(RoomMessage message) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String name = message.authorName ?? t.chatRoomNeighbour;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text(t.chatRoomBlockTitle(name)),
        content: Text(t.chatRoomBlockBody),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(t.chatRoomBlock)),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await widget.api.blockAuthor(message.id);
      if (!mounted) return;
      // The server already leaves them out of every later page and frame; this clears what is on
      // screen now, by the per-room handle every message of theirs here carries.
      setState(() => _messages =
          _messages.where((RoomMessage m) => m.authorHandle != message.authorHandle).toList());
      _say(t.chatRoomBlockedToast);
    } catch (_) {
      if (mounted) _say(t.chatActionFailed);
    }
  }

  Future<void> _openCommunity() async {
    bool unblocked = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) =>
          _CommunitySheet(api: widget.api, onUnblocked: () => unblocked = true),
    );
    // Somebody unblocked is somebody whose messages should be back in the room — however the sheet
    // was dismissed, which is why this is a flag and not the sheet's pop result.
    if (unblocked && mounted) unawaited(_enter());
  }

  Future<void> _chooseArea() async {
    final Future<void> Function(BuildContext context)? choose = widget.onChooseArea;
    if (choose == null) return;
    await choose(context);
    if (mounted) unawaited(_enter());
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _reasonLabel(DeliveryStrings t, RoomReportReason reason) => switch (reason) {
        RoomReportReason.spam => t.chatRoomReasonSpam,
        RoomReportReason.abuse => t.chatRoomReasonAbuse,
        RoomReportReason.personalInfo => t.chatRoomReasonPersonalInfo,
        RoomReportReason.other => t.chatRoomReasonOther,
      };

  String _moment(DateTime at) {
    final MaterialLocalizations words = MaterialLocalizations.of(context);
    final String time = words.formatTimeOfDay(TimeOfDay.fromDateTime(at),
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
    return '${words.formatMediumDate(at)} $time';
  }

  // -------------------------------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(t),
            if (_room != null) _reconnectingStrip(t),
            Expanded(child: _body(t)),
            if (_room != null && !_loading) _footer(t),
          ],
        ),
      ),
    );
  }

  /// Back, "{area} chat" with the LIVE pill, the neighbour count, and the Community tag.
  Widget _header(DeliveryStrings t) {
    final NeighbourhoodRoom? room = _room;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, DeliverySpacing.sm + 4, DeliverySpacing.md, DeliverySpacing.sm + 4),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          YdBackButton(onPressed: () => Navigator.of(context).maybePop(), semanticLabel: t.back),
          const SizedBox(width: DeliverySpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        room == null ? t.chatRoomEntryTitle : t.chatRoomTitle(room.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                      ),
                    ),
                    if (room != null) _livePill(t),
                  ],
                ),
                if (room != null)
                  Text(
                    t.chatRoomMembers(room.memberCount),
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                  ),
              ],
            ),
          ),
          if (room != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => unawaited(_openCommunity()),
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  ),
                  child: Text(
                    t.chatRoomCommunity,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryColors.brand),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// LIVE only while the socket is actually connected — never as decoration.
  Widget _livePill(DeliveryStrings t) {
    final UserQueueSocket? socket = widget.socket;
    if (socket == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: socket.connected,
      builder: (BuildContext context, bool connected, _) {
        if (!connected) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: DeliverySpacing.sm),
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: DeliveryAccent.positive.tint,
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: DeliveryAccent.positive.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  t.chatRoomLive,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: DeliveryAccent.positive.color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reconnectingStrip(DeliveryStrings t) {
    final UserQueueSocket? socket = widget.socket;
    if (socket == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: socket.connected,
      builder: (BuildContext context, bool connected, _) {
        if (connected) return const SizedBox.shrink();
        return _strip(t.riderChatReconnecting, DeliveryAccent.caution);
      },
    );
  }

  Widget _strip(String text, DeliveryAccent accent) {
    return Container(
      width: double.infinity,
      color: accent.tint,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.xs + 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent.color, height: 1.3),
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    final NoNeighbourhoodReason? noRoom = _noRoom;
    if (noRoom != null) {
      final bool noArea = noRoom == NoNeighbourhoodReason.noZone;
      return Center(
        child: YdEmptyState(
          icon: Icons.location_on_outlined,
          title: noArea ? t.chatRoomPickAreaTitle : t.chatRoomUnknownAreaTitle,
          message: noArea ? t.chatRoomPickAreaBody : t.chatRoomUnknownAreaBody,
          action: widget.onChooseArea == null
              ? null
              : YdPillButton(
                  label: t.chatRoomChooseArea,
                  onPressed: () => unawaited(_chooseArea()),
                  size: YdPillButtonSize.compact,
                  expand: false,
                ),
        ),
      );
    }
    if (_loadFailed || _room == null) {
      return Center(
        child: YdEmptyState(
          icon: Icons.forum_outlined,
          title: t.chatRoomCouldNotLoad,
          action: YdPillButton(
            label: t.tryAgain,
            onPressed: () => unawaited(_enter()),
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ),
      );
    }

    final NeighbourhoodRoom room = _room!;
    final DateTime? moveBlockedUntil = room.moveBlockedUntil;
    return Column(
      children: <Widget>[
        if (moveBlockedUntil != null)
          _strip(t.chatRoomMoveBlocked(_moment(moveBlockedUntil)), DeliveryAccent.neutral),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Text(
                      t.chatRoomEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
                    ),
                  ),
                )
              : ListView.builder(
                  // Reversed so the room opens at the newest message; the extra row at the far end
                  // is where older history loads, fetched as soon as it is built.
                  reverse: true,
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  itemCount: _messages.length + (_olderAvailable ? 1 : 0),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == _messages.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadOlder()));
                      return const Padding(
                        padding: EdgeInsets.all(DeliverySpacing.sm),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                          ),
                        ),
                      );
                    }
                    return _row(t, _messages[_messages.length - 1 - index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _row(DeliveryStrings t, RoomMessage message) {
    final DateTime? sentAt = message.sentAt;
    final String? time = sentAt == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(sentAt),
            alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
    final double maxBubble = min(280, MediaQuery.sizeOf(context).width * 0.72);

    final Widget words = message.isHidden
        ? Text(
            t.chatRoomHidden,
            style: const TextStyle(
                fontSize: 13, fontStyle: FontStyle.italic, color: DeliveryColors.faint, height: 1.4),
          )
        : Text(
            message.text ?? '',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: message.mine ? DeliveryColors.white : DeliveryColors.ink,
            ),
          );

    if (message.mine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: DeliverySpacing.sm + 4),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: GestureDetector(
            onLongPress: () => unawaited(_actionsFor(message)),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxBubble),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: message.isHidden ? DeliveryColors.white : DeliveryColors.brand,
                border: message.isHidden ? Border.all(color: DeliveryColors.border) : null,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(12),
                  topEnd: Radius.circular(2),
                  bottomStart: Radius.circular(12),
                  bottomEnd: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  words,
                  if (time != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: message.isHidden
                            ? DeliveryColors.faint
                            : DeliveryColors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final String? name = message.isHidden ? null : (message.authorName ?? t.chatRoomNeighbour);
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(name: name),
          const SizedBox(width: DeliverySpacing.sm + 2),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (name != null)
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                        ),
                      ),
                    if (time != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(time, style: const TextStyle(fontSize: 10, color: DeliveryColors.faint)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onLongPress: message.isHidden ? null : () => unawaited(_actionsFor(message)),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxBubble),
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: DeliveryColors.white,
                      border: Border.all(color: DeliveryColors.border),
                      borderRadius: const BorderRadiusDirectional.only(
                        topStart: Radius.circular(2),
                        topEnd: Radius.circular(12),
                        bottomStart: Radius.circular(12),
                        bottomEnd: Radius.circular(12),
                      ),
                    ),
                    child: words,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The composer, or — while a moderator's mute is in force — until when it lasts.
  Widget _footer(DeliveryStrings t) {
    final NeighbourhoodRoom room = _room!;
    const BoxDecoration bar = BoxDecoration(
      color: DeliveryColors.white,
      border: Border(top: BorderSide(color: DeliveryColors.border)),
    );
    final DateTime? mutedUntil = room.mutedUntil;
    if (mutedUntil != null && room.isMutedAt(DateTime.now())) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DeliverySpacing.md),
        decoration: bar,
        child: Text(
          t.chatRoomMuted(_moment(mutedUntil)),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
        ),
      );
    }
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 2),
      decoration: bar,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _composer,
              enabled: !_sending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: t.chatRoomComposerHint,
                filled: true,
                fillColor: DeliveryColors.background,
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          ChatSendButton(label: t.chatSend, busy: _sending, onPressed: _send),
        ],
      ),
    );
  }
}

/// A neighbour's initial in the brand tint. The platform's profile pictures are not shared into
/// rooms: a photo next to a first name is a lot to hand a thousand strangers who live nearby.
class _Avatar extends StatelessWidget {
  const _Avatar({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final String? label = name;
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DeliveryColors.brandSoft, shape: BoxShape.circle),
        child: label == null || label.isEmpty
            ? const Icon(Icons.person_outline_rounded, size: 18, color: DeliveryColors.brand)
            : Text(
                String.fromCharCode(label.runes.first).toUpperCase(),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.brand),
              ),
      ),
    );
  }
}

/// The room rules, and the people the customer blocked with a way to unblock each. Tells the room
/// when somebody was unblocked, so it reloads with their messages back in it.
class _CommunitySheet extends StatefulWidget {
  const _CommunitySheet({required this.api, required this.onUnblocked});

  final NeighbourhoodChatApi api;
  final VoidCallback onUnblocked;

  @override
  State<_CommunitySheet> createState() => _CommunitySheetState();
}

class _CommunitySheetState extends State<_CommunitySheet> {
  List<BlockedNeighbour>? _blocks;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<BlockedNeighbour> blocks = await widget.api.blocks();
      if (mounted) setState(() => _blocks = blocks);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _unblock(BlockedNeighbour block) async {
    try {
      await widget.api.unblock(block.id);
      if (!mounted) return;
      widget.onUnblocked();
      setState(() => _blocks = _blocks?.where((BlockedNeighbour b) => b.id != block.id).toList());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<BlockedNeighbour>? blocks = _blocks;
    const TextStyle heading = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink);
    const TextStyle body = TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.45);

    return Semantics(
      container: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(t.chatRoomRulesTitle, style: heading),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.chatRoomRulesBody, style: body),
              const SizedBox(height: DeliverySpacing.lg),
              Text(t.chatRoomBlockedPeople, style: heading),
              const SizedBox(height: DeliverySpacing.sm),
              if (_failed)
                Text(t.chatActionFailed, style: body)
              else if (blocks == null)
                const Center(child: CircularProgressIndicator(color: DeliveryColors.brand))
              else if (blocks.isEmpty)
                Text(t.chatRoomNoBlocks, style: body)
              else
                for (final BlockedNeighbour block in blocks)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          block.name ?? t.chatRoomNeighbour,
                          style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_unblock(block)),
                        child: Text(t.chatRoomUnblock),
                      ),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
