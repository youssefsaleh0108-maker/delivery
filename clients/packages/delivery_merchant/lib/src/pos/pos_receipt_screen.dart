/// The settled sale as an artifact — Figma `pos-receipt` (94:859).
///
/// This screen reproduces a receipt; it never computes one. Every figure on it — the subtotal, the
/// tax, the total, the pound conversion, the change and the rounding — is read straight off
/// [PosReceipt] as the server wrote it, because a reprint that recalculates is a reprint that can
/// disagree with the drawer, with the Z-report and with the piece of paper the customer is holding.
/// The rate rendered here is the sale's own [PosReceipt.lbpPerUsd], snapshotted when the sale was
/// opened, never `MarketRates`: the market moves, a settled receipt does not.
///
/// **VAT.** The platform has no tax model yet and `vat_rate_bp` defaults to 0 per store, so the tax
/// line is drawn only when the receipt itself carries a non-zero rate. A hardcoded 11% on a shop
/// below the registration threshold would be a made-up figure on a document a customer keeps.
///
/// **Hosts.** Mounted by the phone shell and by the web portal, so it measures its own constraints
/// rather than the window: the receipt column is held at a paper-like measure and centred, and the
/// action row folds to a stack when there is not room for three buttons side by side.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../order_detail_screen.dart';

/// One completed walk-in sale, as it prints.
///
/// Two ways in, and both are supported because the till and the archive arrive from different
/// directions:
///
/// * straight from checkout, with [receipt] already in hand — the spec's "no API calls" path, and
///   the one that matters, because the customer is standing at the counter;
/// * as a reprint, with [api] and [saleId], where the receipt is fetched.
///
/// [api] is nullable because pos-service is not deployed yet. With neither a receipt nor a way to
/// fetch one the screen says so calmly instead of throwing.
class PosReceiptScreen extends StatefulWidget {
  const PosReceiptScreen({
    super.key,
    this.receipt,
    this.api,
    this.saleId,
    this.onNewSale,
    this.onPrint,
    this.onShare,
  });

  /// The receipt as checkout returned it. When present nothing is fetched.
  final PosReceipt? receipt;

  /// Only used for the reprint path and the refresh control. Null until pos-service ships.
  final PosApi? api;

  /// Which sale to fetch, when [receipt] was not handed over.
  final String? saleId;

  /// Clears the till and starts the next customer. The host owns that decision — on the phone it
  /// pops back to the terminal, in the portal it swaps the pane — so this screen only asks.
  ///
  /// Null falls back to popping the route, which is right for a reprint opened from the archive.
  final VoidCallback? onNewSale;

  /// Opens the server-rendered thermal-width HTML at the given URL.
  ///
  /// A callback rather than a `url_launcher` call: this package has no launcher dependency and the
  /// two hosts open a URL differently (a new browser tab in the portal, a Custom Tab on Android).
  /// When null the URL is copied to the clipboard, so the affordance still does something.
  final void Function(String url)? onPrint;

  /// Hands the host a plain-text rendering of the receipt to share — the WhatsApp path.
  ///
  /// When null the text is copied to the clipboard.
  final void Function(String text)? onShare;

  @override
  State<PosReceiptScreen> createState() => _PosReceiptScreenState();
}

class _PosReceiptScreenState extends State<PosReceiptScreen> {
  /// The measure the receipt column is held to.
  ///
  /// Narrower than [merchantMaxContentWidth] on purpose: this is the one merchant screen that is a
  /// picture of a piece of paper, and a receipt stretched to 720px stops reading as one. Below this
  /// it simply fills whatever the host gave it, so a 380dp phone loses nothing.
  static const double _receiptWidth = 460;

  /// Under this the three actions stack instead of sharing a row.
  ///
  /// "Print receipt" and "Share receipt" are two words each in English and longer in Arabic; three
  /// of them across less than this ellipsise into unreadable stubs.
  static const double _stackActionsBelow = 420;

  /// The padding around the receipt column.
  static const double _pagePad = DeliverySpacing.md + DeliverySpacing.xs;

  late Future<PosReceipt>? _receipt = _initial();

  String? get _saleId => widget.saleId ?? widget.receipt?.saleId;

  /// Whether there is anything to re-fetch. A receipt handed over by checkout is already the
  /// server's final word, so no refresh control is drawn over it.
  bool get _canReload => widget.api != null && _saleId != null;

  Future<PosReceipt>? _initial() {
    final PosReceipt? handed = widget.receipt;
    if (handed != null) {
      return Future<PosReceipt>.value(handed);
    }
    return _fetch();
  }

  Future<PosReceipt>? _fetch() {
    final PosApi? api = widget.api;
    final String? saleId = _saleId;
    if (api == null || saleId == null) {
      return null;
    }
    return api.receipt(saleId);
  }

  void _reload() {
    // Block body, not an arrow: an arrow returns the future out of the closure and setState asserts
    // against that (see product_list_screen.dart:76-82).
    setState(() {
      _receipt = _fetch();
    });
  }

  // ------------------------------------------------------------------- actions

  void _newSale() {
    final VoidCallback? handler = widget.onNewSale;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// The URL of the server-rendered printable, or null when there is nothing to open.
  ///
  /// The receipt's own [PosReceipt.htmlUrl] wins, because the server may have sent an absolute one;
  /// [PosApi.receiptHtmlUrl] is the path-only fallback, which the host resolves against its own
  /// base URL exactly as it does for every other call.
  String? _printUrl(PosReceipt receipt) =>
      receipt.htmlUrl ?? widget.api?.receiptHtmlUrl(receipt.saleId);

  Future<void> _print(PosReceipt receipt, DeliveryStrings t) async {
    final String? url = _printUrl(receipt);
    if (url == null) {
      return;
    }
    final void Function(String)? handler = widget.onPrint;
    if (handler != null) {
      handler(url);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.posReceiptSent)));
  }

  Future<void> _share(PosReceipt receipt, DeliveryStrings t) async {
    final String text = _plainText(context, receipt, t);
    final void Function(String)? handler = widget.onShare;
    if (handler != null) {
      handler(text);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.posReceiptSent)));
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Future<PosReceipt>? pending = _receipt;

    if (pending == null) {
      // Neither a receipt nor a way to fetch one — pos-service is not deployed, or this screen was
      // mounted without either. A calm sentence, not a crash.
      return _frame(
        t,
        null,
        YdEmptyState(
          icon: Icons.receipt_long_outlined,
          title: t.posReceipt,
          message: t.posTerminalUnavailable,
        ),
      );
    }

    return FutureBuilder<PosReceipt>(
      future: pending,
      builder: (BuildContext context, AsyncSnapshot<PosReceipt> snapshot) {
        if (snapshot.hasError) {
          return _frame(
            t,
            null,
            YdEmptyState(
              icon: Icons.cloud_off_rounded,
              title: t.posCouldNotLoadSale,
              message: _messageFor(snapshot.error!, fallback: t.posTerminalUnavailable),
              action: _canReload
                  ? YdPillButton.secondary(
                      label: t.tryAgain,
                      onPressed: _reload,
                      size: YdPillButtonSize.compact,
                      expand: false,
                    )
                  : null,
            ),
          );
        }

        final PosReceipt? receipt = snapshot.data;
        if (receipt == null) {
          return _frame(
            t,
            null,
            const Padding(
              padding: EdgeInsets.all(DeliverySpacing.xl),
              child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
            ),
          );
        }

        return _frame(t, receipt, _receiptBody(t, receipt));
      },
    );
  }

  /// The header band and the scrolling column under it, in the shape both hosts get.
  Widget _frame(DeliveryStrings t, PosReceipt? receipt, Widget body) {
    final String? label = receipt == null ? null : _receiptLabel(receipt);

    return ColoredBox(
      color: DeliveryColors.background,
      // Measured, not asked of MediaQuery: the portal hands this widget the space beside its rail,
      // which is narrower than the window.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MerchantScreenHeader(
                title: t.posReceipt,
                subtitle: label == null ? null : t.posReceiptNo(label),
                onBack: Navigator.of(context).canPop()
                    ? () => Navigator.of(context).maybePop()
                    : null,
                backSemanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
                trailing: _canReload
                    ? IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.muted,
                        tooltip: t.refresh,
                      )
                    : null,
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    _pagePad,
                    _pagePad,
                    _pagePad,
                    // The shell already spent the top inset; only the bottom one is this screen's
                    // to clear, and the primary action sits right on it.
                    _pagePad + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _receiptWidth),
                      child: body,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The receipt card and the actions under it.
  Widget _receiptBody(DeliveryStrings t, PosReceipt receipt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        YdCard.bordered(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ..._storeHeader(t, receipt),
              const SizedBox(height: DeliverySpacing.md),
              const MerchantDivider(),
              const SizedBox(height: DeliverySpacing.md),
              ..._meta(t, receipt),
              const SizedBox(height: DeliverySpacing.md),
              const MerchantDivider(),
              const SizedBox(height: DeliverySpacing.md),
              ..._lines(t, receipt),
              const SizedBox(height: DeliverySpacing.md),
              const MerchantDivider(),
              const SizedBox(height: DeliverySpacing.md),
              ..._totals(t, receipt),
              ..._payments(t, receipt),
              const SizedBox(height: DeliverySpacing.md),
              const MerchantDivider(),
              const SizedBox(height: DeliverySpacing.md),
              Text(
                receipt.footer ?? t.posThankYou,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.faint,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        _actions(t, receipt),
      ],
    );
  }

  // ------------------------------------------------------------------- blocks

  List<Widget> _storeHeader(DeliveryStrings t, PosReceipt receipt) {
    final List<Widget> out = <Widget>[];
    final String? name = _trimmed(receipt.storeName);
    if (name != null) {
      out.add(Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
      ));
    }
    for (final String? line in <String?>[receipt.storeAddress, receipt.storePhone]) {
      final String? value = _trimmed(line);
      if (value == null) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 2));
      out.add(Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.35),
      ));
    }
    if (out.isEmpty) {
      // A receipt with no store block still needs a title where the shop's name would be, or the
      // card opens on a bare list of numbers.
      out.add(Text(
        t.posReceipt,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
      ));
    }
    return out;
  }

  /// Receipt number, when it was issued, and who rang it up.
  List<Widget> _meta(DeliveryStrings t, PosReceipt receipt) {
    final List<Widget> rows = <Widget>[];
    final String? label = _receiptLabel(receipt);
    if (label != null) {
      rows.add(_metaRow(t.posReceiptNo(label), null));
    }
    final DateTime? issued = receipt.issuedAt;
    if (issued != null) {
      final MaterialLocalizations dates = MaterialLocalizations.of(context);
      final DateTime local = issued.toLocal();
      rows.add(_metaRow(
        dates.formatMediumDate(local),
        dates.formatTimeOfDay(TimeOfDay.fromDateTime(local)),
      ));
    }
    final String? cashier = _trimmed(receipt.cashierName);
    if (cashier != null) {
      rows.add(_metaRow(t.posCashier, cashier));
    }
    if (rows.isEmpty) {
      // Nothing identifies this receipt. Say what it is rather than collapsing the block into an
      // unexplained gap between two hairlines.
      rows.add(_metaRow(t.posReceipt, null));
    }
    return _spaced(rows, DeliverySpacing.xs);
  }

  Widget _metaRow(String label, String? value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      );

  List<Widget> _lines(DeliveryStrings t, PosReceipt receipt) {
    if (receipt.lines.isEmpty) {
      return <Widget>[
        Text(
          t.posCartEmpty,
          style: const TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.4),
        ),
      ];
    }

    final List<Widget> rows = <Widget>[
      for (final PosSaleLine line in receipt.lines) _line(t, line),
      const SizedBox(height: DeliverySpacing.sm),
      Text(
        t.posLinesCount(receipt.itemCount),
        style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.35),
      ),
    ];
    return rows;
  }

  Widget _line(DeliveryStrings t, PosSaleLine line) {
    // The unit price is the server's own per-unit figure; the line total is the server's own
    // product. Neither is multiplied here — see the money law on PosSale.
    final String qtyAndPrice = '${line.qty} × ${t.posUsd(line.unitPrice.amount)}';
    final String? options = _trimmed(line.optionsSummary);
    final String? sku = _trimmed(line.sku);

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.productName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.35,
                  ),
                ),
                if (options != null)
                  Text(
                    options,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.35,
                    ),
                  ),
                Text(
                  sku == null ? qtyAndPrice : '$qtyAndPrice · ${t.invSku(sku)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.faint,
                    height: 1.35,
                  ),
                ),
                if (line.refundedQty > 0)
                  Text(
                    line.refundedQty >= line.qty
                        ? t.posStatusRefunded
                        : t.posStatusPartiallyRefunded,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryAccent.critical.color,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            t.posUsd(line.lineTotal.amount),
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _totals(DeliveryStrings t, PosReceipt receipt) {
    final List<Widget> rows = <Widget>[
      _figure(t.posSubtotal, t.posUsd(receipt.subtotal.amount)),
    ];

    if (!receipt.discount.isZero) {
      // The minus is a rendering decision about which of two characters sits in front of the
      // server's digits, not arithmetic on them.
      rows.add(_figure(t.posDiscount, '−${t.posUsd(receipt.discount.unsigned)}'));
    }

    // ONLY when the store actually charges VAT. vat_rate_bp defaults to 0 and most dekkanes are
    // below the registration threshold; a hardcoded 11% would be an invented figure on a document
    // the customer keeps.
    if (receipt.vatRateBp != 0) {
      rows.add(_figure(t.posTax, t.posUsd(receipt.tax.amount)));
    }

    rows.add(_figure(
      t.posTotal,
      t.posUsd(receipt.total.amount),
      emphasis: true,
      // The sale's own conversion at the sale's own rate, both from the server. MarketRates is not
      // permitted here: a reprint must agree with the drawer after the market has moved.
      secondary: receipt.totalLbpExact > 0 ? t.posLbp(_group(receipt.totalLbpExact)) : null,
    ));

    if (receipt.lbpPerUsd > 0) {
      rows.add(Padding(
        padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.xs),
        child: Text(
          t.posRate(_group(receipt.lbpPerUsd)),
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
        ),
      ));
    }

    if (!receipt.refunded.isZero) {
      rows.add(const SizedBox(height: DeliverySpacing.xs));
      rows.add(_figure(
        t.posRefundedAmount,
        t.posUsd(receipt.refunded.amount),
        color: DeliveryAccent.critical.color,
      ));
    }

    return _spaced(rows, DeliverySpacing.xs);
  }

  List<Widget> _payments(DeliveryStrings t, PosReceipt receipt) {
    if (receipt.payments.isEmpty) {
      return const <Widget>[];
    }

    final List<Widget> rows = <Widget>[];

    for (final PosPayment payment in receipt.payments) {
      rows.add(_figure(payment.method.labelIn(t), t.posUsd(payment.applied.amount)));

      final Money? tendered = payment.tendered;
      if (tendered != null) {
        rows.add(_sub(t.posAmountTendered, t.posUsd(tendered.amount)));
      }
      final int? tenderedLbp = payment.tenderedLbp;
      if (tenderedLbp != null && tenderedLbp != 0) {
        rows.add(_sub(t.posAmountTendered, t.posLbp(_group(tenderedLbp))));
      }
      if (!payment.change.isZero) {
        rows.add(_sub(t.posChangeDue, t.posUsd(payment.change.amount)));
      }
      if (payment.changeLbp != 0) {
        rows.add(_sub(t.posChangeDue, t.posLbp(_group(payment.changeLbp))));
      }
      if (payment.cashRoundingLbp != 0) {
        // Booked so the drawer still sums exactly; shown so the cashier is not short by a note
        // nobody can account for.
        rows.add(_sub(t.posRoundingLbp, t.posLbp(_group(payment.cashRoundingLbp))));
      }
      final String? reference = _trimmed(payment.reference);
      if (reference != null) {
        rows.add(_sub(t.posCardReference, reference));
      }
    }

    return <Widget>[
      const SizedBox(height: DeliverySpacing.md),
      const MerchantDivider(),
      const SizedBox(height: DeliverySpacing.md),
      Text(
        t.posTenderMethod,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.muted,
          height: 1.35,
        ),
      ),
      const SizedBox(height: DeliverySpacing.xs),
      ..._spaced(rows, DeliverySpacing.xs),
    ];
  }

  /// One label-and-figure line.
  Widget _figure(
    String label,
    String value, {
    bool emphasis = false,
    String? secondary,
    Color? color,
  }) {
    final Color valueColor = color ?? (emphasis ? DeliveryColors.brand : DeliveryColors.ink);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasis ? 14 : 13,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
              color: emphasis ? DeliveryColors.ink : DeliveryColors.muted,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: emphasis ? 18 : 13,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                  color: valueColor,
                  height: 1.3,
                ),
              ),
              if (secondary != null)
                Text(
                  secondary,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The indented second tier under a tender — what was handed over, what came back.
  Widget _sub(String label, String value) => Padding(
        padding: const EdgeInsetsDirectional.only(start: DeliverySpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.35),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------ actions

  Widget _actions(DeliveryStrings t, PosReceipt receipt) {
    // Print is only offered where there is something to open — no server HTML and no client to
    // build a path from means the button would be a dead control.
    final bool canPrint = _printUrl(receipt) != null;

    final Widget print = YdPillButton.secondary(
      label: t.posPrintReceipt,
      icon: Icons.print_outlined,
      onPressed: canPrint ? () => _print(receipt, t) : null,
      size: YdPillButtonSize.compact,
    );
    final Widget share = YdPillButton.secondary(
      label: t.posShareReceipt,
      icon: Icons.ios_share,
      onPressed: () => _share(receipt, t),
      size: YdPillButtonSize.compact,
    );
    final Widget newSale = YdPillButton(
      label: t.posNewSale,
      icon: Icons.add_shopping_cart_outlined,
      onPressed: _newSale,
      size: YdPillButtonSize.compact,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _stackActionsBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (canPrint) ...<Widget>[print, const SizedBox(height: DeliverySpacing.sm)],
              share,
              const SizedBox(height: DeliverySpacing.sm),
              newSale,
            ],
          );
        }
        return Row(
          children: <Widget>[
            if (canPrint) ...<Widget>[
              Expanded(child: print),
              const SizedBox(width: DeliverySpacing.sm),
            ],
            Expanded(child: share),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(child: newSale),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- plain text

  /// The receipt as text, for the share sheet and the WhatsApp path.
  ///
  /// Built from the same server figures the card draws, and labelled with the same translated
  /// strings — a shared receipt that reads differently from the printed one is a support ticket.
  String _plainText(BuildContext context, PosReceipt receipt, DeliveryStrings t) {
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final StringBuffer out = StringBuffer();

    void line(String? value) {
      final String? trimmed = _trimmed(value);
      if (trimmed != null) out.writeln(trimmed);
    }

    line(receipt.storeName);
    line(receipt.storeAddress);
    line(receipt.storePhone);

    final String? label = _receiptLabel(receipt);
    if (label != null) line(t.posReceiptNo(label));

    final DateTime? issued = receipt.issuedAt;
    if (issued != null) {
      final DateTime local = issued.toLocal();
      line('${dates.formatMediumDate(local)} '
          '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(local))}');
    }
    final String? cashier = _trimmed(receipt.cashierName);
    if (cashier != null) line('${t.posCashier}: $cashier');

    out.writeln();
    for (final PosSaleLine item in receipt.lines) {
      final String options = _trimmed(item.optionsSummary) == null ? '' : ' (${item.optionsSummary})';
      out.writeln('${item.qty} × ${item.productName}$options  '
          '${t.posUsd(item.lineTotal.amount)}');
    }

    out.writeln();
    line('${t.posSubtotal}: ${t.posUsd(receipt.subtotal.amount)}');
    if (!receipt.discount.isZero) {
      line('${t.posDiscount}: −${t.posUsd(receipt.discount.unsigned)}');
    }
    if (receipt.vatRateBp != 0) {
      line('${t.posTax}: ${t.posUsd(receipt.tax.amount)}');
    }
    line('${t.posTotal}: ${t.posUsd(receipt.total.amount)}');
    if (receipt.totalLbpExact > 0) {
      line(t.posLbp(_group(receipt.totalLbpExact)));
    }
    if (!receipt.refunded.isZero) {
      line('${t.posRefundedAmount}: ${t.posUsd(receipt.refunded.amount)}');
    }

    for (final PosPayment payment in receipt.payments) {
      line('${payment.method.labelIn(t)}: ${t.posUsd(payment.applied.amount)}');
      if (!payment.change.isZero) {
        line('${t.posChangeDue}: ${t.posUsd(payment.change.amount)}');
      }
      if (payment.changeLbp != 0) {
        line('${t.posChangeDue}: ${t.posLbp(_group(payment.changeLbp))}');
      }
    }

    out.writeln();
    line(receipt.footer ?? t.posThankYou);
    return out.toString();
  }

  // ------------------------------------------------------------------ helpers

  /// What this receipt is called: the printed label if the store has a prefix, else the number.
  String? _receiptLabel(PosReceipt receipt) =>
      _trimmed(receipt.receiptLabel) ?? receipt.receiptNo?.toString();

  /// Puts a gap between every entry of [rows] without a trailing one.
  static List<Widget> _spaced(List<Widget> rows, double gap) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(rows[i]);
    }
    return out;
  }
}

/// Null for anything the server left empty, so a caller can drop the slot rather than print a blank
/// line on a receipt.
String? _trimmed(String? value) {
  if (value == null) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Thousands separators for an LBP figure.
///
/// Integers, never money: LBP is a whole-pound count on the wire and grouping its digits is a
/// display decision, not arithmetic. USD never comes near this — that stays [Money.amount], the
/// server's own text, unchanged.
String _group(int amount) {
  final bool negative = amount < 0;
  final String digits = amount.abs().toString();
  final StringBuffer out = StringBuffer();
  if (negative) out.write('-');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// Copied file-private from `product_list_screen.dart:799`. The spec promotes this into
/// `order_detail_screen.dart` beside `merchantMoney`; that edit belongs to the wiring step, and
/// reaching into another screen's private symbol from here is not an option.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
