import 'package:delivery_core/delivery_core.dart';

/// Which surface a signed-in session lands on.
enum HomeSurface {
  /// The account holds no role at all. Somebody who signed in with Google and has not yet said
  /// whether they are a customer, a rider or a seller — or who backed out of the application they
  /// started. They are asked, rather than dropped into a shop they have no role to use.
  chooseRole,

  /// Applied, waiting, and with no surface of their own to explore yet.
  pendingApplication,

  carrier,
  rider,
  merchant,
  customer,
}

/// The role branch, as a function of the roles in the token.
///
/// It lived inline in `main.dart`'s builder, which made it the one decision in the app nothing could
/// test. Pulling it out mattered the moment Google sign-in stopped making every new account a
/// customer: the old last line was "anything else is a customer", and an account holding NO role
/// fell straight through it into the customer shell, where every order and every payment would be
/// refused for want of the role the shell assumes. [HomeSurface.chooseRole] is that case, named.
///
/// [preferred] is the role the person just asked for on the Google question, honoured when the
/// account holds it. Without it, an account holding both DELIVERY and MERCHANT that picked "Seller"
/// would land in the rider queue, because the priority below puts riders first — the opposite of
/// what they had just said. It lasts for the session; a cold start routes on priority alone.
///
/// The pending check comes before the preference on purpose: somebody holding APPLICANT and no
/// explorable surface has nowhere else to go, whatever they asked for.
HomeSurface homeFor(Set<DeliveryRole> roles, {DeliveryRole? preferred}) {
  if (roles.isEmpty) return HomeSurface.chooseRole;

  // A pending partner gets their real surface, not a waiting room — see main.dart. Somebody holding
  // APPLICANT with no explorable surface lands on the status screen; a pending carrier is in that
  // case despite their role, because the carrier shell is drawn from a company that is only
  // registered at approval.
  final bool pending = roles.contains(DeliveryRole.applicant);
  if (pending &&
      !roles.contains(DeliveryRole.merchant) &&
      !roles.contains(DeliveryRole.delivery)) {
    return HomeSurface.pendingApplication;
  }

  if (preferred != null && roles.contains(preferred)) {
    switch (preferred) {
      case DeliveryRole.customer:
        return HomeSurface.customer;
      case DeliveryRole.delivery:
        return HomeSurface.rider;
      case DeliveryRole.merchant:
        return HomeSurface.merchant;
      default:
        break;
    }
  }

  // The carrier's company surface wins over the rider queue: an account holding both runs the
  // company, and the queue is their staff's job. Then the rider, whose flow has a time-critical
  // task attached; then the shop.
  if (roles.contains(DeliveryRole.carrier)) return HomeSurface.carrier;
  if (roles.contains(DeliveryRole.delivery)) return HomeSurface.rider;
  if (roles.contains(DeliveryRole.merchant)) return HomeSurface.merchant;

  // Everything else that holds SOME role — CUSTOMER, and the staff and back-office roles that have
  // no surface of their own in this app — shops, as it always has.
  return HomeSurface.customer;
}
