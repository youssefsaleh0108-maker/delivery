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
/// carrier, or use your own drivers. The second and third are the same mechanism â€” a merchant's own
/// fleet is a provider like any other â€” which is why they share this screen rather than living in
/// different places.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late Future<_Loaded> _data = _load();
  bool _busy = false;

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

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(e, DeliveryStrings.of(context)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Takes the strings as an argument: this is static, so there is no context to read them from.
  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
      if (error.response?.statusCode == 404) return t.carrierNotAvailableToYou;
    }
    return t.thatDidNotWork;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Loaded>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Loaded> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        if (snapshot.hasError) {
          return Center(child: Text(DeliveryStrings.of(context).couldNotLoadCarriers('${snapshot.error}')));
        }

        final _Loaded loaded = snapshot.data!;
        final DeliveryProviderInfo? ownFleet = loaded.available
            .where((DeliveryProviderInfo p) => p.kind == ProviderKind.merchant)
            .firstOrNull;

        return ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            Text(DeliveryStrings.of(context).navDelivery, style: Theme.of(context).textTheme.headlineMedium),
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
              _noFleetYet()
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
        );
      },
    );
  }

  Widget _platformOption(DeliveryPolicy policy) {
    return _option(
      selected: policy.platformDecides,
      icon: Icons.auto_awesome_outlined,
      title: DeliveryStrings.of(context).letThePlatformChoose,
      subtitle: DeliveryStrings.of(context).whoeverIsAvailable,
      onTap: _busy
          ? null
          : () => _run(() => widget.api.choose(preferredProviderId: null).then((_) {}),
              DeliveryStrings.of(context).thePlatformWillChoose),
    );
  }

  Widget _carrierOption(DeliveryProviderInfo p, DeliveryPolicy policy) {
    final bool selected = policy.preferredProviderId == p.id;
    return _option(
      selected: selected,
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
              () => widget.api
                  .choose(preferredProviderId: p.id, allowFallback: policy.allowFallback)
                  .then((_) {}),
              DeliveryStrings.of(context).carrierWillCarry(p.name)),
    );
  }

  Widget _noFleetYet() {
    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              DeliveryStrings.of(context).ownDriversBlurb,
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() => widget.api.myFleet().then((_) {}), DeliveryStrings.of(context).yourFleetIsSetUp),
              icon: const Icon(Icons.add, size: 18),
              label: Text(DeliveryStrings.of(context).setUpMyOwnDrivers),
            ),
          ],
        ),
    );
  }

  /// The choice that decides what happens on a bad night.
  Widget _fallbackToggle(DeliveryPolicy policy) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        value: policy.allowFallback,
        // Meaningless while the platform is choosing: there is nothing to fall back from.
        onChanged: _busy || policy.platformDecides
            ? null
            : (bool value) => _run(
                () => widget.api
                    .choose(
                        preferredProviderId: policy.preferredProviderId, allowFallback: value)
                    .then((_) {}),
                value
                    ? DeliveryStrings.of(context).anotherCarrierMayStepIn
                    : DeliveryStrings.of(context).onlyYourChosenCarrier),
        activeThumbColor: DeliveryColors.brand,
        title: Text(DeliveryStrings.of(context).letSomeoneElseStepIn),
        subtitle: Text(
          policy.platformDecides
              ? DeliveryStrings.of(context).onlyAppliesOnceChosen
              : policy.allowFallback
            ? DeliveryStrings.of(context).fallbackOnBlurb
            : DeliveryStrings.of(context).fallbackOffBlurb,
          style: const TextStyle(fontSize: 12.5, height: 1.3),
        ),
      ),
    );
  }

  Widget _option({
    required bool selected,
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
            if (selected)
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
