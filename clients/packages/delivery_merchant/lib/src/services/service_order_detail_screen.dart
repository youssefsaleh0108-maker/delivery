import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../order_detail_screen.dart';
import '../shop_inbox_screen.dart';
import 'service_order_files.dart';
import 'service_order_steps.dart';
import 'service_orders_screen.dart';
import 'service_words.dart';

/// One service order in full, for the shop that makes it: the job, the customer's instructions and
/// files, when it is promised, how it leaves, and the steps the server offers.
///
/// What the orders frame (126:200) leaves out and a print shop cannot work without — above all the
/// customer's design files, opened from short-lived links, and what they asked for in their own words.
///
/// "Chat with customer" opens the shop's conversations. Not one thread picked for this order: a shop
/// thread records no order (the server never writes one) and shows the shop only its customer's
/// display name, and two customers called "Mohammad K." are not rare. Opening the wrong one would put
/// one customer's order in front of another, so the shop chooses the conversation it recognises.
class ServiceOrderDetailScreen extends StatefulWidget {
  const ServiceOrderDetailScreen({
    super.key,
    required this.api,
    required this.order,
    this.onChanged,
    this.shopChat,
    this.chatSocket,
    this.files,
    this.openLink,
    this.clock,
  });

  final OrderApi api;

  /// The order as the queue last read it; read again on opening.
  final DeliveryOrder order;

  /// Told each time the order is read again, so the queue behind can refresh.
  final ValueChanged<DeliveryOrder>? onChanged;

  /// The shop's customer conversations. Null draws no chat button.
  final ShopChatApi? shopChat;

  final UserQueueSocket? chatSocket;

  /// The customer's files. Null draws no files section — see [ServiceOrderFiles].
  final ServiceOrderFiles? files;

  /// Opens a file's link. Null opens it with the platform, in the browser or the phone's viewer.
  final Future<bool> Function(Uri link)? openLink;

  final DateTime Function()? clock;

  @override
  State<ServiceOrderDetailScreen> createState() => _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState extends State<ServiceOrderDetailScreen> {
  late DeliveryOrder _order = widget.order;
  bool _busy = false;
  Future<List<ServiceOrderFile>>? _files;
  Timer? _minute;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _files = widget.files?.forOrder(widget.order.id);
    _reload();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ServiceOrderDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A host that hands over another order, or another files client, gets that order's files — never
    // the list the previous one left behind.
    if (oldWidget.order.id != widget.order.id || oldWidget.files != widget.files) {
      _order = widget.order;
      _files = widget.files?.forOrder(widget.order.id);
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  /// Reads the order again. Quiet when it fails: the order as the queue read it is still on screen,
  /// and its steps answer for themselves if it has moved on.
  Future<void> _reload() async {
    try {
      final DeliveryOrder fresh = await widget.api.read(_order.id);
      if (!mounted) return;
      setState(() => _order = fresh);
      widget.onChanged?.call(fresh);
    } catch (_) {
      // Kept as it was.
    }
  }

  Future<void> _step(SvcStep step) async {
    final SvcStepResult result = await SvcOrderSteps(widget.api).run(
      context,
      _order,
      step,
      onSending: () {
        if (mounted) setState(() => _busy = true);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == SvcStepResult.reload) await _reload();
  }

  void _reloadFiles() {
    setState(() {
      _files = widget.files?.forOrder(_order.id);
    });
  }

  /// Opens a file from a link that works now: the one held, or a fresh one when it has expired.
  Future<void> _openFile(ServiceOrderFile file) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      ServiceOrderFile current = file;
      if (file.isExpiredAt(_now())) {
        final List<ServiceOrderFile> fresh = await widget.files!.forOrder(_order.id);
        current = fresh.firstWhere((ServiceOrderFile f) => f.fileId == file.fileId);
        if (mounted) {
          setState(() {
            _files = Future<List<ServiceOrderFile>>.value(fresh);
          });
        }
      }
      final Uri link = Uri.parse(current.url);
      final bool opened = await (widget.openLink ?? _launch)(link);
      if (!opened) messenger.showSnackBar(SnackBar(content: Text(t.svcFileCouldNotOpen)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.svcFileCouldNotOpen)));
    }
  }

  static Future<bool> _launch(Uri link) =>
      launchUrl(link, mode: LaunchMode.externalApplication);

  void _openConversations() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopInboxScreen(api: widget.shopChat!, socket: widget.chatSocket),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<SvcStep> steps = svcStepsFor(_order);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MerchantScreenHeader(
              title: t.svcOrderTitle(_order.shortId),
              onBack: () => Navigator.of(context).maybePop(),
              backSemanticLabel: t.back,
              trailing: SvcOrderChip(order: _order),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                color: DeliveryColors.brand,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _sections(context, t),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (steps.isNotEmpty)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: DeliveryColors.white,
                  border: Border(top: BorderSide(color: DeliveryColors.border)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                      child: SvcStepRow(steps: steps, busy: _busy, onStep: _step),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, DeliveryStrings t) {
    final DeliveryOrder order = _order;
    final OrderLine? line = order.items.isEmpty ? null : order.items.first;
    final ServiceOrderLine? terms = order.serviceLine;
    final double amount = svcShopAmount(order);
    final String? lbp = svcLbp(amount, t);
    final String age = merchantTimeAgo(order.placedAt, t);
    final Widget? fulfilment = svcFulfilmentChip(order, t);
    final String Function(DateTime) when = svcWhenFormatter(context, clock: _now);
    final String? note = svcOrderNote(context, order, _now());
    // Before acceptance nothing is promised yet, so a new order says how long the work takes once the
    // shop accepts — from the terms it was ordered on, not the offer as it stands today.
    final String? turnaround = order.status == OrderStatus.placed
        ? svcTurnaroundWords(terms?.turnaroundMinHours, terms?.turnaroundMaxHours, t)
        : null;
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);

    return <Widget>[
      _Section(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SvcCustomerAvatar(name: order.customerDisplayName, size: 40),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        order.customerDisplayName ?? t.chatShopCustomer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                        ),
                      ),
                      if (age.isNotEmpty)
                        Text(age, style: const TextStyle(fontSize: 12, color: DeliveryColors.faint)),
                    ],
                  ),
                ),
                if (fulfilment != null) fulfilment,
              ],
            ),
            if (widget.shopChat != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              YdPillButton.secondary(
                label: t.svcChatWithCustomer,
                icon: Icons.chat_bubble_outline_rounded,
                size: YdPillButtonSize.compact,
                onPressed: _openConversations,
              ),
            ],
          ],
        ),
      ),
      gap,
      _Section(
        label: t.svcTheJob,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (line != null) ...<Widget>[
              Text(
                svcJobTitle(line, t),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              if (svcJobDetail(line, t) case final String detail)
                Text(
                  detail,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
                ),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            Wrap(
              spacing: DeliverySpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  svcUsd(amount, t),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.brand,
                  ),
                ),
                if (lbp != null)
                  Text(lbp, style: const TextStyle(fontSize: 12, color: DeliveryColors.faint)),
              ],
            ),
          ],
        ),
      ),
      gap,
      _Section(
        label: t.svcFulfilment,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (order.isPickup)
              _Fact(icon: Icons.storefront_outlined, text: t.svcFulfilmentPickupDetail)
            else if (order.fulfilment == Fulfilment.delivery)
              _Fact(
                icon: Icons.two_wheeler_outlined,
                text: t.svcFulfilmentDeliveryDetail(order.deliveryAddress),
              ),
            if (order.estimatedReadyAt case final DateTime promised)
              _Fact(
                icon: Icons.schedule_rounded,
                text: '${t.svcEstimatedReady}: ${when(promised)}',
              )
            else if (turnaround != null)
              _Fact(icon: Icons.schedule_rounded, text: t.svcTurnaroundAfterAccept(turnaround)),
            if (note != null && order.status != OrderStatus.accepted &&
                order.status != OrderStatus.preparing)
              _Fact(icon: Icons.info_outline_rounded, text: note),
          ],
        ),
      ),
      gap,
      _Section(
        label: t.svcInstructions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (terms?.instructionsPrompt case final String prompt)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.xs),
                child: Text(
                  prompt,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.35),
                ),
              ),
            Text(
              terms?.instructions ?? t.svcNoInstructions,
              style: TextStyle(
                fontSize: 14,
                color: terms?.instructions == null ? DeliveryColors.faint : DeliveryColors.ink,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      if (_files != null) ...<Widget>[
        gap,
        _Section(label: t.svcCustomerFiles, child: _filesBody(t)),
      ],
    ];
  }

  Widget _filesBody(DeliveryStrings t) {
    return FutureBuilder<List<ServiceOrderFile>>(
      future: _files,
      builder: (BuildContext context, AsyncSnapshot<List<ServiceOrderFile>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(DeliverySpacing.sm),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.svcFilesLoadFailed,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                ),
              ),
              TextButton(onPressed: _reloadFiles, child: Text(t.tryAgain)),
            ],
          );
        }
        final List<ServiceOrderFile> files = snap.data ?? const <ServiceOrderFile>[];
        if (files.isEmpty) {
          return Text(
            t.svcNoFiles,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < files.length; i++) ...<Widget>[
              if (i > 0) const MerchantDivider(),
              _FileRow(file: files[i], onOpen: () => _openFile(files[i])),
            ],
          ],
        );
      },
    );
  }
}

/// A white card with the frame's small label above its content.
class _Section extends StatelessWidget {
  const _Section({required this.child, this.label});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(
              label!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: DeliveryColors.faint),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onOpen});

  final ServiceOrderFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String kind = file.isImage ? t.svcFileImage : t.svcFileDocument;
    final String? size = svcFileSize(file.sizeBytes, t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          Icon(
            file.isImage ? Icons.image_outlined : Icons.description_outlined,
            size: 22,
            color: DeliveryColors.muted,
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              size == null ? kind : '$kind · $size',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.ink),
            ),
          ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(t.svcOpenFile),
          ),
        ],
      ),
    );
  }
}
