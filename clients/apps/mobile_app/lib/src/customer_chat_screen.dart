import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';


/// The customer's side of the order conversation.
///
/// Opened from the tracking panel's "Message the rider" entry. The thread is REST all the way:
/// reads and writes go through [ChatApi], and new messages from the rider arrive by polling with
/// the `afterSequence` cursor — the same cheap catch-up a socket reconnect would do, without this
/// screen owning a socket stack the app does not have yet.
///
/// There is deliberately no way to open a conversation from here: one exists exactly when the
/// server opened it (a rider was assigned), and until then the screen says so instead of
/// pretending a message could go somewhere.
class CustomerChatScreen extends StatefulWidget {
  const CustomerChatScreen({super.key, required this.api, required this.orderId});

  final ChatApi api;
  final String orderId;

  @override
  State<CustomerChatScreen> createState() => _CustomerChatScreenState();
}

class _CustomerChatScreenState extends State<CustomerChatScreen> {
  /// The rider app pings every few seconds; polling the thread faster only burns requests.
  static const Duration _pollInterval = Duration(seconds: 4);

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  ChatConversation? _conversation;
  List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;

  /// The idempotency key for the send currently being attempted. Kept across a failed attempt so
  /// a retry of the same text cannot post twice.
  String? _pendingClientId;

  Timer? _poll;

  /// The highest sequence on screen — the cursor for "everything after".
  int get _lastSequence =>
      _messages.isEmpty ? 0 : _messages.map((ChatMessage m) => m.sequence).reduce(
          (int a, int b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final ChatConversation conversation =
          await widget.api.conversationForOrder(widget.orderId);
      final List<ChatMessage> messages = await widget.api.messages(conversation.id);
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _messages = messages;
        _loading = false;
      });
      _markRead();
    } catch (_) {
      // 404 (no rider assigned yet, or not this caller's order) and a network failure land the
      // same way: there is no thread to show, and the screen says so with a retry.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// The cheap catch-up: only what arrived after the highest sequence already on screen.
  Future<void> _refresh() async {
    final ChatConversation? conversation = _conversation;
    if (conversation == null) {
      // The conversation opens server-side when a rider is assigned; keep asking.
      if (_failed && !_loading) await _load();
      return;
    }
    try {
      final List<ChatMessage> fresh =
          await widget.api.messages(conversation.id, afterSequence: _lastSequence);
      if (!mounted || fresh.isEmpty) return;
      final Set<String> seen = _messages.map((ChatMessage m) => m.id).toSet();
      setState(() {
        _messages = <ChatMessage>[
          ..._messages,
          ...fresh.where((ChatMessage m) => !seen.contains(m.id)),
        ]..sort((ChatMessage a, ChatMessage b) => a.sequence.compareTo(b.sequence));
      });
      _markRead();
    } catch (_) {
      // A missed poll is replaced by the next one. The thread on screen stays.
    }
  }

  /// "I have read up to here." Fire and forget — a lost receipt is re-sent by the next poll.
  void _markRead() {
    final ChatConversation? conversation = _conversation;
    final int upTo = _lastSequence;
    if (conversation == null || upTo == 0) return;
    unawaited(widget.api
        .markRead(conversation.id, upToSequence: upTo)
        .catchError((Object _) => 0));
  }

  Future<void> _send() async {
    final ChatConversation? conversation = _conversation;
    final String text = _composer.text.trim();
    if (conversation == null || text.isEmpty || _sending) return;

    // One idempotency key per attempted message, reused on retry so the server cannot store the
    // same sentence twice after a lost response.
    _pendingClientId ??=
        '${widget.orderId}-${DateTime.now().microsecondsSinceEpoch}';

    setState(() => _sending = true);
    try {
      final ChatMessage sent = await widget.api
          .send(conversation.id, text, clientMessageId: _pendingClientId);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _pendingClientId = null;
        _composer.clear();
        if (!_messages.any((ChatMessage m) => m.id == sent.id)) {
          _messages = <ChatMessage>[..._messages, sent]
            ..sort((ChatMessage a, ChatMessage b) => a.sequence.compareTo(b.sequence));
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final DeliveryStrings t = DeliveryStrings.of(context);
      if (e.response?.statusCode == 409) {
        // The conversation closed under us. Reflect it rather than inviting another attempt.
        setState(() => _conversation = null);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.chatClosed)));
      } else {
        // The text stays in the composer and the client id is kept, so trying again is one tap
        // and cannot double-post.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.chatCouldNotSend)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).chatCouldNotSend)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool open = _conversation?.open ?? false;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custChatWithRider,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _thread(t)),
          if (_conversation != null && !open) _closedBar(t),
          if (open) _composerBar(t),
        ],
      ),
    );
  }

  Widget _thread(DeliveryStrings t) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_failed && _conversation == null) {
      return YdEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: t.couldNotLoadChat,
        action: YdPillButton(
          label: t.tryAgain,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: _load,
        ),
      );
    }
    if (_messages.isEmpty) {
      return YdEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: t.chatNoMessagesYet,
      );
    }

    // Reversed so the newest message sits at the bottom and the list opens there, which is where
    // every chat opens.
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      itemCount: _messages.length,
      itemBuilder: (BuildContext context, int i) =>
          _bubble(t, _messages[_messages.length - 1 - i]),
    );
  }

  Widget _bubble(DeliveryStrings t, ChatMessage message) {
    final bool mine = message.mine;

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs,
            vertical: DeliverySpacing.sm + 2),
        decoration: BoxDecoration(
          color: mine ? DeliveryColors.brand : DeliveryColors.white,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(DeliveryRadius.lg),
            topEnd: const Radius.circular(DeliveryRadius.lg),
            bottomStart: Radius.circular(mine ? DeliveryRadius.lg : DeliverySpacing.xs),
            bottomEnd: Radius.circular(mine ? DeliverySpacing.xs : DeliveryRadius.lg),
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
                color: mine ? DeliveryColors.white : DeliveryColors.ink,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (message.sentAt != null)
                  Text(
                    MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(message.sentAt!)),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? DeliveryColors.white.withValues(alpha: 0.75)
                          : DeliveryColors.faint,
                      height: 1.2,
                    ),
                  ),
                if (mine) ...<Widget>[
                  const SizedBox(width: DeliverySpacing.xs),
                  Icon(
                    message.state == ChatMessageState.sent
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    size: 12,
                    color: message.state == ChatMessageState.read
                        ? DeliveryColors.white
                        : DeliveryColors.white.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The composer locked shut, in words rather than a greyed-out field with no explanation.
  Widget _closedBar(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded, size: 16, color: DeliveryColors.muted),
            const SizedBox(width: DeliverySpacing.sm),
            Text(
              t.chatClosed,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar(DeliveryStrings t) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.lg, vertical: DeliverySpacing.md - DeliverySpacing.xs),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(
                    fontSize: 14, color: DeliveryColors.ink, height: 1.35),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: DeliveryColors.background,
                  hintText: t.chatTypeMessage,
                  hintStyle: const TextStyle(
                      fontSize: 14, color: DeliveryColors.faint, height: 1.35),
                  contentPadding: const EdgeInsetsDirectional.symmetric(
                      horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Semantics(
              button: true,
              label: t.chatSend,
              child: Material(
                color: DeliveryColors.brand,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _sending ? null : _send,
                  child: SizedBox.square(
                    dimension: 40,
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: DeliveryColors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 18, color: DeliveryColors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
