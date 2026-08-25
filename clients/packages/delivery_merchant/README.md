# delivery_merchant

The seven merchant pages — dashboard, products, orders, WhatsApp, delivery, areas and shop —
shared by `delivery_portal` (Flutter Web) and `mobile_app` (Android).

A merchant can apply and be signed in from the phone, so the phone is often the only device a shop
has. Both clients therefore mount the same widgets rather than keeping a copy each.

## Using it

```dart
import 'package:delivery_merchant/delivery_merchant.dart';

ProductListScreen(api: catalogApi)
```

Every screen takes the API clients it needs and nothing else: no navigation, no `Scaffold` with a
rail or a bottom bar, no locale plumbing. The host app supplies all of that, which is what lets one
screen sit in a portal rail on desktop and in a phone's navigation without changing.

Labels come from `DeliveryStrings.of(context)` in `delivery_l10n`, so a host must install that
package's delegates before mounting anything from here.
