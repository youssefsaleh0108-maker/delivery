import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'visible_poller.dart';

/// One conversation between a customer and a shop, drawn for whichever side is reading it.
///
/// A customer reaches it from the chat pill on a shop's page: [open] asks the server for the thread,
/// creating it the first time, so the pill never needs to know whether one exists. A merchant
/// reaches it from [ShopInboxScreen], which already holds the [thread]. The layout is the same for
/// both, in the conversation language order chat uses — the reader's own words in brand bubbles
/// against the end, the other side's in white against the start — so the two ends of one
/// conversation cannot drift apart.
///
/// Live over the app's one STOMP socket when the host has it, refetching from its sequence cursor on
/// every reconnect, so a dropped connection loses nothing. A host without one — the portal on the
/// web — gets a refresh button in the header and a catch-up every fifteen seconds while the
/// conversation is on screen, since nothing else would bring the other side's reply.
///
/// A thread goes quiet two weeks after the customer's last activity: the customer is offered Reopen,
/// and the shop is told why it cannot write, because only the customer can start a quiet
/// conversation again.
class ShopThreadScreen extends StatefulWidget {
  const ShopThreadScreen({
    super.key,
    required this.api,
    this.thread,
    this.open,
    this.title,
    this.socket,
  }) : assert(thread != null || open != null, 'Give the thread, or a way to open it');

  final ShopChatApi api;

  /// The thread the inbox already holds (the shop's side).
  final ShopThread? thread;

  /// Opens the caller's thread with a shop (the customer's side) — on first show, and again from
  /// the Reopen button once it has gone quiet.
  final Future<ShopThread> Function()? open;

  /// The header before the thread has loaded: the shop's name the customer tapped from.
  final String? title;

  /// Null loses only liveness: the other side's replies then appear on the next open.
  final UserQueueSocket? socket;

  @override
  State<ShopThreadScreen> createState() => _ShopThreadScreenState();
}

class _ShopThreadScreenState extends State<ShopThreadScreen> {
  /// Enough pages to catch up any real conversation, and a bound against a server that keeps
  /// saying there is more.
  static const int _maxPages = 20;

  /// The server refuses longer messages outright; saying so before sending saves a round trip.
  static const int _maxCodePoints = 1000;

  final TextEditingController _composer = TextEditingController();
  final Random _random = Random();

  ShopThread? _thread;

  /// Oldest first; the list renders it reversed so the newest sits at the bottom.
  List<ShopMessage> _messages = <ShopMessage>[];
  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;
  bool _reopening = false;

  /// The idempotency key of a send that got no answer, reused only if the same words are sent
  /// again — a retry must not post twice, and edited words must not be swallowed as a retry.
  String? _pendingText;
  String? _pendingClientId;

  StreamSubscription<ShopMessage>? _live;
  bool _wasConnected = false;

  /// Without a live feed, how often the conversation catches up while on screen: quick enough to read
  /// as a conversation, and each time one small request against the thread's cursor.
  static const Duration _pollEvery = Duration(seconds: 15);

  /// Only for a host with no socket; see the class doc.
  VisiblePoller? _poller;

  int get _cursor => _messages.isEmpty ? 0 : _messages.last.sequence;

  bool get _customerSide {
    final ShopThread? thread = _thread;
    if (thread != null) return thread.yourSide == ShopThreadSide.customer;
    return widget.open != null;
  }

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    unawaited(_load());

    final UserQueueSocket? socket = widget.socket;
    if (socket != null) {
      _live = ShopChatApi.live(socket).listen((ShopMessage message) {
        final ShopThread? thread = _thread;
        if (thread == null || message.threadId != thread.id) return;
        _fold(<ShopMessage>[message]);
        unawaited(_markRead(message.sequence));
      });
      _wasConnected = socket.connected.value;
      socket.connected.addListener(_onConnectivity);
    } else {
      _poller = VisiblePoller(
        every: _pollEvery,
        // Not while the first load is running: it is already doing exactly this.
        onTick: () => _loading ? Future<void>.value() : _catchUp(),
      )..start();
    }
  }

  @override
  void dispose() {
    widget.socket?.connected.removeListener(_onConnectivity);
    _live?.cancel();
    _poller?.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onConnectivity() {
    final bool connected = widget.socket?.connected.value ?? false;
    if (connected && !_wasConnected && _thread != null) {
      unawaited(_catchUp());
    }
    _wasConnected = connected;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final ShopThread thread = widget.thread ?? await widget.open!();
      if (!mounted) return;
      _thread = thread;
      await _catchUp(rethrowFailure: true);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Everything after the cursor, page by page, then a read receipt for it.
  Future<void> _catchUp({bool rethrowFailure = false}) async {
    final ShopThread? thread = _thread;
    if (thread == null) return;
    try {
      int cursor = _cursor;
      for (int page = 0; page < _maxPages; page++) {
        final ShopThreadPage result = await widget.api.messages(thread.id, afterSequence: cursor);
        if (!mounted) return;
        setState(() => _thread = result.thread);
        _fold(result.messages);
        if (!result.more || result.messages.isEmpty) break;
        cursor = result.messages.last.sequence;
      }
      if (_messages.isNotEmpty) {
        unawaited(_markRead(_messages.last.sequence));
      }
    } catch (_) {
      if (rethrowFailure) rethrow;
      // A background catch-up that fails is retried by the next reconnect or reopen.
    }
  }

  /// Merges rows by sequence: a live frame and a refetch can carry the same message.
  void _fold(List<ShopMessage> incoming) {
    if (!mounted || incoming.isEmpty) return;
    setState(() {
      final Map<int, ShopMessage> bySequence = <int, ShopMessage>{
        for (final ShopMessage m in _messages) m.sequence: m,
        for (final ShopMessage m in incoming) m.sequence: m,
      };
      _messages = bySequence.values.toList()
        ..sort((ShopMessage a, ShopMessage b) => a.sequence.compareTo(b.sequence));
    });
  }

  Future<void> _markRead(int upToSequence) async {
    final ShopThread? thread = _thread;
    if (thread == null) return;
    try {
      await widget.api.markRead(thread.id, upToSequence: upToSequence);
    } catch (_) {
      // Receipts are cumulative; the next one covers a lost one.
    }
  }

  Future<void> _reopen() async {
    final Future<ShopThread> Function()? open = widget.open;
    if (open == null || _reopening) return;
    setState(() => _reopening = true);
    try {
      final ShopThread thread = await open();
      if (!mounted) return;
      setState(() => _thread = thread);
    } catch (_) {
      if (!mounted) return;
      _say(DeliveryStrings.of(context).chatActionFailed);
    } finally {
      if (mounted) setState(() => _reopening = false);
    }
  }

  Future<void> _send() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ShopThread? thread = _thread;
    final String text = _composer.text.trim();
    if (thread == null || text.isEmpty || _sending || !thread.open) return;
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
      final ShopMessage sent =
          await widget.api.send(thread.id, text, clientMessageId: _pendingClientId);
      if (!mounted) return;
      _pendingText = null;
      _pendingClientId = null;
      _composer.clear();
      _fold(<ShopMessage>[sent]);
    } on ShopThreadQuietException {
      if (!mounted) return;
      setState(() => _thread = thread.copyWith(open: false));
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

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The header's refresh: the catch-up the poll makes, except that a failure is said rather than
  /// swallowed — somebody who asked should learn it did not work.
  Future<void> _refreshNow() async {
    try {
      await _catchUp(rethrowFailure: true);
    } catch (_) {
      if (mounted) _say(DeliveryStrings.of(context).chatShopCouldNotLoad);
    }
  }

  /// Only where nothing else keeps the conversation current, and only once there is one to refresh.
  Widget? _refreshButton(DeliveryStrings t) {
    if (widget.socket != null || _thread == null || _loading || _loadFailed) return null;
    return IconButton(
      tooltip: t.refresh,
      icon: const Icon(Icons.refresh_rounded, color: DeliveryColors.ink),
      onPressed: () => unawaited(_refreshNow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: _title(t),
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
        trailing: _refreshButton(t),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _reconnectingStrip(t),
            Expanded(child: _body(t)),
            if (_thread != null && !_loading && !_loadFailed) _footer(t),
          ],
        ),
      ),
    );
  }

  /// The other side: the shop's name for the customer, the customer's first name for the shop.
  String _title(DeliveryStrings t) {
    final ShopThread? thread = _thread;
    if (thread == null) return widget.title ?? '';
    if (thread.yourSide == ShopThreadSide.shop) {
      return thread.customerName ?? t.chatShopCustomer;
    }
    return thread.storeName.isNotEmpty ? thread.storeName : (widget.title ?? '');
  }

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
              horizontal: DeliverySpacing.md, vertical: DeliverySpacing.xs),
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

  Widget _body(DeliveryStrings t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_loadFailed) {
      return Center(
        child: YdEmptyState(
          icon: Icons.forum_outlined,
          title: t.chatShopCouldNotLoad,
          action: YdPillButton(
            label: t.tryAgain,
            onPressed: () => unawaited(_load()),
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Text(
            _customerSide ? t.chatShopEmptyCustomer : t.chatShopEmptyMerchant,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      itemCount: _messages.length,
      itemBuilder: (BuildContext context, int index) =>
          _bubble(_messages[_messages.length - 1 - index]),
    );
  }

  Widget _bubble(ShopMessage message) {
    final bool mine = message.mine;
    final Color foreground = mine ? DeliveryColors.white : DeliveryColors.ink;
    final Color meta = mine ? DeliveryColors.white.withValues(alpha: 0.7) : DeliveryColors.faint;
    final DateTime? sentAt = message.sentAt;
    final String? time = sentAt == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(sentAt),
            alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs, vertical: DeliverySpacing.sm),
        decoration: BoxDecoration(
          color: mine ? DeliveryColors.brand : DeliveryColors.white,
          border: mine ? null : Border.all(color: DeliveryColors.border),
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(DeliveryRadius.lg),
            topEnd: const Radius.circular(DeliveryRadius.lg),
            bottomStart: Radius.circular(mine ? DeliveryRadius.lg : DeliveryRadius.sm),
            bottomEnd: Radius.circular(mine ? DeliveryRadius.sm : DeliveryRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message.text, style: TextStyle(fontSize: 14, color: foreground, height: 1.35)),
            if (time != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(time, style: TextStyle(fontSize: 10, color: meta, height: 1.3)),
            ],
          ],
        ),
      ),
    );
  }

  /// The composer, or the sentence saying the conversation went quiet — with Reopen for the one side
  /// that can.
  Widget _footer(DeliveryStrings t) {
    final ShopThread thread = _thread!;
    const BoxDecoration bar = BoxDecoration(
      color: DeliveryColors.white,
      border: Border(top: BorderSide(color: DeliveryColors.border)),
    );
    const TextStyle quietStyle = TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4);

    if (!thread.open) {
      final bool canReopen = _customerSide && widget.open != null;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DeliverySpacing.md),
        decoration: bar,
        child: canReopen
            ? Row(
                children: <Widget>[
                  Expanded(child: Text(t.chatShopQuietCustomer, style: quietStyle)),
                  const SizedBox(width: DeliverySpacing.sm),
                  YdPillButton(
                    label: t.chatShopReopen,
                    onPressed: () => unawaited(_reopen()),
                    busy: _reopening,
                    size: YdPillButtonSize.compact,
                    expand: false,
                  ),
                ],
              )
            : Text(t.chatShopQuietMerchant, textAlign: TextAlign.center, style: quietStyle),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
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
                hintText: _customerSide ? t.chatShopHintCustomer : t.chatShopHintMerchant,
                filled: true,
                fillColor: DeliveryColors.background,
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          ChatSendButton(
            label: t.chatSend,
            busy: _sending,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

/// The round brand send button the chat screens share. The glyph points along the reading
/// direction, so it mirrors under RTL as the chevrons do.
class ChatSendButton extends StatelessWidget {
  const ChatSendButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: DeliveryColors.brand,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(DeliveryColors.white),
                    ),
                  )
                : Transform.flip(
                    flipX: Directionality.of(context) == TextDirection.rtl,
                    child: const Icon(Icons.send_rounded, size: 18, color: DeliveryColors.white),
                  ),
          ),
        ),
      ),
    );
  }
}
