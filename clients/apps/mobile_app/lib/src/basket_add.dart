import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_detail_screen.dart';
import 'product_options_sheet.dart';
import 'shop_limit_dialog.dart';

/// Putting a product in the basket from a list, the way a shop page does it: the shop limit first,
/// then the product's questions, then the basket.
///
/// Moved out of the shop page when the item search began listing products of many shops, so that
/// Add means one thing wherever a product is drawn:
/// * a product from a shop the basket does not have yet, when the basket already holds
///   [Cart.maxShops] shops, adds nothing and explains why, with the way to the basket;
/// * a product with no options goes straight in, at the price the server sent;
/// * a product with options opens its detail screen, which asks the catalogue for every price
///   ([showProductDetail]); nothing here adds option prices up.
///
/// Each product is filed under [from], the card of the shop it was found in, so the basket groups it
/// with that shop even when the product row names no store. One instance per screen: the options it
/// reads are cached for the screen's life, since a menu cannot change while the customer looks at it.
class BasketAdd {
  BasketAdd({required this.storeApi, required this.cart, required this.onOpenBasket});

  final StoreApi storeApi;
  final Cart cart;

  /// Where "View basket" in the shop-limit dialog goes: the customer shell's Basket tab.
  final VoidCallback onOpenBasket;

  final Map<String, List<OptionGroup>> _optionGroups = <String, List<OptionGroup>>{};

  /// The Add button: in the basket at once when the product asks nothing, its detail screen when it
  /// does.
  ///
  /// The options are fetched on demand rather than with the list: most products have none, and
  /// loading every product's option tree to draw a list would undo the paging.
  Future<void> add(BuildContext context, Product product, {required StoreCard from}) async {
    if (cart.exceedsShopLimit(product, from: from)) {
      await _explainShopLimit(context);
      return;
    }
    final List<OptionGroup> groups = await _groupsOf(product);
    if (groups.isEmpty) {
      cart.add(product, from: from);
      return;
    }
    if (!context.mounted) return;
    await _openDetail(context, product, groups, from);
  }

  /// A tap on the row rather than its Add button: the detail screen is a product's own destination,
  /// options or not.
  Future<void> open(BuildContext context, Product product, {required StoreCard from}) async {
    if (cart.exceedsShopLimit(product, from: from)) {
      await _explainShopLimit(context);
      return;
    }
    final List<OptionGroup> groups = await _groupsOf(product);
    if (!context.mounted) return;
    await _openDetail(context, product, groups, from);
  }

  Future<List<OptionGroup>> _groupsOf(Product product) async {
    final List<OptionGroup>? known = _optionGroups[product.id];
    if (known != null) return known;
    try {
      return _optionGroups[product.id] = await storeApi.productOptions(product.id);
    } catch (_) {
      // A menu that will not load must not block a product that probably has no options; the server
      // prices the line again at checkout either way.
      return _optionGroups[product.id] = const <OptionGroup>[];
    }
  }

  Future<void> _openDetail(BuildContext context, Product product, List<OptionGroup> groups,
      StoreCard from) async {
    final ConfiguredProduct? configured =
        await showProductDetail(context, api: storeApi, product: product, groups: groups);
    if (configured != null) {
      cart.addConfigured(configured, from: from);
    }
  }

  /// The one limit a basket still has, explained at the moment of the tap rather than as a 422 at
  /// checkout. Nothing is thrown out: the customer is shown the way to the basket, where they choose.
  Future<void> _explainShopLimit(BuildContext context) async {
    final bool openBasket = await explainShopLimit(context);
    if (openBasket && context.mounted) onOpenBasket();
  }
}
