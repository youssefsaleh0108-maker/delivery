import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';

/// A split share's method as a person reads it: "Whish Money", "Cash at Door", "With the order" —
/// never the wire name, which the screens used to print as it came ("Paid via HOST_ORDER").
String splitMethodLabel(DeliveryStrings t, String method) => switch (method) {
      'WHISH' => t.custWhishShort,
      'OMT' => t.custOmtShort,
      'BOB' => t.custBobShort,
      'CASH_AT_DOOR' || 'CASH_ON_DELIVERY' => t.custCashAtDoor,
      'HOST_ORDER' => t.splitWithTheOrder,
      _ => method,
    };

/// How a share travels, for the line under a name: a simulated wallet says it is one, a wallet a
/// real provider carried says it was paid, and a promise says how it will be paid. Null while
/// nobody has answered.
String? splitShareCaption(DeliveryStrings t, SplitShare share) {
  final String? method = share.method;
  if (method == null) return null;
  final String label = splitMethodLabel(t, method);
  if (share.simulated) return t.splitSimulatedPayment(label);
  const Set<String> wallets = <String>{'WHISH', 'OMT', 'BOB'};
  if (share.status == 'PAID' && wallets.contains(method)) return t.custPaidVia(label);
  return label;
}
