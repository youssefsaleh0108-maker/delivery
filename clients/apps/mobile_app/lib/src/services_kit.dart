import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'delivery_address.dart';
import 'service_order_files.dart';
import 'service_order_tracking_screen.dart';

/// What the Services tab's screens need, gathered once by the customer shell.
///
/// The tab is a chain of pushed screens — services home, a category or a search, a provider's page,
/// the order screen, then tracking — and every link needs most of the same clients. Threading a
/// dozen constructor arguments through each of them is how one link ends up without the chat client
/// and silently drops its button, so the shell builds this one value and every screen takes it.
///
/// The optional members are optional for the reason the shell's own are: tests. main.dart wires every
/// one of them.
@immutable
class ServicesKit {
  const ServicesKit({
    required this.storeApi,
    required this.orderApi,
    required this.zoneApi,
    required this.addresses,
    required this.connectivity,
    this.catalogApi,
    this.geocodingApi,
    this.files,
    this.pickFile = pickServiceFile,
    this.shopChatApi,
    this.chatSocket,
    this.trackingApi,
    this.trackingSocket,
    this.chatApi,
    this.openOrders,
  });

  final StoreApi storeApi;
  final OrderApi orderApi;

  /// The offer search. Null leaves a search with its providers only.
  final CatalogApi? catalogApi;

  /// For the address sheet a delivery opens.
  final DeliveryZoneApi zoneApi;
  final GeocodingApi? geocodingApi;

  /// The customer's delivery address, shared with Home and checkout: its pin decides what "near you"
  /// means, and a delivery goes to it.
  final DeliveryAddressStore addresses;

  /// Whether the platform answers. A service order is never queued offline, so while this is false
  /// the order screen offers no placement at all.
  final ValueListenable<bool> connectivity;

  /// Sends a customer's design file with an order, and reads a placed order's files back. Null only
  /// in tests that need none: an offer that needs a file is then not offered for ordering, because a
  /// picker that cannot send anything would be a dead control, and the placement it led to would be
  /// refused anyway.
  final ServiceOrderFiles? files;

  /// Opens the file picker. Replaced in tests, which have no platform picker.
  final ServiceFilePicker pickFile;

  /// The customer's conversations with shops, for "Chat with …" on tracking. Null draws no button.
  final ShopChatApi? shopChatApi;
  final UserQueueSocket? chatSocket;

  /// For the rider tracking panel of a service delivery that is out.
  final TrackingApi? trackingApi;
  final UserQueueSocket? trackingSocket;
  final ChatApi? chatApi;

  /// Takes the customer to the Orders tab from however deep in the Services chain they are: what the
  /// order screen offers when a send may have placed the order without its answer arriving. Null
  /// draws no such button.
  final VoidCallback? openOrders;

  /// The tracking screen for one order, wired with this kit's clients.
  Widget trackingScreen(String orderId, {DeliveryOrder? preview}) => ServiceOrderTrackingScreen(
        orderApi: orderApi,
        storeApi: storeApi,
        orderId: orderId,
        preview: preview,
        shopChatApi: shopChatApi,
        chatSocket: chatSocket,
        trackingApi: trackingApi,
        trackingSocket: trackingSocket,
        chatApi: chatApi,
        files: files,
      );
}
