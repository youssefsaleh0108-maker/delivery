import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';

/// The rider's side of one order conversation — the screen behind the order-detail header's chat
/// button, in the redesign's conversation language: white/brand bubbles on the page background,
/// card radii, the 20/12 white header bar.
///
/// Live over the app's one STOMP socket: the customer's messages arrive as frames and are folded
/// into the thread; the rider's own are posted over REST ([ChatApi.send]) because the socket is
/// receive-only by design. On every reconnect the screen refetches from its sequence cursor, which
/// is what makes a dropped connection lose nothing. Read receipts go up as a cursor too, so the
/// customer's ticks and the rider's badge agree with the server rather than with local optimism.
class RiderChatScreen extends StatefulWidget {
  const RiderChatScreen({
    super.key,
    required this.api,
    required this.conversation,
    required this.orderShortId,
    this.socket,
  });

  final ChatApi api;

  /// The conversation the order-detail screen already fetched — this screen never guesses ids.
  final ChatConversation conversation;

  /// The order reference for the header, so the rider knows which doorstep this thread is about.
  final String orderShortId;

  /// Null loses only liveness: messages still load, send and mark read; the other party's
  /// messages then arrive on the next open instead of mid-conversation.
  final UserQueueSocket? socket;

  @override
  State<RiderChatScreen> createState() => _RiderChatScreenState();
}

class _RiderChatScreenState extends State<RiderChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final Random _random = Random();

  /// Oldest first; the list view renders it reversed so the newest sits at the bottom.
  List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;

  /// Whether the composer accepts input. Starts from the conversation row and flips false the
  /// moment a send answers 409 — the server's way of saying the thread closed under us.
  late bool _open = widget.conversation.open;

  StreamSubscription<ChatFrame>? _live;
  bool _wasConnected = false;

  /// The highest sequence held locally — the cursor for "everything after" and for receipts.
  int get _cursor =>
      _messages.isEmpty ? 0 : _messages.last.sequence;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());

    final UserQueueSocket? socket = widget.socket;
    if (socket != null) {
      _live = ChatApi.live(socket).listen((ChatFrame frame) {
        if (frame.conversationId != widget.conversation.id) return;
        _fold(<ChatMessage>[frame.asMessage()]);
        // The thread is on screen, so what just arrived has been read.
        unawaited(_markRead(frame.sequence));
      });
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

  /// On every false→true edge, refetch from the cursor: whatever happened while the socket was
  /// down was not delivered here, and the durable copy is one GET away.
  void _onConnectivity() {
    final bool connected = widget.socket?.connected.value ?? false;
    if (connected && !_wasConnected) {
      unawaited(_fetchAfter(_cursor));
    }
    _wasConnected = connected;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final List<ChatMessage> messages =
          await widget.api.messages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      if (messages.isNotEmpty) {
        unawaited(_markRead(messages.last.sequence));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _fetchAfter(int cursor) async {
    try {
      final List<ChatMessage> missed = await widget.api
          .messages(widget.conversation.id, afterSequence: cursor);
      if (missed.isEmpty || !mounted) return;
      _fold(missed);
      unawaited(_markRead(missed.last.sequence));
    } catch (_) {
      // The next reconnect or reopen catches up; nothing here is lost.
    }
  }

  /// Merges rows into the thread, deduplicating by sequence — a frame and a refetch can both
  /// carry the same message, and it must render once.
  void _fold(List<ChatMessage> incoming) {
    if (!mounted) return;
    setState(() {
      final Map<int, ChatMessage> bySequence = <int, ChatMessage>{
        for (final ChatMessage m in _messages) m.sequence: m,
        for (final ChatMessage m in incoming) m.sequence: m,
      };
      _messages = bySequence.values.toList()
        ..sort((ChatMessage a, ChatMessage b) => a.sequence.compareTo(b.sequence));
    });
  }

  Future<void> _markRead(int upToSequence) async {
    try {
      await widget.api
          .markRead(widget.conversation.id, upToSequence: upToSequence);
    } catch (_) {
      // A lost receipt is re-covered by the next one — the cursor is cumulative.
    }
  }

  Future<void> _send() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String text = _composer.text.trim();
    if (text.isEmpty || _sending || !_open) return;

    setState(() => _sending = true);
    try {
      final ChatMessage sent = await widget.api.send(
        widget.conversation.id,
        text,
        // The sender's own idempotency key: a retry after a lost response does not post twice.
        clientMessageId:
            '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}',
      );
      if (!mounted) return;
      _composer.clear();
      _fold(<ChatMessage>[sent]);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        // The conversation closed under us. The composer locks and says so, exactly as it would
        // have had the screen been opened a minute later.
        setState(() => _open = false);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.riderChatSendFailed)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.riderChatSendFailed)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(context, t),
            _reconnectingStrip(t),
            Expanded(child: _thread(t)),
            _composerBar(t),
          ],
        ),
      ),
    );
  }

  /// The design's `back-header`: chevron, 16px bold title, the order reference against the end.
  Widget _header(BuildContext context, DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 20,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          YdBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: t.back,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.riderChatTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            t.riderOrderRef(widget.orderShortId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// A thin caution strip while the socket is down. Messages still send over REST; what the strip
  /// warns about is that the other party's replies are not arriving live.
  Widget _reconnectingStrip(DeliveryStrings t) {
    final UserQueueSocket? socket = widget.socket;
    if (socket == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: socket.connected,
      builder: (BuildContext context, bool connected, _) {
        if (connected) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: DeliveryAccent.caution.tint,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 20,
            vertical: DeliverySpacing.xs,
          ),
          child: Text(
            t.riderChatReconnecting,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DeliveryAccent.caution.color,
              height: 1.3,
            ),
          ),
        );
      },
    );
  }

  Widget _thread(DeliveryStrings t) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_loadFailed) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          YdEmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: t.riderChatCouldNotLoad,
          ),
          const SizedBox(height: DeliverySpacing.md),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
            child: RiderButton(
              label: t.tryAgain,
              style: RiderButtonStyle.outlined,
              onPressed: () => unawaited(_loadInitial()),
            ),
          ),
        ],
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          t.riderChatEmpty,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
      );
    }

    // Reversed so the newest message sits at the bottom and the view opens there — index 0 of a
    // reversed list is the last row of the thread.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (BuildContext context, int index) =>
          _bubble(t, _messages[_messages.length - 1 - index]),
    );
  }

  /// One message, in the card language: [DeliveryRadius.lg] corners with the corner nearest the
  /// sender pulled in to [DeliveryRadius.sm], brand fill for the rider's own words, white for the
  /// customer's.
  Widget _bubble(DeliveryStrings t, ChatMessage message) {
    final bool mine = message.mine;
    final Color background = mine ? DeliveryColors.brand : DeliveryColors.white;
    final Color foreground = mine ? DeliveryColors.white : DeliveryColors.ink;
    final Color meta = mine
        ? DeliveryColors.white.withValues(alpha: 0.7)
        : DeliveryColors.faint;

    final String? time = message.sentAt == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(message.sentAt!),
            alwaysUse24HourFormat:
                MediaQuery.of(context).alwaysUse24HourFormat);

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs,
          vertical: DeliverySpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(DeliveryRadius.lg),
            topEnd: const Radius.circular(DeliveryRadius.lg),
            bottomStart: Radius.circular(
                mine ? DeliveryRadius.lg : DeliveryRadius.sm),
            bottomEnd: Radius.circular(
                mine ? DeliveryRadius.sm : DeliveryRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: foreground,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (time != null)
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: meta,
                      height: 1.3,
                    ),
                  ),
                // The tick is only meaningful on the viewer's own bubbles: one check stored,
                // two delivered, two at full strength read.
                if (mine) ...<Widget>[
                  const SizedBox(width: DeliverySpacing.xs),
                  Icon(
                    message.state == ChatMessageState.sent
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    size: 12,
                    color: message.state == ChatMessageState.read
                        ? DeliveryColors.white
                        : meta,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The composer, or — once the thread has closed — the sentence saying it has.
  Widget _composerBar(DeliveryStrings t) {
    if (!_open) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DeliverySpacing.md),
        decoration: const BoxDecoration(
          color: DeliveryColors.white,
          border: Border(top: BorderSide(color: DeliveryColors.border)),
        ),
        child: Text(
          t.riderChatClosed,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.md,
        vertical: DeliverySpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
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
                hintText: t.riderChatHint,
                filled: true,
                fillColor: DeliveryColors.background,
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md,
                  vertical: DeliverySpacing.sm + 2,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Semantics(
            button: true,
            label: t.riderChatSend,
            child: Material(
              color: DeliveryColors.brand,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _sending ? null : _send,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                DeliveryColors.white),
                          ),
                        )
                      // The send glyph points along the reading direction, so it mirrors
                      // under RTL like the chevrons do.
                      : Transform.flip(
                          flipX:
                              Directionality.of(context) == TextDirection.rtl,
                          child: const Icon(Icons.send_rounded,
                              size: 18, color: DeliveryColors.white),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
