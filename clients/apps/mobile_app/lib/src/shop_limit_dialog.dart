import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';

/// The one limit a basket still has — items from at most [Cart.maxShops] shops — explained at the
/// moment an add would break it: what did not happen, what to do about it, and the way to the
/// basket, where the customer chooses which shop to check out or remove. True when they asked for
/// the basket; nothing is ever thrown out of it on their behalf.
///
/// One dialog for every considered add that can meet the limit — a shop page's Add, and Reorder on a
/// past order — so both say it in the same words. A Quick Add on the offline shelf answers in a
/// snackbar carrying the same way to the basket, as every Quick Add answers.
Future<bool> explainShopLimit(BuildContext context) async {
  final bool? openBasket = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final DeliveryStrings t = DeliveryStrings.of(context);
      return AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(t.multiCartShopLimitTitle(Cart.maxShops),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        content: Text(
          t.multiCartShopLimitBody,
          style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
              child: Text(t.close)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DeliveryColors.brand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
            ),
            child: Text(t.viewBasket),
          ),
        ],
      );
    },
  );
  return openBasket == true;
}
