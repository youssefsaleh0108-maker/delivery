import 'package:delivery_l10n/delivery_l10n.dart';

import 'inventory_models.dart';
import 'order_models.dart';
import 'pos_models.dart';
import 'provider_models.dart';
import 'report_models.dart';
import 'staff_models.dart';
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
        // No translation exists for the wallet yet; the English fallback is honest until the
        // surface that offers it ships its key. It only appears in dev builds today.
        PaymentMethod.wallet => label,
      };

  /// The one-line explanation shown under the method at checkout.
  ///
  /// The card and wallet sentences here describe the *default* state — the surface that offers
  /// dev-provider test payments replaces them with its own "test payment" wording.
  String descriptionIn(DeliveryStrings t) => switch (this) {
        PaymentMethod.cash => t.payTheRiderWhenItArrives,
        PaymentMethod.card => t.cardNotAvailableYet,
        PaymentMethod.wallet => t.cardNotAvailableYet,
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

// ---------------------------------------------------------------------------- staff

extension StaffRoleLabel on StaffRole {
  String labelIn(DeliveryStrings t) => switch (this) {
        StaffRole.manager => t.staffRoleManager,
        StaffRole.cashier => t.staffRoleCashier,
        StaffRole.stockkeeper => t.staffRoleStockkeeper,
      };
}

extension StoreStaffAccessLabel on StoreStaffAccess {
  /// The owner has no role, so there is no enum to ask — this is the one place that fills the gap,
  /// for a sidebar footer or a card badge that must always name somebody's standing.
  String roleLabelIn(DeliveryStrings t) => role?.labelIn(t) ?? t.staffRoleOwner;
}

extension StorePermissionLabel on StorePermission {
  String labelIn(DeliveryStrings t) => switch (this) {
        StorePermission.posSales => t.staffPermPosSales,
        StorePermission.posRefundsVoids => t.staffPermPosRefundsVoids,
        StorePermission.modifyInventoryPricing => t.staffPermModifyInventoryPricing,
        StorePermission.manageOrders => t.staffPermManageOrders,
        StorePermission.viewReports => t.staffPermViewReports,
        StorePermission.accessSettings => t.staffPermAccessSettings,
        StorePermission.manageStaff => t.staffPermManageStaff,
      };

  /// The second line under each toggle. Both staff frames draw two lines per permission, and a
  /// toggle labelled only "Refunds and voids" does not tell a shopkeeper what they are handing
  /// over.
  String descriptionIn(DeliveryStrings t) => switch (this) {
        StorePermission.posSales => t.staffPermPosSalesDesc,
        StorePermission.posRefundsVoids => t.staffPermPosRefundsVoidsDesc,
        StorePermission.modifyInventoryPricing => t.staffPermModifyInventoryPricingDesc,
        StorePermission.manageOrders => t.staffPermManageOrdersDesc,
        StorePermission.viewReports => t.staffPermViewReportsDesc,
        StorePermission.accessSettings => t.staffPermAccessSettingsDesc,
        StorePermission.manageStaff => t.staffPermManageStaffDesc,
      };
}

extension StaffStatusLabel on StaffStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        StaffStatus.active => t.staffStatusActive,
        StaffStatus.inactive => t.staffStatusInactive,
      };
}

// ---------------------------------------------------------------------------- inventory

extension InventoryFilterLabel on InventoryFilter {
  String labelIn(DeliveryStrings t) => switch (this) {
        InventoryFilter.all => t.invFilterAll,
        InventoryFilter.lowStock => t.invFilterLowStock,
        InventoryFilter.outOfStock => t.invFilterOutOfStock,
        InventoryFilter.active => t.invFilterActive,
        InventoryFilter.hidden => t.invFilterHidden,
      };
}

extension StockSeverityLabel on StockSeverity {
  String labelIn(DeliveryStrings t) => switch (this) {
        StockSeverity.ok => t.invStatusOk,
        StockSeverity.warning => t.invStatusWarning,
        StockSeverity.critical => t.invStatusCritical,
        StockSeverity.out => t.invStatusOut,
      };
}

extension MovementKindLabel on MovementKind {
  String labelIn(DeliveryStrings t) => switch (this) {
        MovementKind.receipt => t.invKindReceipt,
        MovementKind.adjustment => t.invKindAdjustment,
        MovementKind.count => t.invKindCount,
        MovementKind.sale => t.invKindSale,
        MovementKind.returned => t.invKindReturn,
        MovementKind.orderReserve => t.invKindOrderReserve,
        MovementKind.orderRelease => t.invKindOrderRelease,
        MovementKind.orderFulfil => t.invKindOrderFulfil,
      };
}

extension AdjustmentReasonLabel on AdjustmentReason {
  String labelIn(DeliveryStrings t) => switch (this) {
        AdjustmentReason.received => t.invReasonReceived,
        AdjustmentReason.damaged => t.invReasonDamaged,
        AdjustmentReason.expired => t.invReasonExpired,
        AdjustmentReason.theft => t.invReasonTheft,
        AdjustmentReason.correction => t.invReasonCorrection,
        AdjustmentReason.other => t.invReasonOther,
      };
}

extension StockCountStatusLabel on StockCountStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        StockCountStatus.open => t.invCountStatusOpen,
        StockCountStatus.submitted => t.invCountStatusSubmitted,
        StockCountStatus.cancelled => t.invCountStatusCancelled,
      };
}

// ---------------------------------------------------------------------------- the till

extension PosSaleStatusLabel on PosSaleStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        PosSaleStatus.open => t.posStatusOpen,
        PosSaleStatus.completed => t.posStatusCompleted,
        PosSaleStatus.voided => t.posStatusVoided,
        PosSaleStatus.partiallyRefunded => t.posStatusPartiallyRefunded,
        PosSaleStatus.refunded => t.posStatusRefunded,
      };
}

extension PosSaleActionLabel on PosSaleAction {
  String labelIn(DeliveryStrings t) => switch (this) {
        PosSaleAction.complete => t.posActionComplete,
        PosSaleAction.voidSale => t.posActionVoid,
        PosSaleAction.refund => t.posActionRefund,
        PosSaleAction.reprint => t.posActionReprint,
      };
}

extension PosTenderMethodLabel on PosTenderMethod {
  String labelIn(DeliveryStrings t) => switch (this) {
        PosTenderMethod.cashUsd => t.posCashUsd,
        PosTenderMethod.cashLbp => t.posCashLbp,
        PosTenderMethod.card => t.posCard,
        PosTenderMethod.wallet => t.posWallet,
      };
}

extension ReceiptChannelLabel on ReceiptChannel {
  String labelIn(DeliveryStrings t) => switch (this) {
        ReceiptChannel.print_ => t.posReceiptPrint,
        ReceiptChannel.sms => t.posReceiptSms,
        ReceiptChannel.whatsapp => t.posReceiptWhatsapp,
        ReceiptChannel.email => t.posReceiptEmail,
        ReceiptChannel.none => t.posReceiptNone,
      };
}

// ---------------------------------------------------------------------------- reports

extension SaleSourceLabel on SaleSource {
  String labelIn(DeliveryStrings t) => switch (this) {
        SaleSource.delivery => t.repSourceDelivery,
        SaleSource.pos => t.repSourceWalkIn,
      };
}

extension SaleFactStatusLabel on SaleFactStatus {
  String labelIn(DeliveryStrings t) => switch (this) {
        SaleFactStatus.completed => t.repStatusCompleted,
        SaleFactStatus.partiallyRefunded => t.repStatusPartiallyRefunded,
        SaleFactStatus.refunded => t.repStatusRefunded,
        SaleFactStatus.voided => t.repStatusVoided,
      };
}
