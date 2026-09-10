import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'cart.dart';
import 'order_details_screen.dart';

/// One errand, in full — the page a recent-tasks row opens.
///
/// This exists because the list could not answer the question a customer actually has about an
/// errand, which is "what is happening with it?". A row carries one line: the title and a status
/// sentence. Everything else the server sends — where it is being bought, where it goes, who takes
/// it, what the shopper paid, what the fee is, when each step happened, why it ended — was fetched
/// and thrown away. Worse, a row did nothing when tapped until the errand had become an order, so
/// for the whole of the negotiation (the part that is unique to Butler and the part a customer is
/// most unsure about) there was nowhere to look.
///
/// Top to bottom: what the errand is and where it has got to; the steps as a timeline with the
/// moments the server recorded; the places and people; the money. The action — whichever one the
/// state allows — sits in a bar at the bottom so it is on screen however far the customer has
/// scrolled. Which actions appear is decided by the state the server reports, never by the client
/// guessing what may happen next (see [ButlerStatus]).
///
/// It keeps itself fresh the same way the list does: a silent re-read every few seconds while the
/// errand can still move, and straight after every action. It pops `true` when anything changed
/// while it was open, so the list behind it reloads at once instead of on its next poll.
class ButlerRequestDetailsScreen extends StatefulWidget {
  const ButlerRequestDetailsScreen({
    super.key,
    required this.request,
    required this.api,
    required this.orderApi,
    required this.storeApi,
    this.trackingApi,
    this.trackingSocket,
    this.chatApi,
    required this.cart,
  });

  /// The row that was tapped. The page draws it immediately and re-reads it behind the scenes, so
  /// it never flashes a spinner over information the list already had.
  final ButlerRequest request;
  final ButlerApi api;

  /// Threaded through for "Track order": an agreed errand is an ordinary order from then on, and
  /// the ordinary order screen is where its tracking, status and receipt already live.
  final OrderApi orderApi;
  final StoreApi storeApi;
  final TrackingApi? trackingApi;
  final UserQueueSocket? trackingSocket;
  final ChatApi? chatApi;
  final Cart cart;

  @override
  State<ButlerRequestDetailsScreen> createState() => _ButlerRequestDetailsScreenState();
}

class _ButlerRequestDetailsScreenState extends State<ButlerRequestDetailsScreen> {
  /// The list's five seconds, for the same reason: everything the customer is waiting for here
  /// happens on somebody else's phone. It stops once the errand is terminal — nothing more can
  /// happen to it, and an agreed one is followed on its order screen instead.
  static const Duration _pollInterval = Duration(seconds: 5);

  static const double _gutter = DeliverySpacing.lg;

  late ButlerRequest _r = widget.request;
  bool _busy = false;

  /// Whether the errand moved while this page was open — by the customer's hand or on a poll. This
  /// is what the page pops with, and what makes the list reload.
  bool _changed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (!_r.status.isTerminal) {
      _poll = Timer.periodic(_pollInterval, (_) => _pollOnce());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// A re-read the customer does not see happen. A failure keeps what is on screen: the page
  /// already has a perfectly readable errand, and replacing it with an error for a refresh nobody
  /// asked for would be a worse page.
  Future<void> _refresh() async {
    try {
      final ButlerRequest next = await widget.api.read(_r.id);
      if (!mounted) return;
      _take(next);
    } catch (_) {
      // Deliberately silent — see above.
    }
  }

  void _pollOnce() {
    if (!mounted || _busy) return;
    if (_r.status.isTerminal) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _refresh();
  }

  /// Adopts a fresh copy. A status that moved counts as a change the list should hear about, even
  /// when the customer did nothing — a quote that arrived while they were reading is news.
  void _take(ButlerRequest next) {
    setState(() {
      if (next.status != _r.status) _changed = true;
      _r = next;
    });
  }

  /// Runs one of the customer's actions, then re-reads the errand rather than trusting only the
  /// action's reply: the read is the same view every other screen gets, and a refusal usually
  /// means the errand moved underneath the customer (a quote landing as they tapped Cancel), which
  /// only a re-read shows them.
  Future<void> _act(Future<ButlerRequest> Function() call, String success) async {
    setState(() => _busy = true);
    try {
      final ButlerRequest answered = await call();
      if (!mounted) return;
      _changed = true;
      _take(answered);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(butlerActionMessage(e, DeliveryStrings.of(context)))));
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (!await confirmButlerCancel(context) || !mounted) return;
    await _act(() => widget.api.cancel(_r.id), t.cancelled);
  }

  /// "No thanks" is as final as Cancel — the errand ends declined, the shopper is left holding
  /// goods they paid for, and there is no undo — so it asks first for the same reason. It used to
  /// fire on one touch, a finger's width from "Pay".
  Future<void> _decline() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (!await confirmButlerDecline(context) || !mounted) return;
    await _act(() => widget.api.decline(_r.id), t.declined);
  }

  /// Exactly what the recent-tasks row used to do for an agreed errand, moved here so the row can
  /// open this page for every errand instead of only for the ones that had become orders.
  void _track() {
    final String? orderId = _r.orderId;
    if (orderId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OrderDetailsScreen(
        orderId: orderId,
        orderApi: widget.orderApi,
        storeApi: widget.storeApi,
        trackingApi: widget.trackingApi,
        trackingSocket: widget.trackingSocket,
        chatApi: widget.chatApi,
        cart: widget.cart,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ButlerRequest r = _r;
    final Widget? actions = _actions(t, r);

    // Every way out — the header's back chip, the system back gesture — goes through here, so the
    // list always learns whether anything changed. A plain pop would hand it null for the gesture.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? _) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: YdScreenHeader(
          title: t.butlerDetailsTitle,
          onBack: () => Navigator.of(context).maybePop(),
          backSemanticLabel: t.back,
        ),
        body: RefreshIndicator(
          color: DeliveryColors.brand,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
                _gutter, DeliverySpacing.md, _gutter, DeliverySpacing.lg),
            children: <Widget>[
              _summaryCard(t, r),
              const SizedBox(height: DeliverySpacing.md),
              _progressCard(t, r),
              const SizedBox(height: DeliverySpacing.md),
              _errandCard(t, r),
              const SizedBox(height: DeliverySpacing.md),
              _priceCard(t, r),
            ],
          ),
        ),
        bottomNavigationBar: actions == null ? null : _actionBar(actions),
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  /// The one thing the customer can do next, if there is one.
  ///
  /// * quoted — the decision, as the list's quote card draws it: "No thanks" beside "Pay X".
  ///   "No thanks" is final, so it asks first, as Cancel does.
  /// * claimed send — "Cancel" beside "Confirm X". A send has no price to quote, but it becomes an
  ///   order — something the rider can run, and the customer can track — only when the customer
  ///   approves it (infra/smoke-test-butler.js: "it goes straight from claimed to approved", on the
  ///   customer's token). Without this button a send sat at "Claimed" for good.
  /// * requested / claimed purchase — Cancel, behind a confirmation. The server refuses it once a
  ///   shopper has paid; by then the state is quoted and the exit is "No thanks" instead.
  /// * agreed — Track order, once the order it became exists.
  ///
  /// Every button here is the regular 52px pill: the bar has the room, and the compact 44 is under
  /// the 48dp Material minimum for the most consequential taps in Butler. In a pair the quiet
  /// button takes its natural width and the answer takes the rest, so "Pay 124.90" or
  /// "Confirm 2.50" is never the label that gets cut short on a narrow phone.
  Widget? _actions(DeliveryStrings t, ButlerRequest r) {
    return switch (r.status) {
      ButlerStatus.quoted => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Said again right above the button it concerns: a warning three cards up is one the
            // customer scrolled past.
            if (r.overBudget && r.budgetCap != null) ...<Widget>[
              _overBudgetNote(t, r),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            _answerPair(
              no: YdPillButton.secondary(
                label: t.noThanks,
                expand: false,
                busy: _busy,
                onPressed: _busy ? null : _decline,
              ),
              yes: YdPillButton(
                label: t.payAmount(_money(r.payableTotal)),
                busy: _busy,
                onPressed: _busy
                    ? null
                    : () => _act(() => widget.api.approve(r.id), t.approvedOnItsWay),
              ),
            ),
          ],
        ),
      ButlerStatus.claimed when r.awaitingApproval => _answerPair(
          no: YdPillButton.secondary(
            label: t.cancel,
            expand: false,
            busy: _busy,
            onPressed: _busy ? null : _cancel,
          ),
          yes: YdPillButton(
            label: t.butlerConfirmFee(_money(r.payableTotal)),
            busy: _busy,
            onPressed: _busy
                ? null
                : () => _act(() => widget.api.approve(r.id), t.butlerSendConfirmed),
          ),
        ),
      ButlerStatus.requested || ButlerStatus.claimed => YdPillButton.secondary(
          label: t.butlerCancelErrand,
          icon: Icons.close_rounded,
          busy: _busy,
          onPressed: _busy ? null : _cancel,
        ),
      ButlerStatus.approved when r.orderId != null => YdPillButton(
          label: t.butlerTrackOrder,
          icon: Icons.local_shipping_outlined,
          onPressed: _track,
        ),
      _ => null,
    };
  }

  Widget _answerPair({required Widget no, required Widget yes}) {
    return Row(
      children: <Widget>[
        no,
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(child: yes),
      ],
    );
  }

  Widget _actionBar(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
          _gutter, DeliverySpacing.md - DeliverySpacing.xs, _gutter, DeliverySpacing.md - DeliverySpacing.xs),
      child: SafeArea(top: false, child: child),
    );
  }

  // ------------------------------------------------------------------ cards

  /// What it is, which kind of errand, and the status in words — the same sentence the list row
  /// shows, so the page reads as the row opened up rather than as a different account of it.
  Widget _summaryCard(DeliveryStrings t, ButlerRequest r) {
    final ButlerStatusLook status = butlerStatusOf(r, t);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ButlerModeChip(mode: r.mode, background: DeliveryColors.brandSoft, size: 40),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      r.mode == ButlerMode.buy ? t.custBuyAnything : t.custSendAnything,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Not truncated: this is the one place the whole description is readable.
                    Text(
                      r.what,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge(
                label: status.label,
                color: status.text,
                background: status.fill,
                uppercase: false,
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(
            butlerSummaryLine(r, t),
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(DeliveryStrings t, ButlerRequest r) {
    final List<_Step> steps = _stepsFor(t, r);
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(title: t.butlerDetailProgress),
          const SizedBox(height: DeliverySpacing.md),
          for (int i = 0; i < steps.length; i++)
            _stepRow(
              t,
              steps[i],
              last: i == steps.length - 1,
              // The connector is lit when the step it leads to has happened.
              leadsToReached: i < steps.length - 1 &&
                  (steps[i + 1].state == _StepState.done ||
                      steps[i + 1].state == _StepState.stopped),
            ),
        ],
      ),
    );
  }

  /// The errand's steps, as far as they apply to this one.
  ///
  /// A step is drawn as reached when the server recorded its moment, or when the status is already
  /// past it — the status is the source of truth, and a missing timestamp on an old record must not
  /// make a finished step look undone. A send has nothing to price, so it has no quote step at all:
  /// the server refuses to quote one and takes it straight from claimed to agreed.
  ///
  /// An errand that ended early (cancelled before anyone took it, expired on the board) shows only
  /// the steps it actually passed through and then how it ended — greyed-out steps it will never
  /// reach would read as if they might still happen.
  ///
  /// A step that has not happened is worded as something still to happen — "Waiting for a
  /// shopper", "You agree the price" — and only takes its past-tense label once it has. The first
  /// cut drew the steps ahead in their finished wording, so a brand-new request read "A shopper
  /// took it · Price quoted · Price agreed", and a screen reader said exactly that: a blind
  /// customer was told the price was already agreed. The dot alone cannot carry that difference.
  List<_Step> _stepsFor(DeliveryStrings t, ButlerRequest r) {
    final bool buying = r.mode == ButlerMode.buy;
    final ButlerStatus s = r.status;
    final bool claimed = r.claimedAt != null ||
        s == ButlerStatus.claimed ||
        s == ButlerStatus.quoted ||
        s == ButlerStatus.approved ||
        s == ButlerStatus.declined;
    final bool quoted = buying &&
        (r.quotedAt != null ||
            s == ButlerStatus.quoted ||
            s == ButlerStatus.approved ||
            s == ButlerStatus.declined);
    // Each step as (once it has happened, while it is still to happen).
    final (String, String) claimedLabel = buying
        ? (t.butlerStepClaimedBuy, t.butlerStepClaimBuyPending)
        : (t.butlerStepClaimedSend, t.butlerStepClaimSendPending);
    final (String, String) quotedLabel = (t.butlerStepQuoted, t.butlerStepQuotePending);
    final (String, String) agreedLabel = buying
        ? (t.butlerStepAgreed, t.butlerStepAgreePending)
        : (t.butlerStepConfirmed, t.butlerStepConfirmPending);

    final List<_Step> steps = <_Step>[
      _Step(t.butlerStepRequested, _StepState.done, when: r.createdAt),
      if (claimed) _Step(claimedLabel.$1, _StepState.done, when: r.claimedAt),
      if (quoted) _Step(quotedLabel.$1, _StepState.done, when: r.quotedAt),
    ];

    switch (s) {
      case ButlerStatus.approved:
        steps.add(_Step(agreedLabel.$1, _StepState.done, when: r.resolvedAt));
      case ButlerStatus.declined:
        final String? reason = r.declineReason?.trim();
        steps.add(_Step(
          t.youDeclinedThisPrice,
          _StepState.stopped,
          when: r.resolvedAt,
          note: reason == null || reason.isEmpty ? null : t.butlerDeclineReason(reason),
        ));
      case ButlerStatus.cancelled:
        steps.add(_Step(t.cancelled, _StepState.stopped, when: r.resolvedAt));
      case ButlerStatus.expired:
        steps.add(_Step(t.butlerStatusExpired, _StepState.stopped,
            when: r.resolvedAt, note: t.nobodyPickedThisUp));
      case ButlerStatus.requested || ButlerStatus.claimed || ButlerStatus.quoted:
        // Still moving: what is left, in its still-to-happen wording, with the next one marked as
        // where it has got to. When that next step is the customer's own — agreeing a quote,
        // confirming a send — it says so.
        final List<String> ahead = <String>[
          if (!claimed) claimedLabel.$2,
          if (buying && !quoted) quotedLabel.$2,
          agreedLabel.$2,
        ];
        for (int i = 0; i < ahead.length; i++) {
          steps.add(_Step(
            ahead[i],
            i == 0 ? _StepState.current : _StepState.upcoming,
            note: i == 0 && r.awaitingApproval ? t.custWaitingOnYou : null,
          ));
        }
    }
    return steps;
  }

  /// One step: its dot and connector, then the label, the moment and any note.
  ///
  /// The row is one merged node for a screen reader, led by the step's state in words ("Done",
  /// "Now", "Still to come", "Ended"). The dot is the only other thing that tells a finished step
  /// from the one the errand is waiting on, and a dot says nothing aloud.
  Widget _stepRow(DeliveryStrings t, _Step step,
      {required bool last, required bool leadsToReached}) {
    final DateTime? when = step.when;
    final String stateWord = switch (step.state) {
      _StepState.done => t.butlerStepStateDone,
      _StepState.current => t.butlerStepStateNow,
      _StepState.upcoming => t.butlerStepStateNext,
      _StepState.stopped => t.butlerStepStateEnded,
    };
    // Three tiers a sighted customer can tell apart without the dot: ink for what happened, brand
    // for where it is now, muted for what is ahead. Muted rather than faint — faint is for
    // decoration and would put the steps ahead under AA.
    final Color labelColour = switch (step.state) {
      _StepState.done || _StepState.stopped => DeliveryColors.ink,
      _StepState.current => DeliveryColors.brand,
      _StepState.upcoming => DeliveryColors.muted,
    };

    final Widget row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                Semantics(label: stateWord, child: _StepDot(state: step.state)),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: leadsToReached
                          ? DeliveryAccent.positive.color
                          : DeliveryColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                  top: 2, bottom: last ? 0 : DeliverySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: labelColour,
                      height: 1.3,
                    ),
                  ),
                  if (when != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      _formatWhen(when),
                      style: const TextStyle(
                          fontSize: 12, color: DeliveryColors.faint, height: 1.3),
                    ),
                  ],
                  if (step.note != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      step.note!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: step.state == _StepState.current
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: step.state == _StepState.current
                            ? DeliveryColors.brand
                            : DeliveryColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return MergeSemantics(child: row);
  }

  /// Where it comes from, where it goes, and who to ask — each only when the customer gave one.
  /// The labels follow the form that collected them: a purchase is delivered *to* an address, a
  /// send is dropped *at* one.
  Widget _errandCard(DeliveryStrings t, ButlerRequest r) {
    final bool buying = r.mode == ButlerMode.buy;
    final String? from = _present(buying ? r.sourceHint : r.pickupAddress);
    final String? recipient = _present(r.recipient);
    final String? phone = _present(r.contactPhone);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(title: t.butlerDetailTheErrand),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (from != null)
            _fact(
              icon: buying ? Icons.storefront_outlined : Icons.my_location_outlined,
              label: buying ? t.butlerDetailWhereFrom : t.pickUpFrom,
              value: from,
            ),
          _fact(
            icon: Icons.location_on_outlined,
            label: buying ? t.deliverTo : t.dropOffAt,
            value: r.dropoffAddress,
          ),
          if (recipient != null)
            _fact(icon: Icons.person_outline, label: t.butlerDetailRecipient, value: recipient),
          if (phone != null)
            _fact(
              icon: Icons.phone_outlined,
              label: t.butlerDetailContactPhone,
              value: phone,
              // A phone number is a left-to-right token inside an Arabic page; laid out as Arabic
              // its leading "+" jumps to the wrong end.
              valueDirection: TextDirection.ltr,
            ),
        ],
      ),
    );
  }

  /// The money, line by line.
  ///
  /// For a purchase the goods price does not exist until the shopper has paid it, so until then
  /// the line says so instead of showing a zero, and no total is drawn — a "total" that is only
  /// the fee would be the one number on this page that is wrong. A send has no goods at all, so
  /// its total is the fee from the start.
  ///
  /// "Total to pay" is said only while the total can still be paid or has been agreed. A declined
  /// errand keeps the figure the customer turned down, under the plainer "Quoted total", so they
  /// can see what they said no to without being told they owe it. A cancelled or expired one has
  /// no total at all — nothing was agreed and nothing is owed — where it used to end on a bold
  /// "Total to pay 2.50", the one wrong number this comment set out to avoid.
  Widget _priceCard(DeliveryStrings t, ButlerRequest r) {
    final bool buying = r.mode == ButlerMode.buy;
    final bool priced = !buying || r.goodsCost != null;
    final String? totalLabel = switch (r.status) {
      ButlerStatus.cancelled || ButlerStatus.expired => null,
      ButlerStatus.declined => t.butlerDetailQuotedTotal,
      _ => t.butlerDetailTotal,
    };
    final String? receipt = _present(r.receiptRef);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(title: t.butlerDetailPrice),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (r.budgetCap != null)
            _moneyLine(t.butlerDetailBudgetCap, _money(r.budgetCap!)),
          if (buying && r.goodsCost != null)
            _moneyLine(t.butlerDetailGoods, _money(r.goodsCost!))
          else if (buying && !r.status.isTerminal)
            _moneyLine(t.butlerDetailGoods, t.butlerDetailGoodsPending, pending: true),
          _moneyLine(t.butlerDetailErrandFee, _money(r.deliveryFee)),
          if (priced && totalLabel != null) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
              child: Divider(height: 1, thickness: 1, color: DeliveryColors.border),
            ),
            _moneyLine(totalLabel, _money(r.payableTotal),
                strong: r.status != ButlerStatus.declined),
          ],
          if (r.overBudget && r.budgetCap != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            _overBudgetNote(t, r),
          ],
          if (receipt != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            _moneyLine(t.butlerDetailReceipt, receipt),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pieces

  Widget _fact({
    required IconData icon,
    required String label,
    required String value,
    TextDirection? valueDirection,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeliveryColors.background,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(icon, size: 16, color: DeliveryColors.muted),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  textDirection: valueDirection,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyLine(String label, String value, {bool strong = false, bool pending = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 15 : 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? DeliveryColors.ink : DeliveryColors.muted,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: pending ? 12 : (strong ? 16 : 14),
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                color: pending ? DeliveryColors.muted : DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The shopper's number came in above the ceiling the customer named. Amber and a glyph, not
  /// brand red: it is a warning to read before paying, not a failure.
  Widget _overBudgetNote(DeliveryStrings t, ButlerRequest r) {
    final Color caution = DeliveryAccent.caution.color;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs, vertical: DeliverySpacing.sm),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 18, color: caution),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.aboveYourCap(_money(r.budgetCap!)),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formatted through `intl` against the active locale, as the order screen does, so Arabic gets
  /// its own ordering and numerals rather than English ones rearranged. The server's instants are
  /// UTC; the customer reads them in their own time.
  String _formatWhen(DateTime when) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return intl.DateFormat.MMMd(locale).add_jm().format(when.toLocal());
  }

  static String? _present(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String _money(double value) => value.toStringAsFixed(2);
}

enum _StepState {
  /// Happened; the server has its moment.
  done,

  /// The step the errand is waiting on now.
  current,

  /// Still ahead.
  upcoming,

  /// How an errand that did not go through ended — declined, cancelled, expired.
  stopped,
}

class _Step {
  const _Step(this.label, this.state, {this.when, this.note});

  final String label;
  final _StepState state;
  final DateTime? when;
  final String? note;
}

/// The timeline's marker: a green tick for done, a brand ring for "here now", a hollow ring for
/// ahead, a grey cross for an ending that was not an agreement. Grey rather than red for that last
/// one, matching the list's status words — a cancelled errand is not an error.
class _StepDot extends StatelessWidget {
  const _StepDot({required this.state});

  final _StepState state;

  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _StepState.done => _filled(DeliveryAccent.positive.color, Icons.check_rounded),
      _StepState.stopped => _filled(DeliveryColors.faint, Icons.close_rounded),
      _StepState.current => Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: DeliveryColors.brand, width: 2),
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: DeliveryColors.brand, shape: BoxShape.circle),
          ),
        ),
      _StepState.upcoming => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: DeliveryColors.border, width: 2),
          ),
        ),
    };
  }

  Widget _filled(Color colour, IconData icon) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: DeliveryColors.white),
    );
  }
}

// ---------------------------------------------------------------------- shared with the list
//
// The list row and this page describe the same errand, and must say the same thing about it: a
// row reading "Claimed" that opens onto a page reading something else is the page contradicting
// itself. So the words, the colours, the icon and the cancel confirmation live here once, and the
// list uses them.

/// The round glyph for the kind of errand: a cart for a purchase, a parcel for a send.
class ButlerModeChip extends StatelessWidget {
  const ButlerModeChip({
    super.key,
    required this.mode,
    required this.background,
    this.size = 32,
  });

  final ButlerMode mode;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(
        mode == ButlerMode.buy ? Icons.shopping_cart_outlined : Icons.inventory_2_outlined,
        size: size * 0.56,
        color: DeliveryColors.brand,
      ),
    );
  }
}

/// The status word, the colour it is written in, and the fill of the [YdBadge] behind it.
typedef ButlerStatusLook = ({String label, Color text, Color fill});

/// How an errand's status is named and painted.
///
/// The design colour-codes green for finished and amber for outstanding; the states that are
/// neither take a slate neutral rather than borrowing one of those meanings, and anything waiting
/// on the customer is "Your call" in the brand's colours.
///
/// The word is written in a dark shade on a light fill, never in the accent itself: an accent on
/// its own 12% tint measures 1.96:1 for amber, 2.27:1 for green and 2.33:1 for the faint grey —
/// less than the same word on bare white, and far under the 4.5:1 a 12px label needs. The shades
/// used here reach 4.58 (amber), 4.90 (green), 6.9 (the ended states, muted on slate-100) and 7.3
/// ("Your call", brand-dark on brand-soft); a test holds every one to 4.5.
ButlerStatusLook butlerStatusOf(ButlerRequest r, DeliveryStrings t) {
  ButlerStatusLook accent(String label, DeliveryAccent a) =>
      (label: label, text: a.onTint, fill: a.tint);
  ButlerStatusLook ended(String label) =>
      (label: label, text: DeliveryColors.muted, fill: DeliveryColors.borderFaint);
  final ButlerStatusLook yourCall = (
    label: t.butlerStatusYourCall,
    text: DeliveryColors.brandDark,
    fill: DeliveryColors.brandSoft,
  );

  // A claimed send is the customer's call as much as a quote is: it waits on their Confirm.
  if (r.awaitingApproval) return yourCall;
  return switch (r.status) {
    ButlerStatus.requested => accent(t.custStatusPending, DeliveryAccent.caution),
    ButlerStatus.claimed => accent(t.butlerStatusClaimed, DeliveryAccent.caution),
    ButlerStatus.quoted => yourCall,
    ButlerStatus.approved => accent(t.butlerStatusAgreed, DeliveryAccent.positive),
    ButlerStatus.declined => ended(t.declined),
    ButlerStatus.cancelled => ended(t.cancelled),
    ButlerStatus.expired => ended(t.butlerStatusExpired),
  };
}

/// The one-sentence account of where an errand has got to. It carries the money as well as the
/// moment, which on a list of rows is the more useful of the two.
String butlerSummaryLine(ButlerRequest r, DeliveryStrings t) {
  String money(double value) => value.toStringAsFixed(2);
  return switch (r.status) {
    ButlerStatus.requested => t.waitingForShopper(money(r.deliveryFee)),
    // Not "a rider is on the way to collect it", which it used to say: nothing moves on a send
    // until the customer confirms the fee, and this is the sentence that tells them to.
    ButlerStatus.claimed => r.mode == ButlerMode.buy
        ? t.shopperIsOnIt
        : t.butlerSendAwaitingConfirm(money(r.payableTotal)),
    ButlerStatus.quoted =>
      t.goodsPlusFee(money(r.goodsCost ?? 0), money(r.deliveryFee), money(r.payableTotal)),
    ButlerStatus.approved => t.agreedAt(money(r.payableTotal)),
    ButlerStatus.declined => t.youDeclinedThisPrice,
    ButlerStatus.cancelled => t.cancelled,
    ButlerStatus.expired => t.nobodyPickedThisUp,
  };
}

/// The server's sentence where there is one. It is the side that knows why a request cannot be
/// cancelled once a shopper has paid for the goods, and says so.
String butlerActionMessage(Object error, DeliveryStrings t) {
  if (error is DioException) {
    final dynamic body = error.response?.data;
    if (body is Map && body['detail'] is String) return body['detail'] as String;
  }
  return t.thatDidNotWork;
}

/// Asks before an errand is cancelled.
///
/// Cancel used to fire on a single tap of an 11px link sitting right under the status word — the
/// easiest thing on the row to hit by accident, and there is no undo: a cancelled errand is
/// terminal and has to be requested again from scratch. Resolves `true` only on an explicit yes.
Future<bool> confirmButlerCancel(BuildContext context) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(t.butlerCancelConfirmTitle),
      content: Text(t.butlerCancelConfirmBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.keepIt),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: Text(t.butlerCancelConfirmYes),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Asks before a quote is declined.
///
/// Declining is as final as cancelling — the errand ends, it cannot be reopened, and the shopper is
/// left holding goods they paid for with their own money — and "No thanks" sat a finger's width from
/// "Pay". The way out is "Back" rather than "Keep it": beside a price, "keep it" reads as keeping
/// the goods, which is the opposite of what it would do. Resolves `true` only on an explicit yes.
Future<bool> confirmButlerDecline(BuildContext context) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(t.butlerDeclineConfirmTitle),
      content: Text(t.butlerDeclineConfirmBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.back),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: Text(t.butlerDeclineConfirmYes),
        ),
      ],
    ),
  );
  return yes ?? false;
}
