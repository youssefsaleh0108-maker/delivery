import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/home_route.dart';

/// The role switch between shopping and running a shop, as [homeFor] decides it.
///
/// A customer who became a services provider holds CUSTOMER and MERCHANT — and APPLICANT beside them
/// while the application waits. Priority alone would send that account to the shop on every start and
/// never back. The profile menu's "Switch to your shop" and the shop's "Switch to shopping" set a
/// preference; these pin that it is honoured both ways, and that nobody else lands anywhere new.
void main() {
  const Set<DeliveryRole> provider = <DeliveryRole>{DeliveryRole.customer, DeliveryRole.merchant};
  const Set<DeliveryRole> waiting = <DeliveryRole>{
    DeliveryRole.customer,
    DeliveryRole.merchant,
    DeliveryRole.applicant,
  };

  test('a customer who runs a shop lands in the shop when nothing was asked', () {
    expect(homeFor(provider), HomeSurface.merchant);
  });

  test('"Switch to shopping" takes them to the customer home, and "Switch to your shop" back', () {
    expect(homeFor(provider, preferred: DeliveryRole.customer), HomeSurface.customer);
    expect(homeFor(provider, preferred: DeliveryRole.merchant), HomeSurface.merchant);
  });

  test('a customer whose services application is waiting keeps shopping, and can go to the shop', () {
    expect(homeFor(waiting, preferred: DeliveryRole.customer), HomeSurface.customer);
    // The pending shop shell, with its banner — not the status-only screen, which is for somebody
    // with no surface of their own.
    expect(homeFor(waiting, preferred: DeliveryRole.merchant), HomeSurface.merchant);
    expect(homeFor(waiting), HomeSurface.merchant);
  });

  test('a provider who holds no customer role is never sent to a customer home', () {
    expect(homeFor(<DeliveryRole>{DeliveryRole.merchant}, preferred: DeliveryRole.customer),
        HomeSurface.merchant);
  });

  test('a goods merchant and a waiting applicant with no surface land where they always did', () {
    expect(homeFor(<DeliveryRole>{DeliveryRole.merchant}), HomeSurface.merchant);
    expect(homeFor(<DeliveryRole>{DeliveryRole.merchant, DeliveryRole.applicant}),
        HomeSurface.merchant);
    expect(homeFor(<DeliveryRole>{DeliveryRole.applicant}, preferred: DeliveryRole.customer),
        HomeSurface.pendingApplication);
  });
}
