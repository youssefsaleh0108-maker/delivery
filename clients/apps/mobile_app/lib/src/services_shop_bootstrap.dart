import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';

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
/// auto-approval says yes, and until then the account has no shop to stand in.
final class ServicesApplicationPending extends ServicesShopOutcome {
  const ServicesApplicationPending();
}

/// An approved provider whose shop could not be opened just now — a dropped connection, a server that
/// did not answer. Nothing a merchant can do works without the shop, so the shell says so and offers a
/// retry, which can succeed.
final class ServicesShopFailed extends ServicesShopOutcome {
  const ServicesShopFailed(this.error);

  final Object error;
}

/// An approved provider whose shop the server refused for good: the service category the application
/// names is not offered right now (`POST /api/stores` answered 422 — Product Service opens a services
/// shop only in an open category).
///
/// Its own outcome rather than a [ServicesShopFailed], because a retry cannot change it: only YouDrop
/// opening the category again, or support re-filing the provider, can. A "Try again" that fails the
/// same way every time is a button that cannot work, so the shell says what happened and that support
/// can help, and offers no retry.
final class ServicesCategoryNotOffered extends ServicesShopOutcome {
  const ServicesCategoryNotOffered();
}

/// Accounts already known not to be services providers, for as long as the app runs.
///
/// What an account applied to be does not change: an account holds one application, and Onboarding
/// refuses to turn a shop's application into a services one or the other way round. So once the
/// answer is "no application, or not one to offer services", reading it again on every entry to the
/// shop shell only costs a request. The app keeps one of these for the whole session, keyed by
/// account, so somebody else signing in on the same phone is asked afresh.
///
/// Only that answer is kept. A provider still waiting is asked again — approval is what the next entry
/// is looking for — and a read that failed was never an answer.
class ServicesProviderMemory {
  final Set<String> _notProviders = <String>{};

  bool isKnownNotProvider(String account) => _notProviders.contains(account);

  void rememberNotProvider(String account) => _notProviders.add(account);
}

/// Opens an approved services provider's shop on their first entry, before anything else.
///
/// A provider is a merchant whose application said SERVICES (docs/figma-services-designs.md, slice
/// 3). Approval opens nothing — the server creates no shop for a merchant — and a first product would
/// otherwise have provisioned a restaurant, which the server now refuses for a services applicant.
/// So the app opens the shop itself, from the application: its business name, its category, and its
/// area as the shop's neighbourhood (`POST /api/stores`).
///
/// Safe on every entry. A services shop that exists is simply found, and the server hands back the
/// existing services shop when two runs race, so it is never opened twice.
///
/// It costs everybody else nothing beyond the shop list the shell always read. A merchant who owns a
/// shop is a shop and is not asked about: the server opens no shop at all for a services applicant
/// until this bootstrap opens theirs, so a provider cannot own a goods shop to be mistaken for. An
/// account with no shop whose application is not a services one is remembered as such for the session
/// ([ServicesProviderMemory]). Any read that fails means "nothing learned", never "not a provider,
/// open nothing for good": the shell carries on as before and the next entry asks again. Only a
/// failure to open a shop the application clearly describes is reported, because only then is the
/// shell unusable — and a refusal no retry can change is reported as that ([ServicesCategoryNotOffered]).
class ServicesShopBootstrap {
  ServicesShopBootstrap({
    required StoreApi stores,
    required OnboardingApi onboarding,
    ServicesProviderMemory? memory,
    String? account,
  })  : _stores = stores,
        _onboarding = onboarding,
        _memory = memory,
        _account = account;

  final StoreApi _stores;
  final OnboardingApi _onboarding;

  /// Where a "not a services provider" answer is kept between runs for [_account]. Null keeps nothing.
  final ServicesProviderMemory? _memory;

  /// The signed-in account the answer is about — the token's subject.
  final String? _account;

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
    if (owned.isNotEmpty) return NotServicesProvider(owned.first.id);

    final String? account = _account;
    final ServicesProviderMemory? memory = _memory;
    if (account != null && memory != null && memory.isKnownNotProvider(account)) {
      return const NotServicesProvider(null);
    }

    final OnboardingApplication? application;
    try {
      application = await _onboarding.myApplication();
    } catch (_) {
      return const NotServicesProvider(null);
    }
    final ServiceApplicationAnswers? answers = application?.service;
    if (application == null || answers == null) {
      if (account != null) memory?.rememberNotProvider(account);
      return const NotServicesProvider(null);
    }

    final bool approved = application.status == OnboardingStatus.approved ||
        application.status == OnboardingStatus.provisioned;
    if (!approved) return const ServicesApplicationPending();

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
    } on DioException catch (error) {
      // 422 is the server judging the request, not failing to answer it: the category is not open,
      // and asking again will be refused the same way until somebody changes that.
      if (error.response?.statusCode == 422) return const ServicesCategoryNotOffered();
      return ServicesShopFailed(error);
    } catch (error) {
      return ServicesShopFailed(error);
    }
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max).trim();
}
