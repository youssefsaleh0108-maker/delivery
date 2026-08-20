// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class DeliveryStringsEn extends DeliveryStrings {
  DeliveryStringsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Delivery';

  @override
  String get navShops => 'Shops';

  @override
  String get navBasket => 'Basket';

  @override
  String get navOrders => 'Orders';

  @override
  String get navButler => 'Butler';

  @override
  String get alerts => 'Alerts';

  @override
  String get settings => 'Settings';

  @override
  String get signOut => 'Sign out';

  @override
  String get deliverTo => 'Deliver to';

  @override
  String get setDeliveryAddress => 'Set delivery address';

  @override
  String get address => 'Address';

  @override
  String get addressHint => '12 Test Street, Flat 4';

  @override
  String get labelOptional => 'Label (optional)';

  @override
  String get labelHint => 'Home, Work';

  @override
  String get riderNotesOptional => 'Notes for the rider (optional)';

  @override
  String get riderNotesHint => 'Buzzer 4, second floor';

  @override
  String get deliverHere => 'Deliver here';

  @override
  String get recent => 'Recent';

  @override
  String get whereShouldWeBring => 'Where should we bring your order?';

  @override
  String get forgetThisAddress => 'Forget this address';

  @override
  String get addressTooShort => 'A bit more detail so the rider can find you';

  @override
  String get searchShops => 'Search shops and cuisines';

  @override
  String get all => 'All';

  @override
  String get allStores => 'All stores';

  @override
  String get yourFavourites => 'Your favourites';

  @override
  String get starredShops => 'Starred shops';

  @override
  String get offersForYou => 'Offers for you';

  @override
  String shopsDelivering(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shops delivering to you',
      one: '1 shop delivering to you',
    );
    return '$_temp0';
  }

  @override
  String get noShopsMatch => 'No shops match';

  @override
  String get tryClearingAFilter => 'Try clearing a filter or two.';

  @override
  String get nothingDeliveringHere => 'Nothing is delivering here just yet.';

  @override
  String get couldNotLoadStorefront => 'Could not load the storefront';

  @override
  String get tryAgain => 'Try again';

  @override
  String get filterOffers => 'Offers';

  @override
  String get filterUnder30 => 'Under 30 min';

  @override
  String get filterFreeDelivery => 'Free delivery';

  @override
  String get filterHighlyRated => '4.5+';

  @override
  String get clear => 'Clear';

  @override
  String get statusOpen => 'Open';

  @override
  String get statusBusy => 'Busy';

  @override
  String get statusClosingSoon => 'Closing soon';

  @override
  String get statusClosed => 'Closed';

  @override
  String get ratingNew => 'New';

  @override
  String get freeDelivery => 'Free delivery';

  @override
  String deliveryFeeLabel(String amount) {
    return '$amount delivery';
  }

  @override
  String etaRange(int from, int to) {
    return '$from-$to min';
  }

  @override
  String get tabShop => 'Shop';

  @override
  String get tabAisles => 'Aisles';

  @override
  String get tabOffers => 'Offers';

  @override
  String get tabBuyAgain => 'Buy Again';

  @override
  String get everything => 'Everything';

  @override
  String itemCount(int count) {
    return '$count items';
  }

  @override
  String get add => 'Add';

  @override
  String get nothingOnShelves => 'Nothing on the shelves yet';

  @override
  String get nothingInAisle => 'Nothing in this aisle';

  @override
  String get noOffersHere => 'No offers running here right now';

  @override
  String get noHistoryHere => 'Nothing from this shop in your history yet';

  @override
  String get appliesEverywhere => 'Applies everywhere';

  @override
  String get required => 'Required';

  @override
  String get optional => 'Optional';

  @override
  String get soldOut => 'sold out';

  @override
  String addWithTotal(String total) {
    return 'Add · $total';
  }

  @override
  String get basket => 'Basket';

  @override
  String get basketEmpty => 'Your basket is empty';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get delivery => 'Delivery';

  @override
  String get total => 'Total';

  @override
  String get free => 'Free';

  @override
  String get checkout => 'Checkout';

  @override
  String checkoutWithTotal(String total) {
    return 'Checkout · $total';
  }

  @override
  String get minimumNotReached => 'Minimum not reached';

  @override
  String minimumExplanation(String minimum, String shortfall) {
    return 'This shop has a minimum of $minimum — add $shortfall more.';
  }

  @override
  String get viewBasket => 'View basket';

  @override
  String get startNewBasket => 'Start a new basket?';

  @override
  String basketFromAnotherShop(String shop) {
    return 'Your basket has items from $shop. We can only deliver from one shop at a time.';
  }

  @override
  String get keepIt => 'Keep it';

  @override
  String get startHere => 'Start here';

  @override
  String get payment => 'Payment';

  @override
  String get payWithCash => 'Cash on delivery';

  @override
  String get payWithCard => 'Card';

  @override
  String get paidWith => 'Paid with';

  @override
  String get orderDetails => 'Order Details';

  @override
  String get yourOrder => 'Your order';

  @override
  String get reorder => 'Reorder';

  @override
  String deliveredOn(String when) {
    return 'Delivered on: $when';
  }

  @override
  String placedOn(String when) {
    return 'Placed on: $when';
  }

  @override
  String get deliveryCharge => 'Delivery Charge';

  @override
  String get back => 'Back';

  @override
  String get couldNotLoadOrder => 'Could not load this order';

  @override
  String get noOrdersYet => 'No orders yet';

  @override
  String get tracking => 'Tracking';

  @override
  String get live => 'Live';

  @override
  String get stepPlaced => 'Placed';

  @override
  String get stepAccepted => 'Accepted';

  @override
  String get stepPreparing => 'Preparing';

  @override
  String get stepReady => 'Ready';

  @override
  String get stepOnTheWay => 'On the way';

  @override
  String get stepDelivered => 'Delivered';

  @override
  String get waitingForRider => 'Waiting for the rider\'s first location.';

  @override
  String get locationAfterPickup =>
      'The rider\'s location appears once your order is picked up.';

  @override
  String get fixes => 'Fixes';

  @override
  String get travelled => 'Travelled';

  @override
  String get lastSeen => 'Last seen';

  @override
  String get rateYourOrder => 'Rate your order';

  @override
  String get yourRating => 'Your rating';

  @override
  String get leaveAComment => 'Leave a comment (optional)';

  @override
  String get submitReview => 'Submit';

  @override
  String get reviews => 'Reviews';

  @override
  String get noReviewsYet => 'No reviews yet';

  @override
  String get butler => 'Butler';

  @override
  String get butlerTagline => 'Anything that fits on a bike';

  @override
  String get butlerBlurb =>
      'Tell us what you need and where from. A shopper buys it and brings it to you.';

  @override
  String get butlerPrompt =>
      'Need something that is not on here? We will buy it for you.';

  @override
  String get whatDoYouNeed => 'What do you need?';

  @override
  String get whereFromOptional => 'Where from? (optional)';

  @override
  String get budgetCapOptional => 'Budget cap (optional)';

  @override
  String get requestAButler => 'Request a Butler';

  @override
  String get notifications => 'Notifications';

  @override
  String get nothingYet => 'Nothing yet';

  @override
  String get orderUpdatesHere => 'Order updates will show up here.';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get splashTagline => 'Groceries, food and more — delivered.';

  @override
  String get signInFailed => 'We could not sign you in.';

  @override
  String get account => 'Account';

  @override
  String get navAccount => 'Account';

  @override
  String get signOutConfirm => 'You will need to sign in again to order.';

  @override
  String get profile => 'Profile';

  @override
  String get roles => 'Roles';

  @override
  String get selectRequiredOptions => 'Select required options';

  @override
  String orderPlacedToast(String id, String total) {
    return 'Order #$id placed · $total';
  }

  @override
  String get deliveryAddress => 'Delivery address';

  @override
  String get addressRequired => 'We need somewhere to deliver to';

  @override
  String get contactPhoneOptional => 'Contact phone (optional)';

  @override
  String get merchantNotesOptional => 'Notes for the merchant (optional)';

  @override
  String get couldNotLoadShop => 'Could not load this shop';

  @override
  String get couldNotLoadMore => 'Could not load more — try again';

  @override
  String chooseUpTo(int count, String group) {
    return 'Choose up to $count under $group';
  }

  @override
  String get cancelThisOrder => 'Cancel this order?';

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get cancel => 'Cancel';

  @override
  String get couldNotLoadOrders => 'Could not load your orders.';

  @override
  String get browseAndPlaceFirst =>
      'Browse the catalog and place your first one.';

  @override
  String get replaceYourBasket => 'Replace your basket?';

  @override
  String basketFromShopReplace(String shop) {
    return 'Your basket has items from $shop. Reordering will replace it.';
  }

  @override
  String get replace => 'Replace';

  @override
  String openStore(String store) {
    return 'Open $store';
  }

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get couldNotLoadNotifications => 'Could not load notifications';

  @override
  String get pullDownToTryAgain => 'Pull down to try again.';

  @override
  String get setAddressFirst => 'Set a delivery address first';

  @override
  String get whatAreWeMoving => 'What are we moving?';

  @override
  String get pickUpFrom => 'Pick up from';

  @override
  String get whoReceivesItOptional => 'Who receives it? (optional)';

  @override
  String get buyMeSomething => 'Buy me something';

  @override
  String get aShopperBuysIt => 'A shopper buys it';

  @override
  String get deliverYourStuff => 'Deliver your stuff';

  @override
  String get youAlreadyHaveIt => 'You already have it';

  @override
  String get yourErrands => 'Your errands';

  @override
  String get couldNotLoadErrands => 'Could not load your errands';

  @override
  String get noThanks => 'No thanks';

  @override
  String payAmount(String amount) {
    return 'Pay $amount';
  }

  @override
  String get trackIt => 'Track it';

  @override
  String get whatDidItCost => 'What did it cost?';

  @override
  String cappedAt(String amount) {
    return 'They capped it at $amount';
  }

  @override
  String get goodsTotal => 'Goods total';

  @override
  String get receiptNumberOptional => 'Receipt number (optional)';

  @override
  String get sendForApproval => 'Send for approval';

  @override
  String get noErrandsWaiting => 'No errands waiting.';

  @override
  String get nothingToClaim => 'Nothing waiting to be claimed.';

  @override
  String get claim => 'Claim';

  @override
  String get reportWhatItCost => 'Report what it cost';

  @override
  String get deliveries => 'Deliveries';

  @override
  String contactLabel(String phone) {
    return 'Contact: $phone';
  }

  @override
  String get couldNotUpdateFavourites => 'Could not update your favourites.';

  @override
  String get itemNoLongerAvailable =>
      'One of these items is no longer available.';

  @override
  String get checkDeliveryDetails => 'Please check the delivery details.';

  @override
  String get couldNotPlaceOrder =>
      'Could not place the order. Please try again.';

  @override
  String get placing => 'Placing…';

  @override
  String placeOrderWithTotal(String total) {
    return 'Place order · $total';
  }

  @override
  String get nothingStillAvailable =>
      'Nothing from this order is still available.';

  @override
  String addedToBasket(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count items to your basket',
      one: 'Added 1 item to your basket',
    );
    return '$_temp0';
  }

  @override
  String addedSomeMissing(int added, int missing) {
    return 'Added $added; $missing no longer available';
  }

  @override
  String get couldNotReorder => 'Could not reorder just now.';

  @override
  String get reorderWillReplace => 'Reordering will start a new one.';

  @override
  String setByStoreCharged(String store) {
    return 'Set by $store and charged on delivery.';
  }

  @override
  String get cancelBeforeAccepted =>
      'You can only cancel before the merchant accepts it. This cannot be undone.';

  @override
  String get cancelledByCustomer => 'Cancelled by customer';

  @override
  String get tooLateToCancel =>
      'Too late — the merchant has already started this order.';

  @override
  String get couldNotCancelOrder => 'Could not cancel the order.';

  @override
  String riderAt(String lat, String lng) {
    return 'Rider at $lat, $lng';
  }

  @override
  String get couldNotPriceCombination => 'Could not price that combination.';

  @override
  String optionSoldOut(String name) {
    return '$name — sold out';
  }

  @override
  String addToReachMinimum(String amount) {
    return 'Add $amount to reach the minimum';
  }

  @override
  String get removeFromFavourites => 'Remove from favourites';

  @override
  String get addToFavourites => 'Add to favourites';

  @override
  String minOrderLabel(String amount) {
    return 'Min $amount';
  }

  @override
  String closesAtLabel(String when) {
    return 'Closes $when';
  }

  @override
  String get noAislesYet => 'This shop has no aisles yet';

  @override
  String get signInToSeeHistory => 'Sign in to see what you ordered before';

  @override
  String tabAislesCount(int count) {
    return 'Aisles ($count)';
  }

  @override
  String tabOffersCount(int count) {
    return 'Offers ($count)';
  }

  @override
  String get basketFromAnotherShopSingle =>
      'We can only deliver from one shop at a time.';

  @override
  String get basketHasOtherShopItems =>
      'This basket already has items from another shop.';

  @override
  String distanceKm(String km) {
    return '$km km';
  }

  @override
  String distanceM(String m) {
    return '$m m';
  }

  @override
  String get justNow => 'just now';

  @override
  String secondsAgo(int count) {
    return '${count}s ago';
  }

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String lineQuantity(int qty, String name) {
    return '$qty × $name';
  }

  @override
  String lineQtyPrice(int qty, String price) {
    return '$qty × $price';
  }

  @override
  String orderRefWithAddress(String ref, String address) {
    return '#$ref · $address';
  }

  @override
  String get sentBuyConfirmation =>
      'Sent. A shopper will pick it up and tell you what it costs before you pay.';

  @override
  String get sentMoveConfirmation => 'Sent. A rider will collect it.';

  @override
  String get cannotRequestErrands => 'This account cannot request errands';

  @override
  String get couldNotSendRequest => 'Could not send that request';

  @override
  String get butlerMoveTagline => 'Send something across town';

  @override
  String get butlerMoveBlurb =>
      'Already have it? A rider collects it from one address and drops it at another. Nothing is bought.';

  @override
  String get buyHint => 'A phone charger, USB-C, and a bottle of still water';

  @override
  String get buyValidator =>
      'A bit more detail so the shopper knows what to buy';

  @override
  String get whereFromHint => 'Any pharmacy near Hamra';

  @override
  String get budgetValidator => 'A number, or leave it blank';

  @override
  String get moveHint => 'A4 envelope with documents, nothing fragile';

  @override
  String get moveValidator =>
      'A bit more detail so the rider knows what to expect';

  @override
  String get pickUpHint => '8 Clemenceau Street, reception desk';

  @override
  String get pickUpValidator => 'Where should the rider collect it?';

  @override
  String get receiverHint => 'Name and phone number';

  @override
  String get requestAPickup => 'Request a pickup';

  @override
  String errandFeeBuy(String fee) {
    return 'Errand fee $fee. The shopper tells you what the goods cost before you pay anything.';
  }

  @override
  String errandFeeMove(String fee) {
    return 'Errand fee $fee. Nothing is bought, so that is the whole price.';
  }

  @override
  String get dropOffAt => 'Drop off at';

  @override
  String get thatDidNotWork => 'That did not work';

  @override
  String aboveYourCap(String cap) {
    return 'That is above the $cap cap you set.';
  }

  @override
  String get declined => 'Declined';

  @override
  String get approvedOnItsWay => 'Approved — it is on its way';

  @override
  String get cancelled => 'Cancelled';

  @override
  String waitingForShopper(String fee) {
    return 'Waiting for someone to take it · fee $fee';
  }

  @override
  String get shopperIsOnIt =>
      'A shopper is on it. They will tell you what it costs.';

  @override
  String riderOnTheWayToCollect(String total) {
    return 'A rider is on the way to collect it · $total';
  }

  @override
  String goodsPlusFee(String goods, String fee, String total) {
    return 'Goods $goods + fee $fee = $total';
  }

  @override
  String agreedAt(String total) {
    return 'Agreed at $total';
  }

  @override
  String get youDeclinedThisPrice => 'You declined this price';

  @override
  String get nobodyPickedThisUp => 'Nobody picked this up';

  @override
  String get butlerStatusOpen => 'Open';

  @override
  String get butlerStatusClaimed => 'Claimed';

  @override
  String get butlerStatusYourCall => 'Your call';

  @override
  String get butlerStatusAgreed => 'Agreed';

  @override
  String get butlerStatusExpired => 'Expired';

  @override
  String get somebodyElseClaimed => 'Somebody else claimed that one';

  @override
  String get whatYouPaidBeforeFee => 'What you paid, before the errand fee';

  @override
  String get sentForApproval =>
      'Sent. They will approve the price before you deliver.';

  @override
  String cappedAtBudget(String amount) {
    return 'They capped it at $amount';
  }

  @override
  String get yours => 'Yours';

  @override
  String get buyAndBring => 'Buy and bring';

  @override
  String get collectAndDrop => 'Collect and drop';

  @override
  String get from => 'From';

  @override
  String get collectAndDropInstruction =>
      'Collect it and drop it off. It is in your Deliveries tab.';

  @override
  String get waitingOnApproval =>
      'Waiting on them to approve. Do not deliver until they do.';

  @override
  String get approvedDeliverIt =>
      'Approved. Deliver it from your Deliveries tab.';

  @override
  String headingWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String availableWithCount(int count) {
    return 'Available ($count)';
  }

  @override
  String mineWithCount(int count) {
    return 'Mine ($count)';
  }

  @override
  String get errands => 'Errands';

  @override
  String get nothingWaitingForPickup => 'Nothing waiting for pickup right now.';

  @override
  String get noActiveDeliveries => 'You have no active deliveries.';

  @override
  String get anotherRiderClaimedIt => 'Another rider claimed that one first.';

  @override
  String get orderAlreadyMovedOn => 'That order has already moved on.';

  @override
  String contactPhone(String phone) {
    return 'Contact: $phone';
  }

  @override
  String get statusReadyForPickup => 'Ready for pickup';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get actionAccept => 'Accept';

  @override
  String get actionPrepare => 'Start preparing';

  @override
  String get actionMarkReady => 'Mark ready';

  @override
  String get actionClaim => 'Claim';

  @override
  String get actionPickedUp => 'Picked up';

  @override
  String get actionDelivered => 'Delivered';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get verticalRestaurants => 'Restaurants';

  @override
  String get verticalCoffee => 'Coffee';

  @override
  String get verticalGroceries => 'Groceries';

  @override
  String get verticalConvenience => 'Convenience';

  @override
  String get verticalPharmacy => 'Pharmacy';

  @override
  String get verticalElectronics => 'Electronics';

  @override
  String get verticalFlowersGifts => 'Flowers & Gifts';

  @override
  String orderPlacedToastShort(String ref, String total) {
    return 'Order #$ref placed · $total';
  }

  @override
  String minimumExplanationFull(String minimum, String shortfall) {
    return 'This shop has a minimum of $minimum — add $shortfall more.';
  }

  @override
  String addToReachMinimumShort(String amount) {
    return 'Add $amount to reach the minimum';
  }

  @override
  String actionFailed(String action) {
    return 'Could not $action.';
  }

  @override
  String actionOnOrder(String action, String ref) {
    return '$action · #$ref';
  }

  @override
  String itemCountWithDot(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String riderAtShort(String lat, String lng) {
    return 'Rider at $lat, $lng';
  }

  @override
  String waitingOnApprovalOf(String total) {
    return 'Waiting on them to approve $total. Do not deliver until they do.';
  }

  @override
  String get aislesCount => 'Aisles';

  @override
  String get signInPrompt => 'Sign in to see what you ordered before';

  @override
  String get merchantPortal => 'Merchant Portal';

  @override
  String get navProducts => 'Products';

  @override
  String get navDelivery => 'Delivery';

  @override
  String get navMyShop => 'My Shop';

  @override
  String get manageYourCatalog => 'Manage your catalog';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get signIn => 'Sign in';

  @override
  String get notAMerchant => 'This account is not registered as a merchant.';

  @override
  String get signInAsSomeoneElse => 'Sign in as someone else';

  @override
  String get carrierNotAvailableToYou => 'That carrier is not available to you';

  @override
  String couldNotLoadCarriers(String error) {
    return 'Could not load carriers: $error';
  }

  @override
  String get whoCarriesYourOrders => 'Who carries your orders';

  @override
  String get whoCarriesBlurb =>
      'Who carries your orders. This applies from the moment an order is ready to collect — orders already on their way keep the carrier they went out with.';

  @override
  String get yourOwnDrivers => 'Your own drivers';

  @override
  String get fleetRidersBlurb =>
      'Riders are added to your fleet by the platform. A fleet with nobody in it cannot collect anything.';

  @override
  String get whenCarrierCannotTake => 'When your carrier cannot take an order';

  @override
  String get letThePlatformChoose => 'Let the platform choose';

  @override
  String get whoeverIsAvailable =>
      'Whoever is available and can take the job. This is the default.';

  @override
  String get thePlatformWillChoose => 'The platform will choose';

  @override
  String notTakingWorkNow(String kind) {
    return '$kind  ·  not taking work at the moment';
  }

  @override
  String carrierWillCarry(String name) {
    return '$name will carry your orders';
  }

  @override
  String get ownDriversBlurb =>
      'If you already have drivers, they can carry your orders and the platform will only step in when they are busy.';

  @override
  String get yourFleetIsSetUp => 'Your fleet is set up';

  @override
  String get setUpMyOwnDrivers => 'Set up my own drivers';

  @override
  String get anotherCarrierMayStepIn => 'Another carrier may step in';

  @override
  String get onlyYourChosenCarrier => 'Only your chosen carrier will be used';

  @override
  String get letSomeoneElseStepIn => 'Let someone else step in';

  @override
  String get onlyAppliesOnceChosen =>
      'Only applies once you have chosen a carrier.';

  @override
  String get fallbackOnBlurb =>
      'If your carrier cannot take an order, another one will. Orders go out late rather than not at all.';

  @override
  String get fallbackOffBlurb =>
      'Orders wait for your carrier. Nothing goes out with anybody else — and an order they cannot take stays on your counter.';

  @override
  String get cancelledByMerchant => 'Cancelled by merchant';

  @override
  String get orderAlreadyMovedRefreshing =>
      'That order has already moved on. Refreshing.';

  @override
  String get columnToAccept => 'To accept';

  @override
  String get columnPreparing => 'Preparing';

  @override
  String get columnAwaitingRider => 'Awaiting a rider';

  @override
  String get columnDelivered => 'Delivered';

  @override
  String get showCompleted => 'Show completed';

  @override
  String get refresh => 'Refresh';

  @override
  String updatesEvery(int seconds) {
    return 'Updates every ${seconds}s';
  }

  @override
  String get liveOrders => 'Live orders';

  @override
  String get couldNotLoadOrdersShort => 'Could not load orders.';

  @override
  String get noOrdersYetMerchant => 'No orders yet.';

  @override
  String get noOrdersNeedingAttention => 'No orders needing attention.';

  @override
  String get riderAssigned => 'rider assigned';

  @override
  String noteWithText(String note) {
    return 'Note: $note';
  }

  @override
  String get saved => 'Saved';

  @override
  String get couldNotSaveProduct => 'Could not save this product';

  @override
  String get images => 'Images';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String get newProduct => 'New product';

  @override
  String get editProduct => 'Edit product';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get priceLabel => 'Price';

  @override
  String get enterANumber => 'Enter a number';

  @override
  String get priceMustBePositive => 'Price must be greater than zero';

  @override
  String get categoryLabel => 'Category';

  @override
  String get uncategorised => 'Uncategorised';

  @override
  String get saving => 'Saving…';

  @override
  String get save => 'Save';

  @override
  String get saveProductFirst => 'Save the product first, then add photos.';

  @override
  String get needsAPhotoToPublish =>
      'A product needs at least one photo before it can be published.';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get remove => 'Remove';

  @override
  String get couldNotPublishProduct => 'Could not publish this product';

  @override
  String get archiveThisProduct => 'Archive this product?';

  @override
  String archiveConfirm(String name) {
    return '\"$name\" will be withdrawn from the catalog. Existing orders that reference it are unaffected.';
  }

  @override
  String get archive => 'Archive';

  @override
  String get myProducts => 'My products';

  @override
  String get onSale => 'On sale';

  @override
  String productsTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count total',
      one: '1 total',
    );
    return '$_temp0';
  }

  @override
  String get drafts => 'Drafts';

  @override
  String get noPhoto => 'No photo';

  @override
  String get archived => 'Archived';

  @override
  String get yourProducts => 'Your products';

  @override
  String get publish => 'Publish';

  @override
  String get edit => 'Edit';

  @override
  String get draft => 'Draft';

  @override
  String get moreActions => 'More actions';

  @override
  String get noProductsYet => 'No products yet';

  @override
  String get createYourFirstProduct =>
      'Create your first product, add a photo, then publish it.';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String detailWithRef(String detail, String ref) {
    return '$detail (ref: $ref)';
  }

  @override
  String thatDidNotWorkWith(String error) {
    return 'That did not work: $error';
  }

  @override
  String get shopSaved => 'Shop saved';

  @override
  String get couldNotLoadYourShop => 'Could not load your shop';

  @override
  String get noShopYet => 'No shop yet';

  @override
  String get shopCreatedAutomatically =>
      'Add your first product and a shop is created for you automatically.';

  @override
  String get howYourShopAppears => 'How your shop appears on the storefront';

  @override
  String get shopName => 'Shop name';

  @override
  String get tagline => 'Tagline';

  @override
  String get taglineHint => 'Charcoal grills and mezze, all day';

  @override
  String get tags => 'Tags';

  @override
  String get tagsHint => 'Lebanese, Grills, Mezze  (comma separated)';

  @override
  String get addressLabel => 'Address';

  @override
  String get pictures => 'Pictures';

  @override
  String get logoRecognisedBy =>
      'Your logo is what customers recognise you by in search results';

  @override
  String get logo => 'Logo';

  @override
  String get logoHint => 'Square works best. Shown on every store card.';

  @override
  String get cover => 'Cover';

  @override
  String get coverHint => 'Wide. Sits behind your shop header.';

  @override
  String get generatedTileBlurb =>
      'Until you upload one, customers see a generated tile with your initials — consistent and on-brand, but not yours.';

  @override
  String get whatCustomersAreCharged =>
      'What customers are charged and told to expect';

  @override
  String get deliveryFeeLabelMerchant => 'Delivery fee';

  @override
  String get minimumOrder => 'Minimum order';

  @override
  String get etaFromMin => 'ETA from (min)';

  @override
  String get etaToMin => 'ETA to (min)';

  @override
  String get serverAppliesTerms =>
      'Both are applied by the server when an order is placed — a basket under the minimum is refused, and the fee is added to the customer\'s total.';

  @override
  String get openingHours => 'Opening hours';

  @override
  String get openingHoursBlurb =>
      'Your shop shows as Open, Closing soon or Closed based on these';

  @override
  String get addASecondWindow => 'Add a second window';

  @override
  String get secondWindowBlurb =>
      'Add a second window for a day to split your hours — for example a morning service and an evening one, closed in between.';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get listedOnStorefront => 'Listed on the storefront';

  @override
  String get notListedYet => 'Not listed yet';

  @override
  String get markedBusy30 => 'Marked busy for 30 minutes';

  @override
  String get busy30m => 'Busy 30m';

  @override
  String get noLongerBusy => 'No longer marked busy';

  @override
  String get notBusy => 'Not busy';

  @override
  String get yourShopIsLive => 'Your shop is live';

  @override
  String get opens => 'Opens';

  @override
  String get closes => 'Closes';

  @override
  String get removeThisWindow => 'Remove this window';

  @override
  String get upload => 'Upload';

  @override
  String labelRemoved(String label) {
    return '$label removed';
  }

  @override
  String get pictureUpdated => 'Picture updated';

  @override
  String get requiredField => 'Required';

  @override
  String get aNumber => 'A number';

  @override
  String get cannotBeNegative => 'Cannot be negative';

  @override
  String get signInFailedShort => 'Sign-in failed';

  @override
  String get providerKindInHouse => 'In-house';

  @override
  String get providerKindCompany => 'Delivery company';

  @override
  String get providerKindOwnDrivers => 'Own drivers';

  @override
  String get carrierPortal => 'Carrier Portal';

  @override
  String get carrierPortalTagline =>
      'Your company, your fleet and how much work you are offered.';

  @override
  String get notACarrier =>
      'This account is not registered to a delivery company.';

  @override
  String get noCompanyYet => 'No company attached to this account yet';

  @override
  String get askThePlatformToAttachYou =>
      'Ask the platform to attach you to your delivery company.';

  @override
  String get howYouAreDoing => 'How you are doing';

  @override
  String get deliveryScore => 'Delivery score';

  @override
  String get tooEarlyToTell => 'too early to tell';

  @override
  String get ordersDelivered => 'Orders delivered';

  @override
  String get timeToClaim => 'Time to claim';

  @override
  String get timeOnTheRoad => 'Time on the road';

  @override
  String get scoreBlurb =>
      'This score decides how much work you are offered when a merchant lets the platform choose. Delivering what you take matters most; claiming promptly comes next.';

  @override
  String get scoreProvisionalBlurb =>
      'You are still being given work on the benefit of the doubt. The score becomes yours rather than an assumption once you have a few more orders behind you.';

  @override
  String get takingOrders => 'Taking orders';

  @override
  String get takingWork => 'Taking work';

  @override
  String get youAreTakingOrders => 'You are taking orders';

  @override
  String get youAreNotTakingOrders => 'You are not taking orders';

  @override
  String get pauseExplanation =>
      'Pausing stops new orders being sent to you. Anything already assigned to your riders is unaffected.';

  @override
  String get suspendedByPlatform =>
      'The platform has suspended your company. You cannot resume yourself — talk to the platform.';

  @override
  String get pauseNewOrders => 'Pause new orders';

  @override
  String get startTakingOrders => 'Start taking orders';

  @override
  String get pausedNoNewOrders => 'Paused. No new orders will be sent to you.';

  @override
  String get resumedTakingOrders => 'You are taking orders again.';

  @override
  String get yourFleet => 'Your fleet';

  @override
  String get noRidersBlurb =>
      'You have no riders. Your company looks available and can collect nothing, which is the most confusing way to be sent no work — ask the platform to add your riders.';

  @override
  String get ridersAddedByPlatform =>
      'Riders are added to your fleet by the platform.';

  @override
  String get gettingPaid => 'Getting paid';

  @override
  String get noPayoutAccount => 'No payout account on file';

  @override
  String get payoutNeedsAttentionBlurb =>
      'The bank has not confirmed this account. Payments to you may fail — the platform can re-check it.';

  @override
  String get area => 'Area';

  @override
  String get pickYourArea => 'Pick your area so we know who can reach you';

  @override
  String feeToArea(String area, String fee) {
    return 'Delivery to $area: $fee';
  }

  @override
  String doesNotDeliverToArea(String area) {
    return 'This shop does not deliver to $area';
  }

  @override
  String get deliveryAreas => 'Delivery areas';

  @override
  String get whereYouDeliver =>
      'Where you deliver, and what you charge to get there';

  @override
  String get flatFeeEverywhere => 'You charge one fee everywhere';

  @override
  String get flatFeeExplanation =>
      'Add an area below to charge by distance instead. Until you add one, every order costs your standard delivery fee and you deliver anywhere.';

  @override
  String get addAnArea => 'Add an area';

  @override
  String get feeToHere => 'Fee';

  @override
  String get minimumHere => 'Minimum';

  @override
  String get extraMinutes => 'Extra minutes';

  @override
  String get usesShopMinimum => 'uses your shop minimum';

  @override
  String get stopDelivering => 'Stop delivering here';

  @override
  String get areasYouServe => 'Areas you deliver to';

  @override
  String get onlyTheseAreas =>
      'You deliver only to the areas listed here. Orders from anywhere else are refused.';

  @override
  String get manageAreas => 'Delivery areas';

  @override
  String get manageAreasBlurb =>
      'The list customers pick from when they enter an address. Shops price their delivery per area.';

  @override
  String get newArea => 'New area';

  @override
  String get areaName => 'Area name';

  @override
  String get regionOptional => 'Region (optional)';

  @override
  String get sortOrder => 'Order in the list';

  @override
  String get retire => 'Retire';

  @override
  String get reinstate => 'Reinstate';

  @override
  String get retired => 'Retired';

  @override
  String get retiredExplanation =>
      'Retired areas leave the picker but keep working for addresses that already name them.';

  @override
  String get noAreasYet => 'No areas yet';

  @override
  String get noAreasBlurb =>
      'Until you add areas, every shop charges one delivery fee and delivers anywhere.';

  @override
  String get navWhatsApp => 'WhatsApp';

  @override
  String get whatsappInbox => 'WhatsApp inbox';

  @override
  String get whatsappInboxBlurb =>
      'Customers who message your shop. Turn what they asked for into an order without leaving this screen.';

  @override
  String get noConversations => 'No messages yet';

  @override
  String get noConversationsBlurb =>
      'When a customer messages your connected number, the conversation appears here.';

  @override
  String get connectedNumbers => 'Connected numbers';

  @override
  String get connectNumber => 'Connect a number';

  @override
  String get numberId => 'WhatsApp number ID';

  @override
  String get numberLabel => 'Label';

  @override
  String get displayNumber => 'Phone number';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectNumberWarning =>
      'New messages to this number stop arriving. Your existing conversations are kept.';

  @override
  String get noNumbersYet => 'No number connected';

  @override
  String get noNumbersBlurb =>
      'Connect the WhatsApp number your customers already write to.';

  @override
  String get selectAConversation => 'Pick a conversation';

  @override
  String get selectAConversationBlurb =>
      'Choose someone on the left to read what they asked for.';

  @override
  String get showArchived => 'Show archived';

  @override
  String get showActive => 'Show active';

  @override
  String get typeAReply => 'Write a reply';

  @override
  String get sendReply => 'Send';

  @override
  String get replyNotSent => 'Saved, but it could not be sent';

  @override
  String get voiceNote => 'Voice note';

  @override
  String get photo => 'Photo';

  @override
  String get document => 'Document';

  @override
  String get locationPin => 'Location';

  @override
  String get unsupportedMessage => 'Unsupported message';

  @override
  String get startAnOrder => 'Start an order';

  @override
  String get theRequest => 'What they asked for';

  @override
  String get addItem => 'Add item';

  @override
  String get estimate => 'Estimate';

  @override
  String get estimateNote =>
      'An estimate at today’s prices. The final total is calculated when you confirm.';

  @override
  String get deliveryDetails => 'Delivery details';

  @override
  String get orderNotes => 'Notes';

  @override
  String get confirmOrder => 'Confirm order';

  @override
  String get confirmOrderWarning =>
      'This places a real order and books a rider.';

  @override
  String get discardRequest => 'Discard';

  @override
  String get orderPlaced => 'Order placed';

  @override
  String get draftDiscarded => 'Discarded';

  @override
  String get nothingToOrderYet => 'Nothing added yet';

  @override
  String get nothingToOrderYetBlurb =>
      'Add what the customer asked for from your own menu.';

  @override
  String get chooseOptions => 'Choose options';

  @override
  String get quantity => 'Quantity';

  @override
  String get addToOrder => 'Add to order';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get budgetExhausted =>
      'The budget is spent. No further waivers will be granted until revenue catches up.';

  @override
  String deliveryWasFree(String amount) {
    return 'Normally $amount — we covered it';
  }

  @override
  String get noCommissionOnThisOrder => 'No commission on this order';

  @override
  String get deliveryPaidByPlatform => 'Delivery paid by the platform';

  @override
  String get navCompany => 'Company';

  @override
  String get navJobs => 'Jobs';

  @override
  String get navEarnings => 'Earnings';

  @override
  String get jobsTitle => 'Your jobs';

  @override
  String get jobsBlurb =>
      'Everything your riders are carrying, and everything they have delivered.';

  @override
  String get noJobsYet => 'No jobs yet';

  @override
  String get noJobsBlurb => 'Orders assigned to your company will appear here.';

  @override
  String get earningsTitle => 'Earnings';

  @override
  String get earned => 'Earned';

  @override
  String get expected => 'Expected';

  @override
  String get jobsDelivered => 'Delivered';

  @override
  String get jobsInFlight => 'In flight';

  @override
  String get savedByOffers => 'Saved by offers';

  @override
  String earningsWindowNote(int days, String cut) {
    return 'Over the last $days days, after the platform\'s $cut% share of each delivery fee.';
  }

  @override
  String get savedByOffersNote =>
      'The platform waived its share on some of your deliveries, so you kept the whole fee.';

  @override
  String get expectedNote =>
      'What the work in flight is worth if it all completes. Not yet owed.';

  @override
  String get yourFeeOnThis => 'Your fee';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get howTradeIsGoing => 'How trade is going';

  @override
  String get howWorkIsGoing => 'How the work is going';

  @override
  String get ordersToday => 'Orders today';

  @override
  String get salesToday => 'Sales today';

  @override
  String get jobsToday => 'Jobs today';

  @override
  String get earnedToday => 'Earned today';

  @override
  String upOnYesterday(int percent) {
    return '$percent% up on yesterday';
  }

  @override
  String downOnYesterday(int percent) {
    return '$percent% down on yesterday';
  }

  @override
  String get sameAsYesterday => 'Same as yesterday';

  @override
  String get noneYesterday => 'Nothing yesterday';

  @override
  String get nothingYetToday => 'Nothing yet today';

  @override
  String get needsYouNow => 'Needs you now';

  @override
  String get toAccept => 'To accept';

  @override
  String get preparingNow => 'Preparing';

  @override
  String get readyForPickup => 'Ready for pickup';

  @override
  String get outForDelivery => 'Out for delivery';

  @override
  String get allCaughtUp => 'Nothing waiting on you.';

  @override
  String lastDaysHeading(int days) {
    return 'Last $days days';
  }

  @override
  String get quietSoFar => 'No trade in this period yet.';

  @override
  String get noJobsSoFar => 'No jobs in this period yet.';

  @override
  String get barChartLegend =>
      'Solid is delivered; pale is placed but not delivered.';

  @override
  String get ordersInWindow => 'Orders';

  @override
  String get deliveredInWindow => 'Delivered';

  @override
  String get salesInWindow => 'Sales';

  @override
  String get feesInWindow => 'Platform fees';

  @override
  String feesInWindowNote(String cut) {
    return '$cut% of delivered sales.';
  }

  @override
  String get bestSellers => 'Best sellers';

  @override
  String get nothingSoldYet => 'Nothing has sold in this period yet.';

  @override
  String soldQty(int qty) {
    return '$qty sold';
  }

  @override
  String get savedForYou => 'Saved by offers';

  @override
  String get savedForYouNote =>
      'The platform waived its share on some of your orders.';

  @override
  String get navApplicants => 'Applicants';

  @override
  String waitingOnYou(int count) {
    return '$count waiting on you';
  }

  @override
  String get everyoneWhoApplied => 'Everyone who has applied to ride for you.';

  @override
  String get waitingOnly => 'Waiting only';

  @override
  String get everyone => 'Everyone';

  @override
  String get nobodyWaiting => 'Nobody is waiting on you.';

  @override
  String get nobodyHasApplied => 'Nobody has applied yet.';

  @override
  String get hiringAlsoCreatesTheirAccount =>
      'Adding them creates their account and puts them on your fleet, so they can be sent work straight away.';

  @override
  String get addToMyFleet => 'Add to my fleet';

  @override
  String get turnDown => 'Turn down';

  @override
  String turnDownName(String name) {
    return 'Turn down $name';
  }

  @override
  String get theyAreSentThisWordForWord =>
      'They are sent this word for word. Say what would have to change.';

  @override
  String riderAdded(String name) {
    return '$name is on your fleet. We have emailed them how to sign in.';
  }

  @override
  String applicantTurnedDown(String name) {
    return '$name has been told.';
  }

  @override
  String turnedDownBecause(String reason) {
    return 'Turned down: $reason';
  }

  @override
  String get onYourFleetNow => 'On your fleet. They can be sent work.';

  @override
  String get thatDidNotGoThrough => 'That did not go through. Try again.';

  @override
  String get wantToRideForACompany => 'Want to ride for a delivery company?';

  @override
  String get rideWithUs => 'Ride with us';

  @override
  String get whoWouldYouRideFor => 'Who would you ride for?';

  @override
  String get theCompanyDecidesNotUs =>
      'You are applying to the company, not to us. They read it and decide, and we let you know either way.';

  @override
  String get couldNotLoadCompanies => 'We could not load the companies.';

  @override
  String get nobodyIsHiringRightNow =>
      'No delivery companies are taking applications right now.';

  @override
  String get aboutYou => 'About you';

  @override
  String get yourName => 'Your name';

  @override
  String get anythingWeShouldKnowRider =>
      'Anything they should know? (optional)';

  @override
  String get yourEmail => 'Your email';

  @override
  String get weSendACodeToCheckItReachesYou =>
      'We send a six-digit code to check it reaches you. Everything after this goes there, including how to sign in.';

  @override
  String get yourPhoneOptional => 'Your phone (optional)';

  @override
  String get aNumberHelpsWhenAnOrderNeedsSorting =>
      'Useful when something about a delivery needs sorting out quickly. Skip it if you would rather not.';

  @override
  String get sendCode => 'Send code';

  @override
  String get sendAnother => 'Send another';

  @override
  String get theCodeWeSent => 'The code we sent';

  @override
  String get verify => 'Verify';

  @override
  String get skipThis => 'Skip this';

  @override
  String get continueLabel => 'Continue';

  @override
  String get sendApplication => 'Send application';

  @override
  String get applicationSent => 'Application sent';

  @override
  String companyWillBeInTouch(String company) {
    return '$company will read it and be in touch by email.';
  }

  @override
  String get keepThisReference => 'Keep this reference';

  @override
  String get done => 'Done';

  @override
  String get paymentMethod => 'Payment method';

  @override
  String get cashOnDelivery => 'Cash on delivery';

  @override
  String get card => 'Card';

  @override
  String get payTheRiderWhenItArrives =>
      'Pay the rider when your order arrives';

  @override
  String get cardNotAvailableYet => 'Not available yet';

  @override
  String get paymentDue => 'Due on delivery';

  @override
  String get paymentAwaitingAuthorisation => 'Awaiting authorisation';

  @override
  String get paymentAuthorised => 'Authorised';

  @override
  String get paymentPaid => 'Paid';

  @override
  String get paymentRefunded => 'Refunded';

  @override
  String get paymentFailed => 'Payment failed';

  @override
  String get chooseAnAddress => 'Choose an address';

  @override
  String get addANewAddress => 'Add a new address';

  @override
  String riderGreeting(String name) {
    return 'Hi, $name';
  }

  @override
  String get riderHeaderLine => 'Here is what is on the board right now.';

  @override
  String riderWaitingCount(int count) {
    return '$count waiting';
  }

  @override
  String riderOnTheWayCount(int count) {
    return '$count on the way';
  }

  @override
  String get newJobsAppearHere =>
      'New jobs land here as soon as a shop marks an order ready.';

  @override
  String get claimOneToSeeItHere =>
      'Claim one from Available and it will show up here.';

  @override
  String collectCash(String amount) {
    return 'Collect $amount cash';
  }

  @override
  String get alreadyPaid => 'Already paid';
}
