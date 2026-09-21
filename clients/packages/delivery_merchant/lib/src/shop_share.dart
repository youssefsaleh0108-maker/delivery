import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.origin = defaultShopPageOrigin,
    this.onShare,
    this.onFix,
  });

  final Store store;

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

  Widget _ready(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.qr_code_2, size: 20, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  t.merchShareTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            t.merchShareWhatTheySee,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md),
          Center(child: _qr(t)),
          const SizedBox(height: DeliverySpacing.md),
          Text(
            t.merchShareYourLink,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.faint,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          // Selectable, and left-to-right whatever the app's language: a URL read right-to-left is
          // a URL typed back wrong. In full, because half an address is not one.
          SelectableText(
            _url,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md),
          // Wrapped rather than a Row: three labels in two languages do not fit one line on a
          // 320dp phone, and an ellipsised "Print the pos…" is worse than a second line.
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              YdPillButton(
                label: t.merchShareShare,
                icon: Icons.ios_share,
                size: YdPillButtonSize.compact,
                expand: false,
                onPressed: () => _share(t),
              ),
              YdPillButton.secondary(
                label: t.merchShareCopyLink,
                icon: Icons.link,
                size: YdPillButtonSize.compact,
                expand: false,
                onPressed: () => _copy(t),
              ),
              YdPillButton.secondary(
                label: t.merchSharePrintPoster,
                icon: Icons.print_outlined,
                size: YdPillButtonSize.compact,
                expand: false,
                onPressed: () => _poster(t),
              ),
            ],
          ),
        ],
      ),
    );
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
    final Uri poster = Uri.parse('$_url/poster?lang=$lang');
    bool opened = false;
    try {
      opened = await launchUrl(poster, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A browser that blocked the new tab, or a device with nothing that opens a URL.
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.merchShareCouldNotOpenPoster),
        backgroundColor: DeliveryColors.brandDark,
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
            origin: widget.origin,
            onShare: widget.onShare,
            onFix: widget.onShopProfile,
          ),
        ),
      ),
    );
  }
}
