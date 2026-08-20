import 'package:delivery_l10n/delivery_l10n.dart';

import 'order_models.dart';
import 'provider_models.dart';
import 'store_models.dart';

/// Translated labels for the enums the apps put on screen.
///
/// Every one of these enums already carries a `label`, and every one of them was English. That is
/// invisible while the app is English and decisive the moment it is not: a status badge reading
/// "On the way" or a filter chip reading "Groceries" stays English no matter how thoroughly the
/// screen around it is translated, because the string is baked into the model rather than looked up.
///
/// Extensions rather than a field on the enum: an enum constant is built at compile time and a
/// translation is resolved at render time against the reader's locale, so the two cannot live in the
/// same place. The wire value stays on the enum, where it belongs — it is the part that must never
/// change with the language.
///
/// The existing `label` getters are deliberately left alone. They are the English fallback and are
/// still what the Backoffice uses, which is English by decision rather than by omission.
extension OrderStatusLabel on OrderStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        OrderStatus.placed => t.stepPlaced,
        OrderStatus.accepted => t.stepAccepted,
        OrderStatus.preparing => t.stepPreparing,
        OrderStatus.ready => t.statusReadyForPickup,
        OrderStatus.pickedUp => t.stepOnTheWay,
        OrderStatus.delivered => t.stepDelivered,
        OrderStatus.cancelled => t.statusCancelled,
      };
}

extension OrderActionLabel on OrderAction {
  String labelIn(DeliveryStrings t) => switch (this) {
        OrderAction.accept => t.actionAccept,
        OrderAction.prepare => t.actionPrepare,
        OrderAction.ready => t.actionMarkReady,
        OrderAction.claim => t.actionClaim,
        OrderAction.pickUp => t.actionPickedUp,
        OrderAction.deliver => t.actionDelivered,
        OrderAction.cancel => t.actionCancel,
      };
}

extension PaymentMethodLabel on PaymentMethod {
  String labelIn(DeliveryStrings t) => switch (this) {
        PaymentMethod.cash => t.cashOnDelivery,
        PaymentMethod.card => t.card,
      };

  /// The one-line explanation shown under the method at checkout.
  String descriptionIn(DeliveryStrings t) => switch (this) {
        PaymentMethod.cash => t.payTheRiderWhenItArrives,
        PaymentMethod.card => t.cardNotAvailableYet,
      };
}

extension PaymentStatusLabel on PaymentStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        PaymentStatus.due => t.paymentDue,
        PaymentStatus.authorizationPending => t.paymentAwaitingAuthorisation,
        PaymentStatus.authorized => t.paymentAuthorised,
        PaymentStatus.collected || PaymentStatus.captured => t.paymentPaid,
        PaymentStatus.refunded => t.paymentRefunded,
        PaymentStatus.failed => t.paymentFailed,
      };
}

extension StoreVerticalLabel on StoreVertical {
  String labelIn(DeliveryStrings t) => switch (this) {
        StoreVertical.restaurant => t.verticalRestaurants,
        StoreVertical.coffee => t.verticalCoffee,
        StoreVertical.grocery => t.verticalGroceries,
        StoreVertical.convenience => t.verticalConvenience,
        StoreVertical.pharmacy => t.verticalPharmacy,
        StoreVertical.electronics => t.verticalElectronics,
        StoreVertical.flowersGifts => t.verticalFlowersGifts,
      };
}

extension ProviderKindLabel on ProviderKind {
  String labelIn(DeliveryStrings t) => switch (this) {
        ProviderKind.platform => t.providerKindInHouse,
        ProviderKind.external => t.providerKindCompany,
        ProviderKind.merchant => t.providerKindOwnDrivers,
      };
}

extension StoreAvailabilityLabel on StoreAvailability {
  String labelIn(DeliveryStrings t) => switch (this) {
        StoreAvailability.open => t.statusOpen,
        StoreAvailability.busy => t.statusBusy,
        StoreAvailability.closingSoon => t.statusClosingSoon,
        StoreAvailability.closed => t.statusClosed,
      };
}
