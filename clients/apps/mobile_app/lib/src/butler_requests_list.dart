import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'butler_request_details_screen.dart';
import 'cart.dart';

/// The customer's errands, and the one place a quote gets answered.
///
/// This exists because Butler has a step no catalog order has: a shopper is standing in a shop
/// having spent their own money, and the customer has to say yes or no to a number. Without a
/// surface for that answer the request simply stalls, and the shopper is left holding goods nobody
/// has agreed to pay for.
///
/// The redesign's butler page (Figma 20:4) draws only a `recent-tasks` card — a history list with
/// no decision in it. It is drawn here as designed, with the requests waiting on an answer lifted
/// out of it and into their own cards above, in the same card language. That is not decoration:
/// a quote buried three rows down a history list is a quote nobody answers.
///
/// Every row, and every quote card, opens the errand's own page ([ButlerRequestDetailsScreen]).
/// Until that page existed a row was only tappable once the errand had become an order — for the
/// whole negotiation, the part a customer is least sure about, tapping it did nothing, and the one
/// action it offered was an 11px "Cancel" link that fired on a single touch.
class ButlerRequestsList extends StatefulWidget {
  const ButlerRequestsList({
    super.key,
    required this.api,
    required this.orderApi,
    required this.storeApi,
    this.trackingApi,
    this.trackingSocket,
    this.chatApi,
    required this.cart,
    required this.onOpenBasket,
    this.version = 0,
    this.query = '',
  });

  final ButlerApi api;
  final OrderApi orderApi;
  final StoreApi storeApi;
  final TrackingApi? trackingApi;

  /// The tracking service socket, threaded to the tracking panel for pushed positions.
  final UserQueueSocket? trackingSocket;
  final ChatApi? chatApi;
  final Cart cart;

  /// Handed to the order page an approved errand opens. See [OrderDetailsScreen.onOpenBasket].
  final VoidCallback onOpenBasket;

  /// Bumped by the form above when it submits, to reload without a manual pull.
  final int version;

  /// The butler header's search box. Filters the history in place — there is no task-search
  /// endpoint, and the list it searches is already in memory.
  final String query;

  @override
  State<ButlerRequestsList> createState() => _ButlerRequestsListState();
}

class _ButlerRequestsListState extends State<ButlerRequestsList> {
  /// The customer's side of the same five seconds the rider's board polls on.
  ///
  /// This half matters more. Everything a customer waits for on an errand happens on somebody
  /// else's phone: a rider claims it, shops, and quotes a price the customer then has to approve
  /// before anything else can happen. Until now nothing here asked again — the list loaded once
  /// and reloaded only when the customer acted or the parent bumped [ButlerRequestsList.version]
  /// — so the quote sat on the server and the customer sat looking at "waiting for a rider".
  static const Duration _pollInterval = Duration(seconds: 5);

  /// The Material minimum touch target. A row is the thing a customer taps to find out what is
  /// happening with their errand; it should never be a sliver of text to aim at.
  static const double _minTapTarget = 48;

  late Future<Paged<ButlerRequest>> _page = _load();

  /// The last page that loaded, so a poll refreshes the list rather than blanking it.
  Paged<ButlerRequest>? _latest;

  String? _busyId;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollInterval, (_) => _refreshSilently());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<Paged<ButlerRequest>> _load() async {
    final Paged<ButlerRequest> page = await widget.api.mine();
    _latest = page;
    return page;
  }

  /// A reload the customer does not see happen: the list stays on screen, an in-flight action is
  /// left alone, and a failed poll keeps the last good page rather than showing an error for a
  /// refresh nobody asked for.
  Future<void> _refreshSilently() async {
    if (!mounted || _busyId != null) {
      return;
    }
    try {
      final Paged<ButlerRequest> next = await _load();
      if (!mounted) {
        return;
      }
      setState(() => _page = Future<Paged<ButlerRequest>>.value(next));
    } catch (_) {
      // Deliberately silent — see above.
    }
  }

  /// The history card shows a handful; "See All" opens the rest. The design draws the link and
  /// this is the only place it can lead — there is no separate task screen to route to.
  bool _expanded = false;

  static const int _collapsedCount = 4;

  @override
  void didUpdateWidget(ButlerRequestsList old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _reload();
  }

  void _reload() {
    setState(() {
      _page = _load();
    });
  }

  Future<void> _run(String id, Future<ButlerRequest> Function() action, String success) async {
    setState(() => _busyId = id);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(butlerActionMessage(e, DeliveryStrings.of(context)))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Cancelling is terminal — the errand has to be asked for again from scratch — so it is asked
  /// about first, here exactly as on the details page.
  Future<void> _cancel(ButlerRequest r) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (!await confirmButlerCancel(context) || !mounted) return;
    await _run(r.id, () => widget.api.cancel(r.id), t.cancelled);
  }

  /// Declining a quote is as final as cancelling — the errand ends, and the shopper is left holding
  /// goods they paid for — so it asks first too, as on the details page.
  Future<void> _decline(ButlerRequest r) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (!await confirmButlerDecline(context) || !mounted) return;
    await _run(r.id, () => widget.api.decline(r.id), t.declined);
  }

  /// Opens the errand's page, and reloads at once if it changed while that page was open — so a
  /// customer who cancels or pays there comes back to a list that already says so, rather than one
  /// that catches up on its next poll.
  Future<void> _openDetails(ButlerRequest r) async {
    final bool? changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => ButlerRequestDetailsScreen(
        onOpenBasket: widget.onOpenBasket,
        request: r,
        api: widget.api,
        orderApi: widget.orderApi,
        storeApi: widget.storeApi,
        trackingApi: widget.trackingApi,
        trackingSocket: widget.trackingSocket,
        chatApi: widget.chatApi,
        cart: widget.cart,
      ),
    ));
    if (changed == true && mounted) _reload();
  }

  bool _matches(ButlerRequest r) {
    final String q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.what.toLowerCase().contains(q) ||
        (r.sourceHint ?? '').toLowerCase().contains(q) ||
        (r.pickupAddress ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<Paged<ButlerRequest>>(
      future: _page,
      // The last page, so the five-second poll refreshes the list instead of dropping the
      // customer back to a spinner. Only the very first load has nothing to show.
      initialData: _latest,
      builder: (BuildContext context, AsyncSnapshot<Paged<ButlerRequest>> snapshot) {
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(DeliverySpacing.lg),
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Text(t.couldNotLoadErrands,
                style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
          );
        }

        final List<ButlerRequest> all =
            snapshot.data!.content.where(_matches).toList(growable: false);

        // Anything waiting on an answer first, in its own card; the rest is history.
        final List<ButlerRequest> waiting =
            all.where((ButlerRequest r) => r.awaitingApproval).toList();
        final List<ButlerRequest> history =
            all.where((ButlerRequest r) => !r.awaitingApproval).toList();

        if (all.isEmpty) {
          // A search that matched nothing is worth saying; an account with no errands at all is
          // not — the form above it is the whole answer.
          return widget.query.trim().isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  child: Text(t.custNoTasksMatch,
                      style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
                );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final ButlerRequest r in waiting) ...<Widget>[
              _quoteCard(r),
              const SizedBox(height: DeliverySpacing.md),
            ],
            if (history.isNotEmpty) _historyCard(history),
          ],
        );
      },
    );
  }

  /// A request waiting on the customer, in the design's selected-card treatment — the brand tint
  /// with a brand hairline, which is exactly how the frame marks the thing you are being asked to
  /// choose.
  ///
  /// Two kinds of errand wait on the customer ([ButlerRequest.awaitingApproval]): a purchase the
  /// shopper has priced — "No thanks" / "Pay X" — and a send a rider has taken, which only becomes
  /// an order when the customer confirms the fee — "Cancel" / "Confirm X".
  ///
  /// The decision stays on the card, first: answering should never need a second screen. The card
  /// itself opens the details page, for a customer who wants to see the receipt or the timeline
  /// before saying yes — the buttons keep their own taps. Both are the regular 52px pill (the
  /// compact 44 is under the 48dp minimum), and the quiet one takes only its natural width so the
  /// answer, which carries the amount, is never the label cut short on a narrow phone. The quiet
  /// one asks before it ends the errand, as Cancel does everywhere.
  ///
  /// While one of its actions is in flight the card stops opening the page. A busy pill gives its
  /// InkWell a null onTap, so a tap on the spinner used to fall through to the card and open the
  /// page mid-request — a page that, having read the errand before the answer landed, offered Pay
  /// again, and a second approve is refused with an error for a payment that went through.
  Widget _quoteCard(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool busy = _busyId == r.id;
    final bool sending = r.mode == ButlerMode.send;
    final String total = r.payableTotal.toStringAsFixed(2);
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);

    return Material(
      color: DeliveryColors.brandSoft,
      shape: RoundedRectangleBorder(
        borderRadius: corners,
        side: const BorderSide(color: DeliveryColors.brand),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => _openDetails(r),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ButlerModeChip(mode: r.mode, background: DeliveryColors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.what,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  YdBadge.brand(label: t.custWaitingOnYou, uppercase: false, fontSize: 11),
                  _chevron(t),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                butlerSummaryLine(r, t),
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
              ),
              if (r.overBudget) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.aboveYourCap(r.budgetCap!.toStringAsFixed(2)),
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.brand, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              Row(
                children: <Widget>[
                  YdPillButton.secondary(
                    label: sending ? t.cancel : t.noThanks,
                    expand: false,
                    busy: busy,
                    onPressed: busy ? null : () => sending ? _cancel(r) : _decline(r),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: YdPillButton(
                      label: sending ? t.butlerConfirmFee(total) : t.payAmount(total),
                      busy: busy,
                      onPressed: busy
                          ? null
                          : () => _run(r.id, () => widget.api.approve(r.id),
                              sending ? t.butlerSendConfirmed : t.approvedOnItsWay),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `recent-tasks`: a bordered white card, a heading with a text action, and the rows.
  Widget _historyCard(List<ButlerRequest> history) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool truncated = history.length > _collapsedCount;
    final List<ButlerRequest> shown =
        _expanded || !truncated ? history : history.take(_collapsedCount).toList();

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(
            title: t.custRecentTasks,
            actionLabel: truncated ? (_expanded ? t.custShowLess : t.custSeeAll) : null,
            onAction: truncated ? () => setState(() => _expanded = !_expanded) : null,
          ),
          const SizedBox(height: DeliverySpacing.xs),
          for (int i = 0; i < shown.length; i++) ...<Widget>[
            // A hairline rather than a gap: each row now carries its own padding for the tap
            // target, and the rule is what keeps adjacent rows from reading as one.
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: DeliveryColors.borderFaint),
            _taskRow(shown[i]),
          ],
        ],
      ),
    );
  }

  /// `task-item`: the round icon chip, the title over its detail line, the status badge and a
  /// chevron that says the row opens something.
  ///
  /// The whole row is the target and is at least [_minTapTarget] tall. Cancel, where it is still
  /// possible, is a real button on its own line — the design system's secondary pill, labelled
  /// with what it cancels — instead of the 11px link it used to be, and it asks first. It is the
  /// regular 52px size: the compact one is 44, under the same 48dp minimum the row is held to.
  ///
  /// While the row's Cancel is in flight the row does not open the page, for the reason the quote
  /// card gives: a tap on the busy pill would otherwise fall through to the row.
  Widget _taskRow(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool busy = _busyId == r.id;
    final bool cancellable =
        r.status == ButlerStatus.requested || r.status == ButlerStatus.claimed;
    final ButlerStatusLook status = butlerStatusOf(r, t);

    // A transparent Material of its own: the card paints white over the Scaffold's Material, and
    // an ink ripple drawn underneath that white is a ripple nobody sees.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: busy ? null : () => _openDetails(r),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                vertical: DeliverySpacing.md - DeliverySpacing.xs, horizontal: DeliverySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ButlerModeChip(mode: r.mode, background: DeliveryColors.background),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              r.what,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.ink,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: DeliverySpacing.sm),
                          // 12px, the size the bare status word had before it became a badge;
                          // the badge's own default of 11 shrank it.
                          YdBadge(
                            label: status.label,
                            color: status.text,
                            background: status.fill,
                            uppercase: false,
                            fontSize: 12,
                          ),
                        ],
                      ),
                      const SizedBox(height: DeliverySpacing.xs),
                      // The frame puts a timestamp here. The status sentence carries the money as
                      // well as the moment, and on a list of four rows that is the more useful of
                      // the two; the moments are on the details page's timeline.
                      Text(
                        butlerSummaryLine(r, t),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                      ),
                      if (cancellable) ...<Widget>[
                        const SizedBox(height: DeliverySpacing.sm),
                        YdPillButton.secondary(
                          label: t.butlerCancelErrand,
                          icon: Icons.close_rounded,
                          expand: false,
                          busy: busy,
                          onPressed: busy ? null : () => _cancel(r),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: DeliverySpacing.xs),
                // The chip's height, so the chevron sits level with the title however tall the
                // row grows below it.
                SizedBox(height: 32, child: Center(child: _chevron(t))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "This opens something" — pointing forward in either direction.
  ///
  /// Always [Icons.chevron_right]: it is declared with `matchTextDirection`, so [Icon] already
  /// flips it in an RTL context. Picking chevron_left for Arabic, as this did (and as a few older
  /// screens still do), flips it a second time, so an Arabic row pointed back the way the customer
  /// came.
  Widget _chevron(DeliveryStrings t) {
    return Icon(
      Icons.chevron_right,
      size: 20,
      color: DeliveryColors.faint,
      semanticLabel: t.butlerViewDetails,
    );
  }
}
