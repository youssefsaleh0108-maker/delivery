import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'shop_thread_screen.dart';
import 'visible_poller.dart';

/// The shop's conversations with its customers, newest first.
///
/// Which conversations a merchant sees is decided by the server — the shops Product Service confirms
/// the signed-in merchant owns — so this screen passes no shop id and cannot ask for another shop's
/// messages. Only conversations with something in them are listed: a customer who opened the chat
/// and wrote nothing is not a message. A conversation last opened about an order — by its customer
/// from the order, or by the shop from the order's "Chat with customer" — names that order on its row.
///
/// Shared by the mobile merchant shell (pushed from Settings, with a back header) and the portal's
/// merchant rail ([embedded], where the rail draws the chrome and the page carries its own title).
///
/// Without a [socket] — the portal on the web has none — nothing tells the page a customer wrote,
/// and pull-to-refresh is a gesture a desktop mouse cannot make. Such a host gets a refresh button by
/// the title, and the list asks again every half-minute while it is actually on screen: not from a
/// hidden tab, and not while a conversation is open over it.
class ShopInboxScreen extends StatefulWidget {
  const ShopInboxScreen({super.key, required this.api, this.socket, this.embedded = false});

  final ShopChatApi api;

  /// When present, a customer's new message refreshes the list as it arrives.
  final UserQueueSocket? socket;

  final bool embedded;

  @override
  State<ShopInboxScreen> createState() => _ShopInboxScreenState();
}

class _ShopInboxScreenState extends State<ShopInboxScreen> {
  /// Without a live feed, how often the list asks again while on screen. Gentle: a customer's
  /// question can wait half a minute, and a shop may leave the page open all day.
  static const Duration _pollEvery = Duration(seconds: 30);

  List<ShopThread>? _threads;
  bool _failed = false;

  StreamSubscription<ShopMessage>? _live;
  bool _wasConnected = false;

  /// Only for a host with no socket; see the class doc.
  VisiblePoller? _poller;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    final UserQueueSocket? socket = widget.socket;
    if (socket != null) {
      // The frame only says something arrived; the inbox line (unread, preview, order) is the
      // server's to compute, so a refetch is cheaper than keeping two answers in step.
      _live = ShopChatApi.live(socket).listen((_) => unawaited(_refresh()));
      _wasConnected = socket.connected.value;
      socket.connected.addListener(_onConnectivity);
    } else {
      _poller = VisiblePoller(every: _pollEvery, onTick: _refresh)..start();
    }
  }

  @override
  void dispose() {
    widget.socket?.connected.removeListener(_onConnectivity);
    _live?.cancel();
    _poller?.dispose();
    super.dispose();
  }

  void _onConnectivity() {
    final bool connected = widget.socket?.connected.value ?? false;
    if (connected && !_wasConnected) unawaited(_refresh());
    _wasConnected = connected;
  }

  Future<void> _refresh() async {
    try {
      final List<ShopThread> threads = await widget.api.inbox();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _open(ShopThread thread) async {
    final VisiblePoller? poller = _poller;
    // The conversation covers the list and keeps itself current; the list waits underneath.
    poller?.paused = true;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopThreadScreen(api: widget.api, thread: thread, socket: widget.socket),
    ));
    if (!mounted) return;
    if (poller != null) {
      // Uncovering asks at once: what was read and what arrived meanwhile both change the list.
      poller.paused = false;
    } else {
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Widget content = RefreshIndicator(
      color: DeliveryColors.brand,
      onRefresh: _refresh,
      child: _list(context, t),
    );

    if (widget.embedded) {
      return Scaffold(backgroundColor: Colors.transparent, body: content);
    }
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.chatShopInboxTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
        trailing: _refreshButton(t),
      ),
      body: content,
    );
  }

  /// Only where nothing else keeps the list current. With a live feed it would be a second way of
  /// doing what already happens by itself.
  Widget? _refreshButton(DeliveryStrings t) {
    if (widget.socket != null) return null;
    return IconButton(
      tooltip: t.refresh,
      icon: const Icon(Icons.refresh_rounded, color: DeliveryColors.ink),
      onPressed: () => unawaited(_refresh()),
    );
  }

  Widget _list(BuildContext context, DeliveryStrings t) {
    final Widget? refresh = _refreshButton(t);
    final List<Widget> heading = widget.embedded
        ? <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(t.chatShopInboxTitle, style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (refresh != null) refresh,
              ],
            ),
            const SizedBox(height: DeliverySpacing.md),
          ]
        : const <Widget>[];
    const EdgeInsets padding = EdgeInsets.all(DeliverySpacing.md);
    final List<ShopThread>? threads = _threads;

    if (threads == null && !_failed) {
      return ListView(padding: padding, children: <Widget>[
        ...heading,
        const Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        ),
      ]);
    }
    if (threads == null) {
      return ListView(padding: padding, children: <Widget>[
        ...heading,
        YdEmptyState(
          icon: Icons.cloud_off_outlined,
          title: t.chatShopInboxCouldNotLoad,
          action: YdPillButton(
            label: t.tryAgain,
            onPressed: () => unawaited(_refresh()),
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ),
      ]);
    }
    if (threads.isEmpty) {
      return ListView(padding: padding, children: <Widget>[
        ...heading,
        YdEmptyState(
          icon: Icons.forum_outlined,
          title: t.chatShopInboxEmpty,
          message: t.chatShopInboxEmptySub,
        ),
      ]);
    }

    // A merchant with more than one shop needs to know which shop each customer wrote to.
    final bool severalShops = threads.map((ShopThread th) => th.storeId).toSet().length > 1;
    return ListView(padding: padding, children: <Widget>[
      ...heading,
      for (final ShopThread thread in threads)
        Padding(
          padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
          child: _row(context, t, thread, severalShops),
        ),
    ]);
  }

  Widget _row(BuildContext context, DeliveryStrings t, ShopThread thread, bool severalShops) {
    final String name = thread.customerName ?? t.chatShopCustomer;
    final String? raw = thread.lastMessagePreview;
    final String? preview = raw == null
        ? null
        : thread.lastMessageSide == ShopThreadSide.shop
            ? t.chatShopYouPrefix(raw)
            : raw;
    final String? when = _when(context, thread.lastMessageAt);
    final bool unread = thread.unread > 0;
    final String? order = shopThreadOrderLabel(thread, t);

    return YdCard(
      onTap: () => unawaited(_open(thread)),
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          _Monogram(name: name),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                      ),
                    ),
                    if (when != null)
                      Text(when, style: const TextStyle(fontSize: 11, color: DeliveryColors.faint)),
                  ],
                ),
                if (severalShops)
                  Text(
                    thread.storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: DeliveryColors.muted),
                  ),
                // The order the conversation was last opened about, by its customer or by the shop: a
                // shop with two jobs on the go for one customer should not have to scroll back to know.
                if (order != null)
                  Text(
                    order,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: DeliveryColors.muted),
                  ),
                if (preview != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: unread ? DeliveryColors.ink : DeliveryColors.muted,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
                if (!thread.open) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  YdBadge(
                    label: t.chatShopQuietBadge,
                    color: DeliveryColors.muted,
                    background: DeliveryColors.background,
                    // A word, not a code: uppercasing reads as shouting in English and does nothing
                    // for Arabic.
                    uppercase: false,
                  ),
                ],
              ],
            ),
          ),
          if (unread) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DeliveryColors.brand,
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              ),
              child: Text(
                '${thread.unread}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryColors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Today's messages by time, older ones by date.
  static String? _when(BuildContext context, DateTime? at) {
    if (at == null) return null;
    final DateTime now = DateTime.now();
    final MaterialLocalizations words = MaterialLocalizations.of(context);
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return words.formatTimeOfDay(TimeOfDay.fromDateTime(at),
          alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
    }
    return words.formatShortMonthDay(at);
  }
}

/// A customer's initial in the brand tint — the platform holds no customer photo for a shop to see.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String initial = name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DeliveryColors.brandSoft, shape: BoxShape.circle),
        child: Text(
          initial,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.brand),
        ),
      ),
    );
  }
}
