import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Who carries this shop's orders.
///
/// The merchant-facing half of the delivery marketplace. Until this existed a merchant took
/// whoever the platform sent, which is the thing the whole provider abstraction was built to stop.
///
/// Three choices, in order of how much control they give up: let the platform decide, name a
/// carrier, or use your own drivers. The second and third are the same mechanism — a merchant's own
/// fleet is a provider like any other — which is why they share this screen rather than living in
/// different places.
///
/// One column at every width, which is why this page needed no reshaping for the phone: the choice
/// is a list of mutually exclusive options and a list is what that is at 360dp and at 1600. What it
/// did need was gutters that do not eat a phone screen, controls a thumb can land on, and some sign
/// that a tap was received — see [_pending].
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  /// Below this the screen is on a phone and dresses for one.
  ///
  /// Measured against this widget's own constraints rather than the window's: the portal hands the
  /// page whatever is left beside its navigation rail, so a wide browser can still be a narrow
  /// column here, and a phone in landscape is not a desktop.
  static const double _phoneWidth = 600;

  late Future<_Loaded> _data = _load();

  /// Which control is waiting on the server, or null.
  ///
  /// This was a bool, which was enough to stop a second tap and not enough to say anything. On a
  /// desktop the round trip is a blink; on a phone it is long enough that a card absorbing a tap
  /// and then sitting there reads as a card that does not work, and the merchant taps it again.
  /// Naming the row lets exactly that row show it is busy.
  String? _pending;

  bool get _busy => _pending != null;

  // Prefixed rather than bare ids, so a provider id can never collide with one of the fixed rows.
  static const String _platformRow = 'platform';
  static const String _fleetRow = 'fleet';
  static const String _fallbackRow = 'fallback';
  static String _carrierRow(String id) => 'carrier:$id';

  Future<_Loaded> _load() async {
    // Together rather than in sequence: neither depends on the other, and the screen is unusable
    // until both have arrived.
    final List<Object> results = await Future.wait(<Future<Object>>[
      widget.api.available(),
      widget.api.policy(),
    ]);
    return _Loaded(
      results[0] as List<DeliveryProviderInfo>,
      results[1] as DeliveryPolicy,
    );
  }

  /// Re-fetch, and hand back a future that completes when the new data has landed.
  ///
  /// The future is the point: a pull-to-refresh spins until it resolves, so this cannot be the
  /// fire-and-forget [_reload].
  Future<void> _refresh() {
    final Future<_Loaded> next = _load();
    setState(() {
      _data = next;
    });
    // Swallowed deliberately. The FutureBuilder holding `next` is what reports a failed load, and
    // it will; letting the error escape here as well would log it a second time as an unhandled
    // exception thrown by a gesture.
    return next.then<void>((_) {}, onError: (Object _) {});
  }

  void _reload() {
    _refresh();
  }

  Future<void> _run(String row, Future<void> Function() action, String success) async {
    setState(() => _pending = row);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(e, DeliveryStrings.of(context)))));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  /// The sentence the service sent for this failure, if it sent one.
  ///
  /// Split out from [_messageFor] so a failed *load* can use it too without inheriting that
  /// method's 404 wording, which is about a carrier the merchant asked for and makes no sense when
  /// nothing has been asked for yet.
  static String? _serverDetail(Object error) {
    if (error is! DioException) return null;
    final dynamic body = error.response?.data;
    return body is Map && body['detail'] is String ? body['detail'] as String : null;
  }

  /// Takes the strings as an argument: this is static, so there is no context to read them from.
  static String _messageFor(Object error, DeliveryStrings t) {
    final String? detail = _serverDetail(error);
    if (detail != null) return detail;
    if (error is DioException && error.response?.statusCode == 404) {
      return t.carrierNotAvailableToYou;
    }
    return t.thatDidNotWork;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        // 24 on every side of a 360dp phone spends an eighth of the screen on empty margin,
        // and the cards inside carry two lines of wrapping text that would rather have it.
        final double gutter = narrow ? DeliverySpacing.md : DeliverySpacing.lg;

        return FutureBuilder<_Loaded>(
          future: _data,
          builder: (BuildContext context, AsyncSnapshot<_Loaded> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
            }
            if (snapshot.hasError) {
              return _loadFailed(snapshot.error!, gutter);
            }

            final _Loaded loaded = snapshot.data!;
            final DeliveryProviderInfo? ownFleet = loaded.available
                .where((DeliveryProviderInfo p) => p.kind == ProviderKind.merchant)
                .firstOrNull;

            // Pull to refresh, because on a phone there is nothing else. Which carriers exist and
            // whether this shop has a fleet are both decided elsewhere, and the portal had the
            // browser's reload button standing in for a control this page never needed to grow.
            // Harmless on the desktop it also renders on: Flutter's default web scroll behaviour
            // leaves mouse drags out of `dragDevices`, so a pointer cannot trigger this.
            return RefreshIndicator(
              onRefresh: _refresh,
              color: DeliveryColors.brand,
              child: ListView(
                // Short pages are the common case here — two carriers and a switch — and without
                // this the list refuses to overscroll, which means it refuses to be pulled.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  gutter,
                  gutter,
                  // Clears the gesture bar, so the fallback switch is not the thing sitting under
                  // it. `paddingOf`, not `viewPaddingOf`: a host that already wrapped this in a
                  // SafeArea has consumed the inset, and this must not add it a second time.
                  gutter + MediaQuery.paddingOf(context).bottom,
                ),
                children: <Widget>[
                  Text(DeliveryStrings.of(context).navDelivery,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    DeliveryStrings.of(context).whoCarriesBlurb,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: DeliverySpacing.lg),

                  SectionLabel(DeliveryStrings.of(context).whoCarriesYourOrders),
                  _platformOption(loaded.policy),
                  for (final DeliveryProviderInfo p in loaded.available
                      .where((DeliveryProviderInfo p) => p.kind != ProviderKind.merchant))
                    _carrierOption(p, loaded.policy),

                  const SizedBox(height: DeliverySpacing.lg),
                  SectionLabel(DeliveryStrings.of(context).yourOwnDrivers),
                  if (ownFleet == null)
                    _noFleetYet(narrow)
                  else ...<Widget>[
                    _carrierOption(ownFleet, loaded.policy),
                    const SizedBox(height: DeliverySpacing.xs),
                    SoftNote(
                      text: DeliveryStrings.of(context).fleetRidersBlurb,
                      accent: DeliveryAccent.info,
                    ),
                  ],

                  const SizedBox(height: DeliverySpacing.lg),
                  SectionLabel(DeliveryStrings.of(context).whenCarrierCannotTake),
                  _fallbackToggle(loaded.policy),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// A load that failed, and the way out of it.
  ///
  /// This used to be a bare centred line printing `'${snapshot.error}'`. Two things wrong with that
  /// on a phone, neither of which shows on a desktop: a DioException stringifies to its URI and its
  /// stack, which is most of a 360dp screen and tells a shop owner nothing, and there was no retry
  /// — the portal had the browser's reload button behind it, and the Android app has no such thing,
  /// so a merchant who opened this page inside a tunnel was stuck with a dead screen until they
  /// killed the app.
  Widget _loadFailed(Object error, double gutter) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              t.couldNotLoadCarriers(_serverDetail(error) ?? t.thatDidNotWork),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: DeliverySpacing.md),
            OutlinedButton(onPressed: _reload, child: Text(t.tryAgain)),
          ],
        ),
      ),
    );
  }

  Widget _platformOption(DeliveryPolicy policy) {
    return _option(
      selected: policy.platformDecides,
      busy: _pending == _platformRow,
      icon: Icons.auto_awesome_outlined,
      title: DeliveryStrings.of(context).letThePlatformChoose,
      subtitle: DeliveryStrings.of(context).whoeverIsAvailable,
      onTap: _busy
          ? null
          : () => _run(_platformRow, () => widget.api.choose(preferredProviderId: null).then((_) {}),
              DeliveryStrings.of(context).thePlatformWillChoose),
    );
  }

  Widget _carrierOption(DeliveryProviderInfo p, DeliveryPolicy policy) {
    final bool selected = policy.preferredProviderId == p.id;
    return _option(
      selected: selected,
      busy: _pending == _carrierRow(p.id),
      icon: p.kind == ProviderKind.merchant
          ? Icons.storefront_rounded
          : (p.isInHouse ? Icons.pedal_bike_rounded : Icons.local_shipping_rounded),
      title: p.name,
      // A carrier that cannot take work right now can still be chosen: a preference is a standing
      // choice, and their being closed tonight is not a reason to forget it.
      subtitle: p.canTakeWork
          ? p.kind.labelIn(DeliveryStrings.of(context))
          : DeliveryStrings.of(context).notTakingWorkNow(p.kind.labelIn(DeliveryStrings.of(context))),
      onTap: _busy
          ? null
          : () => _run(
              _carrierRow(p.id),
              () => widget.api
                  .choose(preferredProviderId: p.id, allowFallback: policy.allowFallback)
                  .then((_) {}),
              DeliveryStrings.of(context).carrierWillCarry(p.name)),
    );
  }

  Widget _noFleetYet(bool narrow) {
    final bool busy = _pending == _fleetRow;
    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              DeliveryStrings.of(context).ownDriversBlurb,
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            SizedBox(
              // Full width on a phone. At its natural size this is a 230dp button floating in a
              // 310dp card, and on a screen held in one hand the only action on the page should not
              // be something you have to aim at. A null width leaves the desktop button alone.
              width: narrow ? double.infinity : null,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(_fleetRow, () => widget.api.myFleet().then((_) {}),
                        DeliveryStrings.of(context).yourFleetIsSetUp),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: DeliveryColors.brand),
                      )
                    : const Icon(Icons.add, size: 18),
                label: Text(DeliveryStrings.of(context).setUpMyOwnDrivers),
              ),
            ),
          ],
        ),
    );
  }

  /// The choice that decides what happens on a bad night.
  Widget _fallbackToggle(DeliveryPolicy policy) {
    // Meaningless while the platform is choosing: there is nothing to fall back from.
    final bool enabled = !_busy && !policy.platformDecides;
    final bool busy = _pending == _fallbackRow;

    void set(bool value) => _run(
          _fallbackRow,
          () => widget.api
              .choose(preferredProviderId: policy.preferredProviderId, allowFallback: value)
              .then((_) {}),
          value
              ? DeliveryStrings.of(context).anotherCarrierMayStepIn
              : DeliveryStrings.of(context).onlyYourChosenCarrier,
        );

    return SoftCard(
      padding: EdgeInsets.zero,
      // A ListTile carrying its own Switch rather than a SwitchListTile, for the two things that
      // needs: a spinner where the thumb is while the change is in flight — a switch that does not
      // move until the server answers is the most convincing dead control on the page — and text
      // that stays at full contrast when the row is disabled. ListTile's disabled grey is black38,
      // and the sentence it would mute is the one explaining *why* the row is disabled.
      child: ListTile(
        // The whole row, not just the thumb: 32dp of switch is a poor target, and the label beside
        // it is where a thumb actually lands.
        onTap: enabled ? () => set(!policy.allowFallback) : null,
        title: Text(DeliveryStrings.of(context).letSomeoneElseStepIn),
        subtitle: Text(
          policy.platformDecides
              ? DeliveryStrings.of(context).onlyAppliesOnceChosen
              : policy.allowFallback
            ? DeliveryStrings.of(context).fallbackOnBlurb
            : DeliveryStrings.of(context).fallbackOffBlurb,
          style: const TextStyle(fontSize: 12.5, height: 1.3),
        ),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: DeliveryColors.brand),
              )
            : Switch(
                value: policy.allowFallback,
                onChanged: enabled ? set : null,
                activeThumbColor: DeliveryColors.brand,
              ),
      ),
    );
  }

  Widget _option({
    required bool selected,
    required bool busy,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: SoftCard(
        onTap: onTap,
        selected: selected,
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: selected ? DeliveryColors.brandSoft : DeliveryAccent.info.tint,
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
              ),
              child: Icon(icon,
                  size: 20,
                  color: selected ? DeliveryColors.brand : DeliveryAccent.info.color),
            ),
            const SizedBox(width: DeliverySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: selected ? DeliveryColors.brand : DeliveryColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: DeliveryColors.muted, height: 1.3)),
                ],
              ),
            ),
            // Same 21dp slot either way, so choosing a carrier does not reflow the text beside it.
            if (busy)
              const SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: DeliveryColors.brand),
              )
            else if (selected)
              const Icon(Icons.check_circle_rounded, color: DeliveryColors.brand, size: 21),
          ],
        ),
      ),
    );
  }
}

class _Loaded {
  const _Loaded(this.available, this.policy);

  final List<DeliveryProviderInfo> available;
  final DeliveryPolicy policy;
}
