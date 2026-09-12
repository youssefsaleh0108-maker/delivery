import 'dart:async';

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The customer app's offline strip (Figma 121:279), over every tab at once.
///
/// Mounted once, in the shell, above the tab stack — so it is true on whichever tab the customer is
/// on, and never covers the nav bar, which the shell's scaffold draws below everything. It wraps
/// the tabs rather than sitting beside them so that, while it shows, it can take the status-bar
/// inset for itself and remove it from the tabs underneath: each tab's header already pads for
/// the status bar, and both doing it would leave a gap.
///
/// Offline: the amber strip with the frame's `OFFLINE` pill at its start. The design paints that
/// pill into the phone's own status bar, which no app can draw into, so it leads the strip
/// instead. A "Saved items" link opens the cached catalog when the shell offers one.
///
/// Back online: a green "Back online" for a moment, then nothing — the design draws only the
/// offline state, but a strip that simply vanishes leaves the customer wondering whether the
/// queued order is on its way.
///
/// The words use amber-700 rather than the design's amber-600 (see
/// [DeliveryColors.cautionSoft]), which is too light to read at 13px on this ground.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    super.key,
    required this.connectivity,
    required this.child,
    this.onOpenSaved,
    this.backOnlineFor = const Duration(seconds: 3),
  });

  /// True while the platform can be reached.
  final ValueListenable<bool> connectivity;

  /// The tabs.
  final Widget child;

  /// Opens the cached catalog. Null draws no link.
  final VoidCallback? onOpenSaved;

  /// How long "Back online" stays up.
  final Duration backOnlineFor;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late bool _online = widget.connectivity.value;
  bool _justBack = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.connectivity.addListener(_changed);
  }

  @override
  void didUpdateWidget(OfflineBanner old) {
    super.didUpdateWidget(old);
    if (old.connectivity != widget.connectivity) {
      old.connectivity.removeListener(_changed);
      widget.connectivity.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.connectivity.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final bool online = widget.connectivity.value;
    if (online == _online) return;
    _hide?.cancel();
    setState(() {
      _justBack = online;
      _online = online;
    });
    if (online) {
      _hide = Timer(widget.backOnlineFor, () {
        if (mounted) setState(() => _justBack = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showing = !_online || _justBack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: AlignmentDirectional.topStart,
          child: showing
              ? (_online ? _backOnline(context) : _offline(context))
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: showing,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Widget _strip({required Color background, required Widget child}) => Semantics(
        container: true,
        liveRegion: true,
        child: ColoredBox(
          color: background,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md, vertical: 10),
              child: child,
            ),
          ),
        ),
      );

  Widget _offline(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Color ink = DeliveryAccent.caution.onTint;
    return _strip(
      background: DeliveryColors.cautionSoft,
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              t.offlinePill,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: DeliveryColors.white,
                letterSpacing: 0.4,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.offlineBanner,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
                height: 1.3,
              ),
            ),
          ),
          if (widget.onOpenSaved != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            Semantics(
              button: true,
              child: InkWell(
                onTap: widget.onOpenSaved,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(DeliverySpacing.xs),
                  child: Text(
                    t.offlineSavedItems,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      decoration: TextDecoration.underline,
                      decorationColor: ink,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _backOnline(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Color ink = DeliveryAccent.positive.onTint;
    return _strip(
      background: Color.alphaBlend(DeliveryAccent.positive.tint, DeliveryColors.white),
      child: Row(
        children: <Widget>[
          Icon(Icons.wifi_rounded, size: 16, color: ink),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.offlineBackOnline,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
