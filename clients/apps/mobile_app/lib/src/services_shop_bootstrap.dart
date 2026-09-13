import 'package:delivery_core/delivery_core.dart';

/// What opening a services provider's shop came to. See [ServicesShopBootstrap].
sealed class ServicesShopOutcome {
  const ServicesShopOutcome();
}

/// The account has its services shop: found, or opened just now.
final class ServicesShopReady extends ServicesShopOutcome {
  const ServicesShopReady(this.store, {required this.opened});

  final Store store;

  /// True when this run opened it.
  final bool opened;
}

/// Not a services provider — or nothing could be learned. The shell carries on exactly as it did
/// before services existed, standing in [storeId] (null when there is no shop).
final class NotServicesProvider extends ServicesShopOutcome {
  const NotServicesProvider(this.storeId);

  final String? storeId;
}

/// Applied to offer services and not approved yet. Nothing is opened until a reviewer or
/// auto-approval says yes; the shell stands in [storeId] as before.
final class ServicesApplicationPending extends ServicesShopOutcome {
  const ServicesApplicationPending(this.storeId);

  final String? storeId;
}

/// An approved provider whose shop could not be opened. Nothing a merchant can do works without the
/// shop, so the shell says so and offers a retry rather than showing screens that would all fail.
final class ServicesShopFailed extends ServicesShopOutcome {
  const ServicesShopFailed(this.error);

  final Object error;
}

/// Opens an approved services provider's shop on their first entry, before anything else.
///
/// A provider is a merchant whose application said SERVICES (docs/figma-services-designs.md, slice
/// 3). Approval opens nothing — the server creates no shop for a merchant — and a first product would
/// otherwise have provisioned a restaurant, which the server now refuses for a services applicant.
/// So the app opens the shop itself, from the application: its business name, its category, and its
/// area as the shop's neighbourhood (`POST /api/stores`).
///
/// Safe on every entry. A services shop that exists is simply found; it is a SERVICES shop that is
/// looked for rather than any shop, so a provider who set up a goods shop by hand while waiting still
/// gets theirs; and the server hands back the existing services shop when two runs race, so it is
/// never opened twice.
///
/// The cost to everybody else is one read of their own application per entry, for a merchant with no
/// services shop. Any read that fails means "nothing learned", never "not a provider, open nothing
/// for good": the shell carries on as before and the next entry asks again. Only a failure to open a
/// shop the application clearly describes is reported, because only then is the shell unusable.
class ServicesShopBootstrap {
  ServicesShopBootstrap({required StoreApi stores, required OnboardingApi onboarding})
      : _stores = stores,
        _onboarding = onboarding;

  final StoreApi _stores;
  final OnboardingApi _onboarding;

  /// The server's limits on a shop's name and neighbourhood (`StoreRequest`). An application's
  /// business name may be longer, and a shop that can never be opened is worse than a trimmed name.
  static const int _maxName = 160;
  static const int _maxNeighborhood = 80;

  /// [onOpening] is called just before the shop is opened — the one step worth a screen of its own.
  Future<ServicesShopOutcome> run({void Function()? onOpening}) async {
    final List<Store> owned;
    try {
      owned = (await _stores.mine(size: 20)).content;
    } catch (_) {
      return const NotServicesProvider(null);
    }
    for (final Store store in owned) {
      if (store.vertical == StoreVertical.services) {
        return ServicesShopReady(store, opened: false);
      }
    }
    final String? standing = owned.isEmpty ? null : owned.first.id;

    final OnboardingApplication? application;
    try {
      application = await _onboarding.myApplication();
    } catch (_) {
      return NotServicesProvider(standing);
    }
    final ServiceApplicationAnswers? answers = application?.service;
    if (application == null || answers == null) return NotServicesProvider(standing);

    final bool approved = application.status == OnboardingStatus.approved ||
        application.status == OnboardingStatus.provisioned;
    if (!approved) return ServicesApplicationPending(standing);

    final ServiceCategory? category = answers.category;
    if (category == null) {
      // A category this build cannot name. Opening the shop under a guess would file it wrongly for
      // good — a shop never changes out of its vertical — so it is reported instead.
      return ServicesShopFailed(StateError(
          'The application names a service category this app does not know: '
          '${answers.categoryWire}'));
    }

    onOpening?.call();
    try {
      final Store store = await _stores.create(
        name: _clip(application.businessName.trim(), _maxName),
        vertical: StoreVertical.services,
        serviceCategory: category,
        neighborhood: answers.area == null ? null : _clip(answers.area!, _maxNeighborhood),
      );
      return ServicesShopReady(store, opened: true);
    } catch (error) {
      return ServicesShopFailed(error);
    }
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max).trim();
}
