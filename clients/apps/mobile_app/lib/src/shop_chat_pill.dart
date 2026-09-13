import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show ShopThreadScreen;
import 'package:flutter/material.dart';

import 'store_page_screen.dart' show ShopChatActionBuilder;

/// What [ShopChatActionBuilder] draws in this app: the dekkane frame's "Chat with …" pill (Figma
/// 112:2041), opening the customer's conversation with that shop.
///
/// Built once by the customer shell, which holds the chat client and the socket, and handed down
/// through Home to the neighbourhood browse and every shop it opens. The pill asks the server for the
/// thread when tapped rather than when drawn: a shop page is opened far more often than a chat is,
/// and a thread that was never written in should not exist just because somebody browsed.
ShopChatActionBuilder shopChatActionFor({required ShopChatApi api, UserQueueSocket? socket}) {
  return (BuildContext context, StoreCard store) => ShopChatPill(
        shopName: store.name,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ShopThreadScreen(
            api: api,
            open: () => api.openWithStore(store.id),
            title: store.name,
            socket: socket,
          ),
        )),
      );
}

/// The green pill the frame floats above the basket bar. Green rather than brand on purpose: the
/// brand red on that screen already means "add to basket", and a chat is not a purchase.
class ShopChatPill extends StatelessWidget {
  const ShopChatPill({super.key, required this.shopName, required this.onPressed});

  final String shopName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ConstrainedBox(
      // A long shop name ellipsises inside the pill instead of pushing it off the screen.
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      child: Material(
        color: DeliveryAccent.positive.color,
        shape: const StadiumBorder(),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: DeliveryColors.white),
                const SizedBox(width: DeliverySpacing.sm),
                Flexible(
                  child: Text(
                    t.chatShopWith(shopName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
