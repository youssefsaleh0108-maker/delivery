import '../api/onboarding_api.dart';
import '../models/onboarding_models.dart';
import 'auth_service.dart';
import 'delivery_role.dart';

/// What somebody said they are, on the question the app asks before it opens the browser.
///
/// Sign in with Google creates an account the moment Google vouches for the person, and until now
/// the realm then made every one of them a customer. That is the wrong default for somebody who came
/// to ride or to sell, so the app asks first and this is the answer. It decides the role — the realm
/// no longer does.
enum AccountIntent {
  /// "I want to order."
  customer(DeliveryRole.customer),

  /// "I want to deliver."
  rider(DeliveryRole.delivery),

  /// "I want to sell."
  seller(DeliveryRole.merchant);

  const AccountIntent(this.role);

  /// The live role that answers this intent. Holding it is what "already a rider" means.
  final DeliveryRole role;

  /// The application a partner intent starts, or null for a customer, who is not reviewed.
  OnboardingKind? get applicationKind => switch (this) {
        AccountIntent.customer => null,
        AccountIntent.rider => OnboardingKind.rider,
        AccountIntent.seller => OnboardingKind.merchant,
      };
}

/// What a session that has just come back needs before a screen can be chosen for it.
enum BrokerStep {
  /// The account already holds the role asked for. Picking a role you have just signs you in.
  proceed,

  /// Asked to shop without the role: onboarding-service grants CUSTOMER, then the token refreshes.
  becomeCustomer,

  /// Asked to ride or sell without the role: the partner application, for this same account.
  apply,
}

/// Something worth saying once the session is adopted. The session is good either way.
enum BrokerNotice {
  /// The role asked for could not be added. The app's role question is the way back to it.
  roleNotAdded,

  /// They asked to ride or sell, but this account already has an application — shown instead of a
  /// second one, which the server would refuse anyway (one account carries one application).
  existingApplication,

  /// They asked to ride or sell, and this account's application of that kind has already been
  /// decided without the role being on the account now — approved and later suspended, declined,
  /// or approved with a setup that never finished. Nothing is resumed: the server grants nothing on
  /// a decided application, and saying "we've opened that" over a screen that opened nothing left
  /// people answering the same question in a loop with the reason never given.
  applicationClosed,

  /// They asked to ride or sell on an account that already trades as another partner kind and has
  /// no application to show — a seeded account, or a role given by hand. One account holds one
  /// partner role and the server refuses a second; walking them through the whole application
  /// first, to be refused at the end, would waste every answer they gave.
  alreadyPartner,
}

/// Where the Google round trip ended up. Every branch is something the app can say or show; none
/// of them is a blank screen.
sealed class BrokerOutcome {
  const BrokerOutcome();
}

/// Signed in, with any role change already in [session] — route it.
final class BrokerSignedIn extends BrokerOutcome {
  const BrokerSignedIn(this.session, {this.notice});

  final AuthSession session;
  final BrokerNotice? notice;
}

/// Signed in, and asked to ride or sell on an account with no application yet. The app shows the
/// partner application for this account; the role is granted when that is submitted.
final class BrokerNeedsApplication extends BrokerOutcome {
  const BrokerNeedsApplication(this.session, this.intent);

  final AuthSession session;
  final AccountIntent intent;
}

/// They backed out of the browser. Nothing changed anywhere.
final class BrokerCancelled extends BrokerOutcome {
  const BrokerCancelled();
}

/// Keycloak will not hand this sign-in to the provider — it is not registered, or not enabled yet.
/// Known before any browser opened, so the person never saw a login page they did not ask for.
final class BrokerUnavailable extends BrokerOutcome {
  const BrokerUnavailable();
}

/// The round trip itself failed. [error] is for the log, never for the screen.
final class BrokerFailed extends BrokerOutcome {
  const BrokerFailed(this.error);

  final Object error;
}

/// Sign in through a Keycloak broker (Google), then give the account the role that was asked for.
///
/// <p>Kept out of the screens and out of `main.dart` so the decision can be tested without a
/// browser: [decide] is a pure function of the answer and the token's roles, and [settle] talks only
/// to [AuthService] and [OnboardingApi], both of which a test can stand in for.
///
/// <p><strong>Every role change is followed by a refresh.</strong> Roles live in the access token,
/// and a grant made by onboarding-service lands in Keycloak, not in the token this app is holding.
/// Routing on the old token would put a brand new customer on the "choose how you use YouDrop"
/// screen they just answered.
///
/// <p><strong>This grants nothing by itself.</strong> Every change is a call to onboarding-service,
/// which acts on the caller's own token subject and applies the same gates the open application form
/// does. Nothing here could make somebody a rider the platform has not approved.
class BrokerSignIn {
  BrokerSignIn({
    required AuthService auth,
    required OnboardingApi onboarding,
    this.alias = AuthService.googleBroker,
  })  : _auth = auth,
        _onboarding = onboarding;

  final AuthService _auth;
  final OnboardingApi _onboarding;

  /// The Keycloak identity provider this signs in through.
  final String alias;

  /// The live roles of the three partner kinds. Holding any of them is "already a partner".
  static const Set<DeliveryRole> _partnerRoles = <DeliveryRole>{
    DeliveryRole.delivery,
    DeliveryRole.merchant,
    DeliveryRole.carrier,
  };

  /// Whether Keycloak will hand a sign-in to [alias] right now, asked without any browser.
  ///
  /// The same question [start] asks, exposed so the app can ask it BEFORE anybody is shown the
  /// customer / rider / seller sheet. Asked only after the answer, a disabled provider cost every
  /// person a question, a spinner of up to eight seconds, and then "not available". See
  /// [AuthService.brokerAvailable] for what true, false and null mean.
  Future<bool?> available() => _auth.brokerAvailable(alias);

  /// What the returned session needs, from the answer and the roles its token carries.
  ///
  /// Holding the role asked for wins outright — even a rider whose application is still pending
  /// holds DELIVERY beside APPLICANT, and their surface already knows how to say "pending".
  static BrokerStep decide(AccountIntent intent, Set<DeliveryRole> roles) {
    if (roles.contains(intent.role)) return BrokerStep.proceed;
    return intent == AccountIntent.customer ? BrokerStep.becomeCustomer : BrokerStep.apply;
  }

  /// The whole thing: is the provider there, the browser round trip, and then [settle].
  Future<BrokerOutcome> start(AccountIntent intent) async {
    // Asked before the browser opens. With the provider disabled Keycloak ignores the hint and
    // shows its own login page, which is exactly the page this flow exists to spare people.
    if (await _auth.brokerAvailable(alias) == false) {
      return const BrokerUnavailable();
    }

    final AuthSession? session;
    try {
      session = await _auth.signInWithBroker(alias);
    } catch (error) {
      return BrokerFailed(error);
    }
    if (session == null) return const BrokerCancelled();
    return settle(session, intent);
  }

  /// Gives an already signed-in [session] the role [intent] asks for, or says what is needed.
  ///
  /// Also the entry point for an account that signed in earlier and holds no role at all — the
  /// role question asked again, with no browser in between.
  Future<BrokerOutcome> settle(AuthSession session, AccountIntent intent) async {
    try {
      switch (decide(intent, session.roles)) {
        case BrokerStep.proceed:
          return BrokerSignedIn(session);
        case BrokerStep.becomeCustomer:
          return await _becomeCustomer(session);
        case BrokerStep.apply:
          return await _apply(session, intent);
      }
    } catch (_) {
      // Anything unforeseen still ends signed in, with a sentence, on a screen that can ask again.
      return BrokerSignedIn(session, notice: BrokerNotice.roleNotAdded);
    }
  }

  Future<BrokerOutcome> _becomeCustomer(AuthSession session) async {
    try {
      await _onboarding.becomeCustomer();
    } catch (_) {
      // Nothing changed server-side, so the session in hand is still the true one.
      return BrokerSignedIn(session, notice: BrokerNotice.roleNotAdded);
    }
    final AuthSession fresh = await _auth.refresh();
    return BrokerSignedIn(
      fresh,
      notice: fresh.hasRole(DeliveryRole.customer) ? null : BrokerNotice.roleNotAdded,
    );
  }

  /// Rider or seller, without the role in the token.
  ///
  /// Usually that means no application yet, and the app shows the form. The other case is an
  /// account that already applied: the same kind is resumed — the server re-asserts the applicant
  /// roles, which is how an attempt that lost Keycloak half way gets finished — and another kind is
  /// shown as it is rather than started twice.
  ///
  /// Two things are said rather than attempted, because the server would refuse or ignore them
  /// and the person deserves the reason up front: an account that already trades as another
  /// partner kind (the form would end in a refusal), and an application of this kind that has
  /// already been decided (resuming it grants nothing, so no role could arrive).
  Future<BrokerOutcome> _apply(AuthSession session, AccountIntent intent) async {
    final OnboardingApplication? existing = await _onboarding.mine();
    if (existing == null) {
      // decide() only sends here without intent.role, so any partner role held is another kind.
      if (_partnerRoles.any(session.hasRole)) {
        return BrokerSignedIn(session, notice: BrokerNotice.alreadyPartner);
      }
      return BrokerNeedsApplication(session, intent);
    }
    if (existing.kind != intent.applicationKind) {
      return BrokerSignedIn(session, notice: BrokerNotice.existingApplication);
    }
    if (existing.status.isDecided) {
      return BrokerSignedIn(session, notice: BrokerNotice.applicationClosed);
    }
    await _onboarding.applyForMyAccount(
      kind: existing.kind,
      // The receipt carries no contact name, and the server's resume ignores the answers anyway;
      // it still validates that one was sent.
      name: session.name ?? session.displayName,
      businessName: existing.businessName.isEmpty ? null : existing.businessName,
    );
    final AuthSession fresh = await _auth.refresh();
    // Undecided and resumed, so the roles should be there. If they are not, the grant failed
    // somewhere — which is "could not finish setting up", not "we opened your application".
    return BrokerSignedIn(
      fresh,
      notice: fresh.hasRole(intent.role) ? null : BrokerNotice.roleNotAdded,
    );
  }
}
