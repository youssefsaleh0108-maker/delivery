import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// The hairline every merchant card separates its halves with, and the availability switch — the
// same control the catalogue list and the menu builder use, because "take orders at the table" is
// the same kind of promise as "this is on the shelf".
import 'order_detail_screen.dart';
import 'product_list_screen.dart';

/// Where a shop's public page lives.
///
/// A compile-time define rather than a value read from the session, because this is not the API:
/// the app talks to `api-dev.youdrop.shop` and the page a customer opens is `www.youdrop.shop`, and
/// the two move independently. The default is production's, so a build that forgets the define
/// still prints an address that works rather than an empty one.
///
/// It is also what the QR code encodes — the service builds those bytes from its own
/// `delivery.public.base-url` — so a build pointed somewhere else would show a code and an address
/// that disagree. Which is why the define is spelled with the service's own environment variable,
/// `PUBLIC_SITE_BASE_URL`: the two settings have to hold the same value, and a deploy script that
/// sets one can be seen not to have set the other. Overridable per widget only so a test can assert
/// against a fixed host.
const String defaultShopPageOrigin = String.fromEnvironment(
  'PUBLIC_SITE_BASE_URL',
  defaultValue: 'https://www.youdrop.shop',
);

/// The shop's own page, as something a merchant can hand to a customer: the address, the QR code,
/// and the three ways of passing them on.
///
/// <p>A card rather than a screen, because it has to sit in two different places without being two
/// different things. On the portal it is a block on **My shop** — a nav-rail tab of its own for one
/// QR code would be a tab a merchant visits once. On the phone it is both a block on Shop Profile
/// and the body of [ShopShareScreen], which the Settings list opens.
///
/// **The QR is drawn by the server, not here.** `/s/{slug}/qr.png` is a one-bit PNG the service
/// already renders for the page itself, cached for a year because it is a pure function of a slug
/// that never moves. Encoding it again in Dart would mean a second QR library, a second set of
/// error-correction choices, and a printed code from the poster that need not match the one on this
/// screen.
///
/// **Sharing is the host's, copying is ours.** This package builds for Android and for the web from
/// one source, and a share sheet exists on one of them. So the host passes [onShare] when it has a
/// real one — the phone's own chooser, which is what puts WhatsApp one tap away — and the web
/// passes nothing and falls back to the clipboard with a confirmation. Same for a share sheet the
/// person dismisses: it reports false, and the link is on the clipboard either way.
class ShopShareCard extends StatefulWidget {
  const ShopShareCard({
    super.key,
    required this.store,
    this.storeApi,
    this.origin = defaultShopPageOrigin,
    this.onShare,
    this.onFix,
  });

  final Store store;

  /// The client that saves how many tables the shop has.
  ///
  /// Null hides the table-codes block rather than drawing a stepper that cannot save. A host that
  /// wants the block passes its store client; the two that mount this card both have one.
  final StoreApi? storeApi;

  /// The public origin the page and the QR code live on. See [defaultShopPageOrigin].
  final String origin;

  /// The host's own share sheet, given the text to share; false when it did not share.
  ///
  /// Null on the web, where there is no sheet to open and the clipboard is the answer.
  final Future<bool> Function(String text)? onShare;

  /// Where the one missing thing is put right, for a shop that has no page yet.
  ///
  /// On Shop Profile it scrolls to the address card, which holds the map; from the Settings screen
  /// it opens Shop Profile. Null hides the button rather than showing a dead one.
  final VoidCallback? onFix;

  @override
  State<ShopShareCard> createState() => _ShopShareCardState();
}

class _ShopShareCardState extends State<ShopShareCard> {
  /// How many tables the stepper currently shows. Starts at what the shop has saved.
  late int _tables = widget.store.tableCount;

  /// The number the server last confirmed, so the sheet is only offered for codes that exist and a
  /// failed save can say what the shop still has.
  late int _savedTables = widget.store.tableCount;

  /// Whether the shop takes orders from those tables — what the web basket asks before drawing a
  /// pad. Distinct from having tables: a bakery may want the codes purely as a menu on the wall.
  late bool _ordering = widget.store.tableOrdering;
  late bool _savedOrdering = widget.store.tableOrdering;

  bool _savingTables = false;

  @override
  void didUpdateWidget(ShopShareCard old) {
    super.didUpdateWidget(old);
    // A host that reloaded the shop — Shop Profile saves and rebuilds — brings a new count with it.
    if (old.store.tableCount != widget.store.tableCount ||
        old.store.tableOrdering != widget.store.tableOrdering) {
      _tables = widget.store.tableCount;
      _savedTables = widget.store.tableCount;
      _ordering = widget.store.tableOrdering;
      _savedOrdering = widget.store.tableOrdering;
    }
  }
  /// The address as a customer would receive it — the one the QR code also encodes.
  ///
  /// The trailing slash is trimmed exactly as the service trims it off its own base URL, so a
  /// deploy that sets the two settings with different punctuation still produces one address
  /// rather than one with a doubled slash that a merchant would read out loud.
  String get _url {
    final String origin = widget.origin;
    return '${origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin}'
        '/s/${widget.store.slug}';
  }

  String get _qrUrl => '$_url/qr.png';

  /// The printable sheet of table cards, or one card of it.
  ///
  /// The parameter is `t`, spelled the same here as in the code the sheet draws and in the page
  /// the code opens — see `ShopTableCodes` in product-service. The web basket reads it back off
  /// the page, so a second spelling anywhere would be a card that scans to a page that does not
  /// know which table it came from.
  String _tablesUrl(String lang, {int? table}) =>
      '$_url/tables?lang=$lang${table == null ? '' : '&t=$table'}';

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // The pin first: a shop with no pin cannot be published either, so "publish it" would be an
    // instruction the server then refuses. See StoreNotListable.pinRequired.
    if (!widget.store.hasPin) {
      return _notReady(t, t.merchShareNeedsPin, t.merchSharePlaceOnMap,
          Icons.wrong_location_outlined);
    }
    if (!widget.store.status.isListed) {
      return _notReady(t, t.merchShareNeedsPublish, t.merchSharePublishYourShop,
          Icons.visibility_off_outlined);
    }
    return _ready(t);
  }

  // ---------------------------------------------------------------- the shop has a page

  /// The design's screen, as one column: the code and the address in a showcase card, three
  /// actions under it, and the table codes under those.
  ///
  /// A [Column] of cards rather than one card, because the design draws them as separate surfaces
  /// and because the table block has to be able to be absent — a host with no store client, or a
  /// shop with no page, gets the first two and nothing that would not work.
  Widget _ready(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _showcase(t),
        const SizedBox(height: DeliverySpacing.md + DeliverySpacing.xs),
        _actions(t),
        if (widget.storeApi != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md + DeliverySpacing.xs),
          _tableCodes(t),
        ],
      ],
    );
  }

  /// The code, the address and the one line that says what a stranger will find.
  Widget _showcase(DeliveryStrings t) {
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md + DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            t.merchShareWhatTheySee,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md),
          _qr(t),
          const SizedBox(height: DeliverySpacing.md),
          // The design's address row: the address and, beside it, the copy that used to be a pill
          // of its own. A background-tinted strip, so the address reads as the thing being handed
          // over rather than as another line of prose.
          Container(
            padding: const EdgeInsets.fromLTRB(
              DeliverySpacing.md - DeliverySpacing.xs,
              DeliverySpacing.sm,
              DeliverySpacing.sm,
              DeliverySpacing.sm,
            ),
            decoration: BoxDecoration(
              color: DeliveryColors.background,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  // Selectable, and left-to-right whatever the app's language: a URL read
                  // right-to-left is a URL typed back wrong. In full, because half an address is
                  // not one.
                  child: SelectableText(
                    _url,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                IconButton(
                  onPressed: () => _copy(t),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: DeliveryColors.brand,
                  tooltip: t.merchShareCopyLink,
                  // A 24px glyph in the design; a 40px box around it, because a thumb needs one.
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The design's three tiles: download the code, print the poster, share the link.
  ///
  /// A [Wrap] of flexible tiles rather than a fixed three-across [Row]: "تحميل رمز QR" under a
  /// 20px glyph on a 320dp phone is wider than a third of the screen, and three ellipsised labels
  /// are worse than two rows of whole ones.
  Widget _actions(DeliveryStrings t) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = DeliverySpacing.sm;
        final double third = (constraints.maxWidth - gap * 2) / 3;
        // Below this a tile cannot hold a word, so the row becomes two rows of wider tiles.
        final double tile = third < 96 ? (constraints.maxWidth - gap) / 2 : third;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            _ActionTile(
              width: tile,
              icon: Icons.download_rounded,
              label: t.merchShareDownloadQr,
              onPressed: () => _open(_qrUrl, t.merchShareCouldNotOpenQr),
            ),
            _ActionTile(
              width: tile,
              icon: Icons.print_outlined,
              label: t.merchSharePrintQr,
              onPressed: () => _poster(t),
            ),
            _ActionTile(
              width: tile,
              icon: Icons.ios_share,
              label: t.merchShareShare,
              onPressed: () => _share(t),
            ),
          ],
        );
      },
    );
  }

  /// **Table QR codes.** A code per table, so an order started at one knows which table it is.
  ///
  /// The number is saved on the shop before any sheet is offered, because the codes are generated
  /// from it: the server refuses a card for a table the shop has not said it has, which is what
  /// keeps a merchant from printing twelve cards for a room with eight. It is also what makes a
  /// reprint work from any device and in any month — the count is the shop's, not this screen's.
  ///
  /// The sheet itself is a browser tab, like the poster and for the same reasons: printing is the
  /// browser's job, the paper size is in the sheet's own `@page` rules, and it is the same document
  /// whoever opens it.
  Widget _tableCodes(DeliveryStrings t) {
    final bool dirty = _tables != _savedTables || _ordering != _savedOrdering;
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md + DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.merchTablesTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            t.merchTablesWhat,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Wrapped so the label and the stepper stack instead of colliding at 320dp with a long
          // Arabic label.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              Text(
                t.merchTablesHowMany,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                ),
              ),
              _TableStepper(
                value: _tables,
                max: StoreApi.maxTables,
                busy: _savingTables,
                onChanged: (int next) => setState(() => _tables = next),
                fewerLabel: t.merchTablesFewer,
                moreLabel: t.merchTablesMore,
                valueLabel: t.merchTablesCount(_tables),
              ),
            ],
          ),
          // What happens after a diner scans a card. Off until the shop says otherwise: taking an
          // order is a promise that somebody is watching a screen, and a shop that prints codes so
          // people can read the menu at the table has made no such promise. The web basket reads
          // the same answer off the public page; nothing here draws a pad.
          if (_tables > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            MerchantDivider(),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.merchTablesOrderingTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ordering ? t.merchTablesOrderingOn : t.merchTablesOrderingOff,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DeliveryColors.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                MerchantAvailabilitySwitch(
                  value: _ordering,
                  busy: _savingTables,
                  semanticLabel: t.merchTablesOrderingTitle,
                  onChanged: (bool on) => setState(() => _ordering = on),
                ),
              ],
            ),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          YdPillButton(
            label: dirty || _savedTables == 0 ? t.merchTablesSave : t.merchTablesPrintSheet,
            icon: dirty || _savedTables == 0 ? null : Icons.print_outlined,
            size: YdPillButtonSize.compact,
            onPressed: _savingTables
                ? null
                : (dirty || _savedTables == 0 ? () => _saveTables(t) : () => _printTables(t)),
          ),
          if (_savedTables > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Text(
              t.merchTablesReprintOne,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // Every table, as a chip. A merchant replacing the card on table 7 taps 7 — which is
            // also what the printed sheet's own on-screen controls offer, so the two ways in agree.
            Wrap(
              spacing: DeliverySpacing.sm,
              runSpacing: DeliverySpacing.sm,
              children: <Widget>[
                for (int table = 1; table <= _savedTables; table++)
                  ActionChip(
                    label: Text('$table', textDirection: TextDirection.ltr),
                    tooltip: t.merchTablesReprintTable(table),
                    onPressed: () => _printTables(t, table: table),
                    side: const BorderSide(color: DeliveryColors.border),
                    backgroundColor: DeliveryColors.white,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveTables(DeliveryStrings t) async {
    final StoreApi? api = widget.storeApi;
    if (api == null || _savingTables) return;
    setState(() => _savingTables = true);
    try {
      // Both in one call, because they are one decision on one screen and because they constrain
      // each other: the server turns ordering off when the tables go to zero.
      final Store saved = await api.setTables(widget.store.id, _tables, ordering: _ordering);
      if (!mounted) return;
      setState(() {
        _savedTables = saved.tableCount;
        _tables = saved.tableCount;
        _savedOrdering = saved.tableOrdering;
        _ordering = saved.tableOrdering;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.merchTablesSaved(saved.tableCount))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tables = _savedTables;
        _ordering = _savedOrdering;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.merchTablesCouldNotSave),
          backgroundColor: DeliveryColors.brandDark,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingTables = false);
    }
  }

  Future<void> _printTables(DeliveryStrings t, {int? table}) async {
    final String lang = Localizations.localeOf(context).languageCode;
    await _open(_tablesUrl(lang, table: table), t.merchTablesCouldNotOpen);
  }

  /// The code, big enough to be scanned off this screen by somebody else's phone.
  Widget _qr(DeliveryStrings t) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 220 is comfortably scannable at arm's length; on a 320dp phone the card is narrower than
        // that, so the code takes what there is rather than overflowing.
        final double side = math.min(220, constraints.maxWidth);
        return Container(
          width: side,
          height: side,
          padding: const EdgeInsets.all(DeliverySpacing.sm),
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            border: Border.all(color: DeliveryColors.border),
          ),
          child: Semantics(
            label: t.merchShareQrLabel,
            image: true,
            child: Image.network(
              _qrUrl,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              // The portal is served from a different origin than the page, and CanvasKit decodes
              // a fetched image rather than an <img>, so a QR with no CORS header would be a blank
              // square on the web only. Falling back to an <img> element is what makes it appear.
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (BuildContext context, Object error, StackTrace? stack) => Center(
                child: Text(
                  t.merchShareQrFailed,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                ),
              ),
              loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) =>
                  progress == null
                      ? child
                      : const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: DeliveryColors.brand,
                            ),
                          ),
                        ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- the shop has no page

  /// What a shop that is not on the map, or not live, is shown instead of a code that leads nowhere.
  ///
  /// One sentence, one thing to do, and a way to get there. A dead QR printed and taped to a
  /// counter is worse than no QR at all, and a merchant who scanned their own would only find a
  /// 404 with nothing to explain it.
  Widget _notReady(DeliveryStrings t, String message, String action, IconData icon) {
    return YdCard.bordered(
      child: YdEmptyState(
        icon: icon,
        title: t.merchShareNoPageTitle,
        message: message,
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
        action: widget.onFix == null
            ? null
            : YdPillButton.secondary(
                label: action,
                onPressed: widget.onFix,
                size: YdPillButtonSize.compact,
                expand: false,
              ),
      ),
    );
  }

  // ---------------------------------------------------------------- the three actions

  Future<void> _copy(DeliveryStrings t) async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.merchShareLinkCopied)),
    );
  }

  /// The phone's own share sheet, or the clipboard.
  ///
  /// Only the link is shared, with no sentence wrapped around it: every chat app draws its own
  /// preview card from the page's Open Graph tags — the shop's name, its picture and what it sells
  /// — and a line of our prose in front of that is something the merchant would have to delete.
  Future<void> _share(DeliveryStrings t) async {
    final Future<bool> Function(String)? sheet = widget.onShare;
    if (sheet != null && await sheet(_url)) {
      return;
    }
    if (!mounted) return;
    await _copy(t);
  }

  /// Opens the printable sheet the service renders at `/s/{slug}/poster`.
  ///
  /// A browser tab rather than anything drawn here: printing is the browser's job, the paper sizes
  /// are in the sheet's own `@page` rules, and the poster is the same document whether it is opened
  /// from the phone, from the portal or from a link a merchant sends to whoever has the printer.
  /// It carries this app's language so the sheet comes out in the one the merchant is reading.
  Future<void> _poster(DeliveryStrings t) async {
    final String lang = Localizations.localeOf(context).languageCode;
    await _open('$_url/poster?lang=$lang', t.merchShareCouldNotOpenPoster);
  }

  /// Hands a URL to the browser, and says so when there is no browser to hand it to.
  ///
  /// The poster, the sheet of table cards and the QR image all go this way. **Download QR is a
  /// browser tab too, deliberately**: saving a picture is a thing the phone's browser and the
  /// desktop's already do, with the permissions and the destination folder the person has already
  /// chosen, and a downloader of our own would be a file plugin, a storage permission and a
  /// "where did it go" question on every platform — for a PNG that is one tap away from the page
  /// it opens.
  Future<void> _open(String url, String couldNot) async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // A browser that blocked the new tab, or a device with nothing that opens a URL.
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(couldNot), backgroundColor: DeliveryColors.brandDark),
    );
  }
}

/// One of the design's three square actions: a glyph over a short label, in a bordered tile.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final double width;
  final IconData icon;

  /// Already localised by the caller.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: YdCard.bordered(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md - DeliverySpacing.xs),
        radius: DeliveryRadius.md,
        onTap: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: DeliveryColors.brand),
            const SizedBox(height: DeliverySpacing.xs + 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The design's −/number/+ control for how many tables the room has.
///
/// Hand-drawn, like the availability switch and for the same reason: the design's is a 24px round
/// button either side of a bold number on a tinted strip, and there is no platform control that is
/// that. The buttons are 40px targets around 24px circles, because a thumb needs 40.
class _TableStepper extends StatelessWidget {
  const _TableStepper({
    required this.value,
    required this.max,
    required this.busy,
    required this.onChanged,
    required this.fewerLabel,
    required this.moreLabel,
    required this.valueLabel,
  });

  final int value;
  final int max;
  final bool busy;
  final ValueChanged<int> onChanged;

  /// All already localised by the caller.
  final String fewerLabel;
  final String moreLabel;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _button(Icons.remove, fewerLabel, value > 0 ? () => onChanged(value - 1) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm),
            child: Semantics(
              label: valueLabel,
              // The label replaces the digits rather than sitting beside them: "12" read out on
              // its own says nothing, and "12 tables, 12" says it twice.
              excludeSemantics: true,
              child: Text(
                '$value',
                // Western digits and left-to-right in both languages: this is the number the cards
                // are printed with and the number printed in each card's address.
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
          ),
          _button(Icons.add, moreLabel, value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? onPressed) {
    final bool enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Material(
            color: DeliveryColors.white,
            shape: const CircleBorder(side: BorderSide(color: DeliveryColors.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: SizedBox.square(
                dimension: 24,
                child: Icon(
                  icon,
                  size: 14,
                  color: enabled ? DeliveryColors.muted : DeliveryColors.border,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Share your shop, as its own screen — what the phone's Settings list opens.
///
/// The portal has no screen of its own for this: [ShopShareCard] sits on **My shop** there, which
/// is the page a merchant already opens to look at their shop. On the phone that page is two taps
/// in, so the Settings list carries a row of its own straight to this.
///
/// Resolves the shop the way every other screen in this package does — the first of
/// `StoreApi.mine` — so a merchant with several shops sees the same one here as on Shop Profile
/// rather than a different one, which would be worse than no choice at all.
class ShopShareScreen extends StatefulWidget {
  const ShopShareScreen({
    super.key,
    required this.api,
    this.origin = defaultShopPageOrigin,
    this.onShare,
    this.onShopProfile,
    this.onBack,
  });

  final StoreApi api;

  /// The public origin the page and the QR code live on. See [defaultShopPageOrigin].
  final String origin;

  /// The host's own share sheet. See [ShopShareCard.onShare].
  final Future<bool> Function(String text)? onShare;

  /// Opens Shop Profile, where the map pin and the publish button are. See [ShopShareCard.onFix].
  final VoidCallback? onShopProfile;

  final VoidCallback? onBack;

  @override
  State<ShopShareScreen> createState() => _ShopShareScreenState();
}

class _ShopShareScreenState extends State<ShopShareScreen> {
  Store? _store;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Store> mine = (await widget.api.mine(size: 20)).content;
      if (!mounted) return;
      setState(() {
        _store = mine.isEmpty ? null : mine.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: t.merchShareTitle,
            subtitle: _store?.name,
            onBack: widget.onBack,
            backSemanticLabel: t.back,
          ),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadYourShop,
        message: '$_error',
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    final Store? store = _store;
    if (store == null) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.noShopYet,
        message: t.shopCreatedAutomatically,
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        DeliverySpacing.md,
        DeliverySpacing.md,
        DeliverySpacing.md,
        DeliverySpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ShopShareCard(
            store: store,
            // This screen already holds the store client it resolved the shop with, so the table
            // codes block is drawn here and can save.
            storeApi: widget.api,
            origin: widget.origin,
            onShare: widget.onShare,
            onFix: widget.onShopProfile,
          ),
        ),
      ),
    );
  }
}
