// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class DeliveryStringsEn extends DeliveryStrings {
  DeliveryStringsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'YouDrop';

  @override
  String get navHome => 'Home';

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
  String couldNotOpenPicker(Object reason) {
    return 'Could not open the file picker: $reason';
  }

  @override
  String uploadFailedBecause(Object reason) {
    return 'Upload failed: $reason';
  }

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
  String get merchbAddPhotosNow =>
      'Add photos now — they upload when you save.';

  @override
  String get merchbPhotosAddedOnSave => 'These photos are added when you save.';

  @override
  String get merchbPending => 'Pending';

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
  String photoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

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
  String get createAccount => 'Create Account';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get signInWithAPasscode => 'Sign in with a passcode';

  @override
  String get couldNotSignInWithGoogle => 'Google sign-in did not complete.';

  @override
  String get enterYourPasscode => 'Enter your passcode';

  @override
  String get chooseAPasscode => 'Choose a passcode';

  @override
  String get confirmYourPasscode => 'Enter it again';

  @override
  String get sixDigitsYouWillUseToSignIn =>
      'Six digits you will use to sign in';

  @override
  String get passcodeMustBeSixDigits => 'Your passcode must be six digits.';

  @override
  String get passcodesDoNotMatch => 'Those did not match. Try again.';

  @override
  String get merchantHome => 'Your shop';

  @override
  String get orJoinUs => 'or';

  @override
  String get sellOrDeliverWithUs => 'Sell or deliver with us';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get usernameOrEmail => 'Username or email';

  @override
  String get password => 'Password';

  @override
  String get hide => 'Hide';

  @override
  String get show => 'Show';

  @override
  String get noAccountYet => 'New here?';

  @override
  String get couldNotReachTheServer =>
      'We could not reach the server. Check your connection and try again.';

  @override
  String get whatIsYourEmail => 'What\'s your email?';

  @override
  String get enterAValidEmail => 'Enter a valid email address.';

  @override
  String get lastNameOptional => 'Last name (optional)';

  @override
  String get choosePassword => 'Choose a password';

  @override
  String get atLeastEightCharacters => 'At least 8 characters';

  @override
  String get passwordTooShort => 'Use at least 8 characters.';

  @override
  String get deliveryPortal => 'Delivery Portal';

  @override
  String get backoffice => 'Backoffice';

  @override
  String get switchArea => 'Switch portal';

  @override
  String get navCategories => 'Categories';

  @override
  String get navCatalog => 'Catalog';

  @override
  String get navBanners => 'Banners';

  @override
  String get navOnboarding => 'Onboarding';

  @override
  String get navCarriers => 'Carriers';

  @override
  String get navAreas => 'Areas';

  @override
  String get navFinance => 'Finance';

  @override
  String get navOffers => 'Offers';

  @override
  String get navSettings => 'Settings';

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

  @override
  String get partnerChoiceTitle => 'Sell or deliver with us';

  @override
  String get partnerChoiceIntro =>
      'Tell us which one you are and we will take you through it.';

  @override
  String get applyAsMerchant => 'Sell on YouDrop';

  @override
  String get applyAsMerchantBlurb =>
      'You run a shop and want your products in the app.';

  @override
  String get applyAsRider => 'Deliver with YouDrop';

  @override
  String get applyAsRiderBlurb =>
      'You want to carry orders and get paid for each one.';

  @override
  String get whoWillYouRideFor => 'Who will you ride for?';

  @override
  String get rideForYouDrop => 'YouDrop';

  @override
  String get rideForYouDropBlurb =>
      'Join our own fleet. We review your application and we pay you.';

  @override
  String get rideForACompany => 'A delivery company';

  @override
  String get rideForACompanyBlurb =>
      'Apply to one of the companies below. They decide, not us.';

  @override
  String get yourBusiness => 'Your business';

  @override
  String get businessName => 'Business name';

  @override
  String get theNameCustomersWillSee =>
      'The name customers will see in the app.';

  @override
  String get yourNameAsOwner => 'Your name';

  @override
  String get anythingWeShouldKnowMerchant =>
      'Anything we should know? (optional)';

  @override
  String get weWillBeInTouch => 'We will read it and be in touch by email.';

  @override
  String get finishSettingUpInTheApp =>
      'Set your shop up now and look around. Publishing to the market unlocks once you are approved.';

  @override
  String get continueAsGuest => 'Continue without an account';

  @override
  String get guestApplicationExplainer =>
      'No account needed to apply. You choose a passcode at the end and can sign in straight away, then watch your application while we read it.';

  @override
  String codeSentTo(String destination) {
    return 'We sent a 6-digit code to $destination. It expires in 10 minutes and can be used once.';
  }

  @override
  String get enterTheCode => 'Enter the code';

  @override
  String get didntGetIt => 'Did not get it?';

  @override
  String get yourApplicationReference => 'Your application reference';

  @override
  String get referenceExplainer =>
      'Quote this if you contact us, and use it to check your application at any time. It is not a password and it is not needed to sign in.';

  @override
  String get unlockWithFingerprint => 'Unlock with fingerprint';

  @override
  String get useFingerprintNextTime => 'Use your fingerprint next time';

  @override
  String get fingerprintKeepsYourAccountClosed =>
      'Your session stays locked until you unlock it, so someone holding your phone cannot open your account.';

  @override
  String get fingerprintNotSetUp =>
      'No fingerprint or face is set up on this phone yet. Add one in Android Settings, under Biometrics, then come back.';

  @override
  String get couldNotVerifyYou =>
      'We could not verify you. Try again, or sign in with your passcode.';

  @override
  String get signInWithPasscodeInstead => 'Use my passcode instead';

  @override
  String get locked => 'Locked';

  @override
  String get notNow => 'Not now';

  @override
  String get turnOn => 'Turn on';

  @override
  String get biometricUnlock => 'Fingerprint unlock';

  @override
  String get chooseYourPasscode => 'Choose a passcode';

  @override
  String get passcodeLetsYouFollowIt =>
      'Six digits. You will use them to sign in and follow your application while we read it.';

  @override
  String get applicationPending => 'Application received';

  @override
  String get weAreReadingIt =>
      'We are reading your application. You will get an email as soon as there is a decision, and this screen keeps the status.';

  @override
  String companyIsReadingIt(String company) {
    return '$company is reading your application. You will get an email as soon as they decide.';
  }

  @override
  String get applicationStatus => 'Status';

  @override
  String get statusSubmitted => 'Waiting to be read';

  @override
  String get statusInReview => 'Being read now';

  @override
  String get statusApproved => 'Approved — setting up your account';

  @override
  String get statusRejected => 'Not accepted';

  @override
  String get statusProvisioned => 'Approved';

  @override
  String get statusFailed =>
      'Something went wrong setting you up. We are on it.';

  @override
  String get checkAgain => 'Check again';

  @override
  String get whatHappensNext => 'What happens next';

  @override
  String get nextStepsPending =>
      'Nothing to do for now. When you are approved this app becomes your shop or your job board — same sign-in, same passcode.';

  @override
  String get couldNotCreateSignIn =>
      'We could not set up your sign-in. Your application was still received.';

  @override
  String get pendingBannerMerchant =>
      'Your application is being reviewed. Set your shop up now — you can publish to the market once you are approved.';

  @override
  String get pendingBannerRider =>
      'Your application is being reviewed. Look around the board — you can take deliveries once you are approved.';

  @override
  String get notWhilePending =>
      'You can do this once your application is approved.';

  @override
  String get viewApplication => 'View application';

  @override
  String get accountReadySignInInstead =>
      'Your account is ready, but signing you in did not work. Close this and sign in with your email and the passcode you just chose.';

  @override
  String get dayByDay => 'Day by day';

  @override
  String get authTagline => 'Anything delivered, anywhere';

  @override
  String get authRoleCustomer => 'Customer';

  @override
  String get authRoleCustomerBlurb => 'Order and get deliveries';

  @override
  String get authRoleRider => 'Rider';

  @override
  String get authRoleRiderBlurb => 'Deliver and earn';

  @override
  String get authRoleMerchant => 'Merchant';

  @override
  String get authRoleMerchantBlurb => 'Sell and grow your business';

  @override
  String get authJoinYoudrop => 'Join YouDrop';

  @override
  String get authChooseHowToUse => 'Choose how you want to use YouDrop';

  @override
  String get authRolePopular => 'Popular';

  @override
  String get authRoleWantOrder => 'I want to Order';

  @override
  String get authRoleWantOrderBlurb =>
      'Get food, groceries & parcels delivered fast';

  @override
  String get authRoleWantDeliver => 'I want to Deliver';

  @override
  String get authRoleWantDeliverBlurb =>
      'Drive on your schedule, keep 100% of tips';

  @override
  String get authRoleWantSell => 'I want to Sell';

  @override
  String get authRoleWantSellBlurb => 'Grow your restaurant or store business';

  @override
  String get riderIntroHeader => 'Apply as Partner';

  @override
  String get riderIntroTitle => 'Earn on Your Schedule';

  @override
  String get riderIntroSubtitle =>
      'Join Lebanon\'s premier delivery fleet. Drive a scooter, motorcycle or car, and start earning today.';

  @override
  String get riderPerk1Title => 'Drive on Your Own Time';

  @override
  String get riderPerk1Body => 'No minimum hours, completely flexible shifts.';

  @override
  String get riderPerk2Title => 'Fast Payouts in Cash & USD';

  @override
  String get riderPerk2Body =>
      'Get paid daily or weekly directly in fresh cash.';

  @override
  String get riderPerk3Title => 'Rider Fuel Rewards';

  @override
  String get riderPerk3Body =>
      'Access discounted fuel partners across Lebanon.';

  @override
  String get applyToDeliver => 'Apply to Deliver';

  @override
  String get merchantIntroHeader => 'Grow with Us';

  @override
  String get merchantIntroHeaderLogin => 'Partner already?';

  @override
  String get merchantIntroTitle => 'Grow Your Business';

  @override
  String get merchantIntroSubtitle =>
      'Partner with YouDrop and offer fast delivery or takeout to residents across Beirut and Lebanon.';

  @override
  String get merchantBenefit1Title => 'Reach 50,000+ Customers';

  @override
  String get merchantBenefit1Body =>
      'Instant visibility to hungry customers in your radius.';

  @override
  String get merchantBenefit2Title => 'Zero Setup Fee & Easy Menus';

  @override
  String get merchantBenefit2Body =>
      'Our team builds and styles your online menu or store catalog.';

  @override
  String get merchantBenefit3Title => 'Direct Payouts & Dashboard';

  @override
  String get merchantBenefit3Body =>
      'Track sales, orders, and withdraw cash in real-time.';

  @override
  String get registerStoreNow => 'Register Store Now';

  @override
  String get authAlreadyHaveAnAccount => 'Already have an account?';

  @override
  String get authDontHaveAnAccount => 'Don\'t have an account?';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authSignInSubtitle => 'Please enter your credentials to log in.';

  @override
  String get authSignInAccountSubtitle => 'Sign in to your YouDrop account';

  @override
  String get authTaglineLebanon => 'Deliver everything in Lebanon';

  @override
  String get authLogIn => 'Log In';

  @override
  String get authForgotShort => 'Forgot?';

  @override
  String authSocialComingSoon(String provider) {
    return '$provider sign-in is coming soon.';
  }

  @override
  String authStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get authEmailOrPhone => 'Email or phone number';

  @override
  String get authEmailOrPhoneHint => 'e.g. name@domain.com or +961…';

  @override
  String get authPasscodeHint => 'Your six-digit passcode';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authUseTheKeypad => 'Use the keypad';

  @override
  String get authOrContinueWith => 'Or continue with';

  @override
  String get authComingSoon => 'Soon';

  @override
  String get authShowPassword => 'Show passcode';

  @override
  String get authHidePassword => 'Hide passcode';

  @override
  String get authDeleteDigit => 'Delete last digit';

  @override
  String get authCreateAccountSubtitle =>
      'Start getting anything delivered anywhere.';

  @override
  String get authFullName => 'Full name';

  @override
  String get authFullNameHint => 'e.g. Sarah Jenkins';

  @override
  String get authEmailAddress => 'Email address';

  @override
  String get authEmailHint => 'e.g. sarah.j@gmail.com';

  @override
  String get authPhoneNumber => 'Phone number';

  @override
  String get authPhoneHint => '70 123 456';

  @override
  String get authConfirmPassword => 'Confirm passcode';

  @override
  String get authPasscodeKeepGoing => 'Keep going';

  @override
  String get authPasscodeComplete => 'Complete';

  @override
  String get authAgreeToTerms => 'I agree to the terms and the privacy policy';

  @override
  String get authTermsPrefix => 'By signing up, you agree to our ';

  @override
  String get authTermsOfService => 'Terms of Service';

  @override
  String get authTermsAnd => ' and ';

  @override
  String get authPrivacyPolicy => 'Privacy Policy';

  @override
  String get authPleaseAcceptTheTerms => 'Please accept the terms to continue.';

  @override
  String get authVerifyYourEmail => 'Verify your email';

  @override
  String get authVerifyYourNumber => 'Verify your number';

  @override
  String get authStep => 'Step';

  @override
  String get authComplete => 'complete';

  @override
  String get authNext => 'Next';

  @override
  String get authGetStarted => 'Get started';

  @override
  String get authSubmitApplication => 'Submit application';

  @override
  String get authSendingApplication => 'Sending your application…';

  @override
  String get authCouldNotSendApplication =>
      'We could not send your application. Nothing was lost — try again.';

  @override
  String get authRiderIntroTitle => 'Join as a rider';

  @override
  String get authRiderIntroBlurb =>
      'Flexible hours, competitive pay, and easy navigation — start delivering with YouDrop in a few minutes.';

  @override
  String get authRiderBenefitHours => 'Flexible hours';

  @override
  String get authRiderBenefitPay => 'Competitive pay';

  @override
  String get authRiderBenefitNavigation => 'Easy navigation';

  @override
  String get authWhatYouNeedToSignUp => 'What you\'ll need to sign up';

  @override
  String get authNeedValidId => 'Valid ID';

  @override
  String get authNeedDriversLicence => 'Driving licence';

  @override
  String get authNeedVehicleDocuments => 'Vehicle documents';

  @override
  String get authMerchantSignUp => 'Merchant sign up';

  @override
  String get authMerchantIntroTitle => 'Register your business';

  @override
  String get authMerchantIntroBlurb =>
      'Reach more customers, manage products easily, and track performance in real time.';

  @override
  String get authWhatYouGet => 'What you\'ll get';

  @override
  String get authMerchantBenefitReach =>
      'Reach more customers through our delivery network';

  @override
  String get authMerchantBenefitManage =>
      'Easy product management and order fulfilment';

  @override
  String get authMerchantBenefitAnalytics =>
      'Real-time analytics to optimise your sales';

  @override
  String get authWhatYouNeed => 'What you\'ll need';

  @override
  String get authNeedBusinessLicence => 'Business licence';

  @override
  String get authNeedTaxCertificate => 'Tax certificate';

  @override
  String get authNeedBankDetails => 'Bank details';

  @override
  String get authPersonalInformation => 'Personal information';

  @override
  String get authPersonalInformationBlurb =>
      'Please fill in your primary details to establish your rider profile.';

  @override
  String get authDateOfBirth => 'Date of birth';

  @override
  String get authDateOfBirthHint => 'DD / MM / YYYY';

  @override
  String get authNationalId => 'National ID number';

  @override
  String get authNationalIdHint => 'As printed on your ID';

  @override
  String get authVehicleDetails => 'Vehicle details';

  @override
  String get authVehicleDetailsBlurb =>
      'Select your vehicle category and register its official details.';

  @override
  String get authVehicleType => 'Vehicle type';

  @override
  String get authVehicleMotorcycle => 'Motorcycle';

  @override
  String get authVehicleCar => 'Car';

  @override
  String get authVehicleBicycle => 'Bicycle';

  @override
  String get authVehicleVan => 'Van';

  @override
  String get authVehicleModel => 'Vehicle make / model';

  @override
  String get authVehicleModelHint => 'e.g. Yamaha TMAX / Toyota Yaris';

  @override
  String get authPlateNumber => 'Plate number';

  @override
  String get authPlateNumberHint => 'e.g. 1234 ABC';

  @override
  String get authVehicleYear => 'Vehicle year';

  @override
  String get authVehicleYearHint => 'e.g. 2024';

  @override
  String get authSelectDeliveryZone => 'Select delivery zone';

  @override
  String get authSelectDeliveryZoneBlurb =>
      'Which parts of the city do you prefer to deliver in?';

  @override
  String get authMapComingSoon => 'Coverage map coming soon';

  @override
  String get authPreferredArea => 'Preferred area';

  @override
  String get authPreferredAreaHint => 'e.g. Hamra, Achrafieh';

  @override
  String get authAvailableZones => 'Available zones';

  @override
  String get authZonesNoneToPickTitle => 'No zones to pick';

  @override
  String get authZonesNoneToPickBlurb =>
      'Nothing ties a rider to a fixed zone on this platform. The pin you placed and the area you typed above are what a reviewer goes by.';

  @override
  String get authBusinessInformation => 'Business information';

  @override
  String get authBusinessInformationBlurb =>
      'Tell us about your company and the contact person.';

  @override
  String get authBusinessShopName => 'Business / shop name';

  @override
  String get authBusinessShopNameHint => 'e.g. Rose Garden Pizzeria';

  @override
  String get authOwnerFullName => 'Owner full name';

  @override
  String get authOwnerFullNameHint => 'e.g. Jane Cooper';

  @override
  String get authBusinessType => 'Business type';

  @override
  String get authBusinessTypeHint => 'Choose one';

  @override
  String get authBusinessTypeRestaurant => 'Restaurant';

  @override
  String get authBusinessTypeGrocery => 'Grocery';

  @override
  String get authBusinessTypePharmacy => 'Pharmacy';

  @override
  String get authBusinessTypeBakery => 'Bakery';

  @override
  String get authBusinessTypeRetail => 'Retail';

  @override
  String get authBusinessTypeOther => 'Other';

  @override
  String get authContactEmail => 'Contact email address';

  @override
  String get authReviewAndSubmit => 'Review and submit';

  @override
  String get authReviewAndSubmitBlurb =>
      'Check what we are about to send. You can go back and change any of it.';

  @override
  String get authDocuments => 'Documents';

  @override
  String get authDocumentsBlurb =>
      'The papers we will need before you can start.';

  @override
  String get authDocumentsComingSoonTitle => 'Uploading opens shortly';

  @override
  String get authDocumentsComingSoonBlurb =>
      'You can finish your application without it — we will ask for the papers by email before you start.';

  @override
  String get authBankDetails => 'Bank details';

  @override
  String get authBankDetailsBlurb => 'Where your payouts will go.';

  @override
  String get authBankComingSoonTitle => 'Payout setup opens shortly';

  @override
  String get authBankComingSoonBlurb =>
      'We never take bank details before a decision. You will set payouts up once you are approved.';

  @override
  String get authApplicationSubmitted => 'Application submitted';

  @override
  String get authApplicationSubmittedBlurb =>
      'We have your application and our operations team is reading it now.';

  @override
  String get authWhatToExpectNext => 'What to expect next';

  @override
  String get authExpectVerification => 'We check your details (1–3 days)';

  @override
  String get authExpectBackgroundCheck => 'Background check';

  @override
  String get authExpectTrainingInvite => 'Invitation to rider training';

  @override
  String get authWeWillNotifyYou =>
      'We will let you know by email as soon as there is a decision.';

  @override
  String get authApplicationUnderReview => 'Application under review';

  @override
  String get authApplicationUnderReviewBlurb =>
      'Thank you. Your registration is in and our team is checking it over. This usually takes a day or two.';

  @override
  String get authExplorationModeActive => 'Exploration mode is on';

  @override
  String get authExplorationModeBlurb =>
      'While you wait you can set your products and menus up and look around. Nothing goes live until you are approved.';

  @override
  String get authApplicationChecklist => 'Application checklist';

  @override
  String get authChecklistAccountCreated => 'Account created';

  @override
  String get authChecklistDocuments => 'Documents uploaded';

  @override
  String get authChecklistAudit => 'Security and compliance check';

  @override
  String get authChecklistActivation => 'Shop activated and published';

  @override
  String get authExploreDashboard => 'Explore dashboard';

  @override
  String get custSeeAll => 'See All';

  @override
  String get custShowLess => 'Show Less';

  @override
  String get custAllCategories => 'All Categories';

  @override
  String get custFilters => 'Filters';

  @override
  String get custMyBasket => 'My Basket';

  @override
  String get custPromoCode => 'Promo Code';

  @override
  String get custApply => 'Apply';

  @override
  String get custOrderSummary => 'Order Summary';

  @override
  String get custDiscounts => 'Discounts';

  @override
  String get custTotalAmount => 'Total Amount';

  @override
  String get custProceedToCheckout => 'Proceed to Checkout';

  @override
  String get custAddToBasket => 'Add to Basket';

  @override
  String get custDeliveryTime => 'Delivery Time';

  @override
  String get custMinOrderStat => 'Min. Order';

  @override
  String custRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ratings',
      one: '1 Rating',
      zero: 'No ratings',
    );
    return '$_temp0';
  }

  @override
  String custShopsInCategory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Shops',
      one: '1 Shop',
      zero: 'No shops',
    );
    return '$_temp0';
  }

  @override
  String get custPeopleAlsoOrdered => 'People Also Ordered';

  @override
  String get custSoon => 'Soon';

  @override
  String get custIncreaseQuantity => 'Increase quantity';

  @override
  String get custDecreaseQuantity => 'Decrease quantity';

  @override
  String get custSearchInShop => 'Search this shop';

  @override
  String get custShopSearchHint => 'Search the menu';

  @override
  String get custButlerTitle => 'YouDrop Butler';

  @override
  String get custChooseWhatYouNeed => 'Choose what you need help with';

  @override
  String get custBuyAnything => 'Buy Anything';

  @override
  String get custBuyAnythingBlurb => 'We buy & deliver from anywhere';

  @override
  String get custSendAnything => 'Send Anything';

  @override
  String get custSendAnythingBlurb => 'Courier, pick up, or send items';

  @override
  String get custRecentTasks => 'Recent tasks';

  @override
  String get custSearchTasksHint => 'Search your errands';

  @override
  String get custNoTasksMatch => 'No errands match that search';

  @override
  String get custStatusPending => 'Pending';

  @override
  String get custWaitingOnYou => 'Waiting on you';

  @override
  String get custApplePay => 'Apple Pay';

  @override
  String get custOrderNotes => 'Order Notes';

  @override
  String get custOrderNotesHint =>
      'e.g. Leave package at the door, bell is not working...';

  @override
  String get custTotalPrice => 'Total Price';

  @override
  String get custPlaceOrder => 'Place Order';

  @override
  String get custOrderStatus => 'Order Status';

  @override
  String get custOrderRef => 'Order';

  @override
  String get custItemsOrdered => 'Items Ordered';

  @override
  String get custLiveMap => 'Live map';

  @override
  String get custAccountSettings => 'Account Settings';

  @override
  String custHiName(String name) {
    return 'Hi, $name';
  }

  @override
  String get custRewardsTitle => 'Rewards & Points';

  @override
  String get custTotalPoints => 'Total points';

  @override
  String custPtsThisMonth(int points) {
    return '+$points pts this month';
  }

  @override
  String custNextTierLabel(String tier) {
    return 'Next tier: $tier';
  }

  @override
  String custPtsToGo(int points) {
    return '$points pts to go';
  }

  @override
  String get custRewardsBlurb =>
      'Earn points on every delivered order. Redeem for vouchers and cashback.';

  @override
  String get custCurrentTierHeading => 'Current tier';

  @override
  String custCurrentTierLine(String tier) {
    return 'Current Tier: $tier';
  }

  @override
  String custTierEarnedLine(int points, int orders) {
    return 'Earned $points points · $orders orders completed';
  }

  @override
  String custNextTierLine(String tier) {
    return 'Next Tier: $tier';
  }

  @override
  String custNextTierBlurb(int points) {
    return 'Reach $points points to unlock better rewards.';
  }

  @override
  String get custTopTier => 'You are at the top tier.';

  @override
  String get custRewardCategories => 'Reward categories';

  @override
  String get custFreeDelivery => 'Free Delivery';

  @override
  String get custVouchersAvailable => 'Vouchers available';

  @override
  String get custCashback => 'Cashback';

  @override
  String get custEarnedLabel => 'Earned';

  @override
  String get custReferralBonus => 'Referral Bonus';

  @override
  String get custRecentActivity => 'Recent activity';

  @override
  String get custNoActivityYet =>
      'No points yet — they arrive with your first delivered order.';

  @override
  String custPointsOrderEntry(String points, String shortId) {
    return '$points pts · Order #$shortId';
  }

  @override
  String custPointsEntry(String points) {
    return '$points pts';
  }

  @override
  String get tierBronze => 'Bronze';

  @override
  String get tierSilver => 'Silver';

  @override
  String get tierGold => 'Gold';

  @override
  String get tierPlatinum => 'Platinum';

  @override
  String get custMyAccount => 'My account';

  @override
  String get custMyOrders => 'My Orders';

  @override
  String get custMyAddresses => 'My Addresses';

  @override
  String get custPaymentMethods => 'Payment Methods';

  @override
  String get custVouchersPromos => 'Vouchers & Promos';

  @override
  String get custPreferences => 'Preferences';

  @override
  String get custSupport => 'Support';

  @override
  String get custTermsPrivacy => 'Terms & Privacy';

  @override
  String get custAboutYoudrop => 'About YouDrop';

  @override
  String get custEditProfile => 'Edit profile';

  @override
  String get custLogOutAccount => 'Log Out Account';

  @override
  String get custAppLanguage => 'App Language';

  @override
  String get custOrderHistory => 'Order History';

  @override
  String get custHelpSupport => 'Help & Support';

  @override
  String get custLabelAddressAs => 'Label Address As:';

  @override
  String get custLabelHome => 'Home';

  @override
  String get custLabelWork => 'Work';

  @override
  String get custLabelOther => 'Other';

  @override
  String get merchTodaySummary => 'Today\'s Summary';

  @override
  String get merchPendingOrders => 'Pending Orders';

  @override
  String get merchNewOrders => 'New Orders';

  @override
  String get merchView => 'View';

  @override
  String get merchRecentOrders => 'Recent Orders';

  @override
  String get merchViewAll => 'View All';

  @override
  String get merchActive => 'Active';

  @override
  String get merchInactive => 'Inactive';

  @override
  String get merchPublishShop => 'Publish your shop';

  @override
  String get merchShopHidden => 'Your shop is hidden from the market.';

  @override
  String get merchbHideShop => 'Hide shop';

  @override
  String get merchOrderFlow => 'Order Flow';

  @override
  String get merchManagerView => 'Manager View';

  @override
  String get merchTabNew => 'New';

  @override
  String get merchTabCompleted => 'Completed';

  @override
  String get merchReject => 'Reject';

  @override
  String get merchFlowStatus => 'Flow Status';

  @override
  String get merchCustomerDetails => 'Customer Details';

  @override
  String get merchItemsBreakdown => 'Items Breakdown';

  @override
  String get merchSpecialInstructions => 'Special Instructions';

  @override
  String get merchGrandTotal => 'Grand Total';

  @override
  String get merchStepPickedUp => 'Picked Up';

  @override
  String get merchNothingInThisList => 'Nothing in this list.';

  @override
  String get merchOpenOrder => 'Open order';

  @override
  String get merchbMenuItems => 'Menu Items';

  @override
  String get merchbManageAvailability => 'Manage availability';

  @override
  String get merchbSearchMenuItems => 'Search products...';

  @override
  String get merchbAvailable => 'Available';

  @override
  String get merchbOffShelf => 'Off-shelf';

  @override
  String get merchbAddProduct => 'Add Product';

  @override
  String get merchbAvailability => 'Availability';

  @override
  String get merchbNoMatchingItems => 'No matching items';

  @override
  String get merchbAddNewProduct => 'Add New Product';

  @override
  String get merchbProductImage => 'Product Image';

  @override
  String get merchbUploadImageCta => 'Upload a product photo';

  @override
  String get merchbUploadHint => 'PNG, JPG up to 5MB';

  @override
  String get merchbVariantsOptions => 'Variants & Options';

  @override
  String get merchbAddOption => '+ Add option';

  @override
  String merchbChoicesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count choices',
      one: '1 choice',
    );
    return '$_temp0';
  }

  @override
  String get merchbNoOptionsYet => 'No options on this item yet';

  @override
  String get merchbOptionsReadOnly =>
      'Shown as customers see them. Editing options arrives soon.';

  @override
  String get merchbOptionsNeedSave =>
      'Save the item first, then add its options.';

  @override
  String get merchbOptionsLoadFailed =>
      'Could not load the current options. Nothing was changed.';

  @override
  String get merchbOptionsSaveFailed => 'Could not save the options.';

  @override
  String get merchbAddGroup => '+ Add group';

  @override
  String get merchbGroupName => 'Group name';

  @override
  String get merchbRemoveGroup => 'Remove group';

  @override
  String get merchbOptionName => 'Option';

  @override
  String get merchbRemoveOption => 'Remove option';

  @override
  String get merchbPriceDelta => 'Extra';

  @override
  String get merchbMinSelect => 'Choose at least';

  @override
  String get merchbMaxSelect => 'Choose at most';

  @override
  String get merchbRuleRequired => 'Required — the customer must choose.';

  @override
  String get merchbRuleOptional => 'Optional — the customer may skip this.';

  @override
  String get merchbUntitledGroup => 'this group';

  @override
  String get merchbGroupNeedsName => 'Every group needs a name.';

  @override
  String merchbGroupNeedsOption(String name) {
    return '$name needs at least one option.';
  }

  @override
  String merchbOptionNeedsName(String name) {
    return 'Every option in $name needs a name.';
  }

  @override
  String merchbMinAboveMax(String name) {
    return 'In $name, the minimum is above the maximum.';
  }

  @override
  String merchbMinAboveCount(String name) {
    return 'In $name, the minimum is more than the number of options.';
  }

  @override
  String merchbGroupOutOfRange(String name) {
    return 'In $name, the numbers must be between 0 and 50.';
  }

  @override
  String get merchbSaveMenuItem => 'Save Product';

  @override
  String get merchbSoon => 'Soon';

  @override
  String get merchbShopConfiguration => 'Shop Configuration';

  @override
  String get merchbShopStatus => 'Shop status';

  @override
  String get merchbBannerAndLogo => 'Shop Banner & Logo';

  @override
  String get merchbChangeCover => 'Change Cover';

  @override
  String get merchbChangeLogo => 'Change Logo';

  @override
  String get merchbShopAddress => 'Shop Address';

  @override
  String get merchbMapPreviewSoon => 'Map preview';

  @override
  String get merchbOperatingDetails => 'Operating Details';

  @override
  String get merchbSaveShopSettings => 'Save Shop Settings';

  @override
  String merchbHoursDaily(String from, String to) {
    return 'Daily: $from - $to';
  }

  @override
  String get merchbHoursCustom => 'Custom schedule';

  @override
  String get merchbHoursNone => 'No hours set';

  @override
  String get merchbEditHours => 'Edit opening hours';

  @override
  String get merchbDay => 'Day';

  @override
  String get merchbTimeHint => 'HH:mm';

  @override
  String get merchbDayMonday => 'Monday';

  @override
  String get merchbDayTuesday => 'Tuesday';

  @override
  String get merchbDayWednesday => 'Wednesday';

  @override
  String get merchbDayThursday => 'Thursday';

  @override
  String get merchbDayFriday => 'Friday';

  @override
  String get merchbDaySaturday => 'Saturday';

  @override
  String get merchbDaySunday => 'Sunday';

  @override
  String get merchbAccountSettings => 'Account Settings';

  @override
  String get merchbRoleOwner => 'Owner';

  @override
  String get merchbAppLanguage => 'App Language';

  @override
  String get merchbLangShortEn => 'EN';

  @override
  String get merchbLangShortAr => 'AR';

  @override
  String get merchbShopProfile => 'Shop Profile';

  @override
  String get merchbPaymentBankDetails => 'Payment & Bank details';

  @override
  String get merchbBankReadOnly =>
      'This is the account on file. It was set with your application, and the platform team is who changes it now — not this screen.';

  @override
  String get merchbBankNoneFiled =>
      'No bank details were filed with your application. The bank step closes once an application is decided, so the platform team is who adds them now.';

  @override
  String get merchbNotificationSettings => 'Notification Settings';

  @override
  String get merchbShopAnalytics => 'Shop Analytics';

  @override
  String get merchbLogOutAccount => 'Log Out Account';

  @override
  String get riderComingSoon => 'Coming soon';

  @override
  String get riderTabAvailable => 'Available';

  @override
  String get riderTabActive => 'Active';

  @override
  String get riderTabEarnings => 'Earnings';

  @override
  String get riderSegmentDeliveries => 'Deliveries';

  @override
  String get riderRegionZone => 'Region zone';

  @override
  String riderDeliveriesNearby(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deliveries nearby',
      one: '1 delivery nearby',
      zero: 'No deliveries nearby',
    );
    return '$_temp0';
  }

  @override
  String get riderOffersNearYou => 'Offers near you';

  @override
  String get riderAcceptDelivery => 'Accept delivery';

  @override
  String get riderMyActiveTasks => 'My active tasks';

  @override
  String riderActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active',
      one: '1 active',
      zero: 'None active',
    );
    return '$_temp0';
  }

  @override
  String riderOrderRef(String ref) {
    return 'Order #$ref';
  }

  @override
  String riderMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min ago',
      one: '1 min ago',
      zero: 'Just now',
    );
    return '$_temp0';
  }

  @override
  String riderHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hrs ago',
      one: '1 hr ago',
    );
    return '$_temp0';
  }

  @override
  String get riderNavigate => 'Navigate';

  @override
  String get riderViewDetails => 'View details';

  @override
  String get riderStartNavigation => 'Start navigation';

  @override
  String get riderYourPayout => 'Your payout';

  @override
  String get riderRouteTimeline => 'Route timeline';

  @override
  String get riderPickupAddress => 'Pickup address';

  @override
  String get riderDeliveryAddress => 'Delivery address';

  @override
  String get riderItemsToCollect => 'Items to collect';

  @override
  String riderItemLine(int qty, String name) {
    return '${qty}x $name';
  }

  @override
  String get riderNoItemsListed => 'This order has no itemised list.';

  @override
  String get riderDeliveryInstructions => 'Delivery instructions';

  @override
  String get riderMyEarnings => 'My earnings';

  @override
  String get riderPayout => 'Payout';

  @override
  String get riderPeriodToday => 'Today';

  @override
  String get riderPeriodWeekly => 'Weekly';

  @override
  String get riderTotalEarnings => 'Total earnings';

  @override
  String get riderEarningsDerived =>
      'Added up from the delivery fees on your own completed deliveries.';

  @override
  String get riderHoursOnline => 'Hours online';

  @override
  String get riderAcceptRate => 'Accept rate';

  @override
  String get riderRating => 'Rating';

  @override
  String get riderWeeklyOverview => 'Weekly overview';

  @override
  String get riderTodaysDeliveries => 'Today\'s deliveries';

  @override
  String get riderThisWeeksDeliveries => 'This week\'s deliveries';

  @override
  String get riderNothingDeliveredYet =>
      'Nothing delivered in this period yet.';

  @override
  String get riderCouldNotLoadEarnings => 'Could not load your earnings';

  @override
  String get riderDriverSettings => 'Driver settings';

  @override
  String get riderVehicleProfile => 'Vehicle profile';

  @override
  String get riderActiveDuty => 'Active duty (online)';

  @override
  String get riderAppLanguage => 'App language';

  @override
  String get riderDocuments => 'Documents & licences';

  @override
  String get riderBankDetails => 'Bank account details';

  @override
  String get riderNotificationPreferences => 'Notification preferences';

  @override
  String get riderHelpAndSupport => 'Help & live chat support';

  @override
  String get riderErrandTry => 'Try';

  @override
  String get riderErrandTo => 'To';

  @override
  String get riderErrandCap => 'Cap';

  @override
  String get etaWaitingFirstFix => 'Waiting for the rider\'s first GPS fix';

  @override
  String get etaPositionOutOfDate => 'The rider\'s position is out of date';

  @override
  String get etaNoMapPoint => 'No map point to measure to';

  @override
  String get etaRouteServiceDown => 'The route service did not answer';

  @override
  String get etaNothingOnItsWay => 'Nothing is on its way';

  @override
  String get etaUnavailable => 'No estimate available';

  @override
  String get etaHeadingToShop => 'Heading to the shop';

  @override
  String get etaOnTheWayToYou => 'On the way to you';

  @override
  String get etaStraightLineNote =>
      'Rough estimate — measured in a straight line, not by road';

  @override
  String get dutyOnDuty => 'On duty';

  @override
  String get dutyOffDuty => 'Off duty';

  @override
  String get presenceSignalLost => 'Signal lost';

  @override
  String get promoApplied => 'The code was applied';

  @override
  String get promoUnknownCode => 'That code was not recognised';

  @override
  String get promoNotActive => 'That code is no longer available';

  @override
  String get promoNotStarted => 'That code cannot be used yet';

  @override
  String get promoExpired => 'That code has expired';

  @override
  String get promoBelowMinimum =>
      'Your basket is below the minimum for that code';

  @override
  String get promoFullyRedeemed => 'That code has been fully redeemed';

  @override
  String get promoAlreadyUsed => 'You have already used that code';

  @override
  String get promoWorthNothing => 'That code is worth nothing on this order';

  @override
  String get promoDidNotApply => 'That code did not apply';

  @override
  String get paymentWallet => 'Wallet';

  @override
  String get paymentTestModeNote =>
      'Test payment — no real money moves in this build';

  @override
  String get cashOutRequested => 'Requested';

  @override
  String get cashOutPaid => 'Paid';

  @override
  String get cashOutRefused => 'Refused';

  @override
  String get paidByPlatform => 'Paid by the platform';

  @override
  String get paidByYourCompany => 'Paid by your company';

  @override
  String get paidElsewhere => 'Paid elsewhere';

  @override
  String get tipCashAtDoor => 'Cash at the door';

  @override
  String get tipOnline => 'Online';

  @override
  String get docNationalId => 'National ID';

  @override
  String get docDrivingLicence => 'Driving licence';

  @override
  String get docVehicleRegistration => 'Vehicle registration';

  @override
  String get docCommercialRegistration => 'Commercial registration';

  @override
  String get docWaitingReview => 'Waiting for review';

  @override
  String get docApproved => 'Approved';

  @override
  String get docRefused => 'Refused';

  @override
  String get payoutFormatChecked => 'Format checked';

  @override
  String get payoutVerified => 'Verified';

  @override
  String get payoutFailedVerification => 'Failed verification';

  @override
  String get notifCatOrderUpdates => 'Order updates';

  @override
  String get notifCatChat => 'Chat';

  @override
  String get notifCatPromotions => 'Promotions';

  @override
  String get notifCatAccount => 'Account and security';

  @override
  String get notifChannelPush => 'Push';

  @override
  String get notifChannelInApp => 'In-app';

  @override
  String get notifChannelEmail => 'Email';

  @override
  String get notifChannelSms => 'SMS';

  @override
  String get chatRoleCustomer => 'Customer';

  @override
  String get chatRoleRider => 'Rider';

  @override
  String get crossSellBoughtTogether => 'Often bought together';

  @override
  String get crossSellSameShelf => 'From the same shelf';

  @override
  String get crossSellYouMightAlsoLike => 'You might also like';

  @override
  String get ratingNewRider => 'New';

  @override
  String get custTestPayment => 'Test payment';

  @override
  String get custPaymentDeclined =>
      'The payment was declined and your order was not placed.';

  @override
  String get custPromoRemove => 'Remove the code';

  @override
  String get custPromoChecking => 'Checking the code…';

  @override
  String get promoCouldNotCheck => 'Could not check the code';

  @override
  String get etaMinShort => 'min';

  @override
  String get etaArriving => 'Expected arrival';

  @override
  String get etaRemaining => 'Remaining';

  @override
  String get custChatWithRider => 'Message the rider';

  @override
  String get chatTypeMessage => 'Type a message…';

  @override
  String get chatSend => 'Send';

  @override
  String get chatClosed => 'This conversation is closed';

  @override
  String get chatNoMessagesYet => 'No messages yet';

  @override
  String get chatCouldNotSend => 'Could not send your message';

  @override
  String get couldNotLoadChat => 'Could not load the conversation';

  @override
  String get custRateYourRider => 'Rate your rider';

  @override
  String get custHowWasDelivery => 'How was your delivery?';

  @override
  String get custAddCommentOptional => 'Add a comment (optional)';

  @override
  String get custSubmitRating => 'Submit rating';

  @override
  String get custThanksForRating => 'Thanks for rating your rider';

  @override
  String get custAlreadyRatedDelivery => 'You rated this delivery';

  @override
  String get custCouldNotSendRating => 'Could not send your rating';

  @override
  String ratingStars(Object n) {
    return '$n stars';
  }

  @override
  String get searchForAPlace => 'Search for a place…';

  @override
  String get noPlacesFound => 'No places found';

  @override
  String get couldNotSearchPlaces => 'Could not search just now';

  @override
  String get addressPinnedOnMap => 'Pinned on the map';

  @override
  String get notifPreferences => 'Notification preferences';

  @override
  String get notifPrefsBlurb => 'Choose how we reach you, topic by topic';

  @override
  String get notifAlwaysOn =>
      'Always on — account and security messages cannot be switched off';

  @override
  String get couldNotLoadPreferences => 'Could not load your preferences';

  @override
  String get couldNotSaveThatChange => 'Could not save that change';

  @override
  String crossSellTogetherCount(Object count) {
    return '$count× together';
  }

  @override
  String riderBalanceLine(Object balance, Object available) {
    return 'Balance $balance · available for cash-out $available';
  }

  @override
  String riderEarningsBreakdown(Object earnings, Object tips) {
    return '$earnings delivery pay · $tips tips';
  }

  @override
  String get riderCashOutTitle => 'Cash out';

  @override
  String get riderCashOutAvailable => 'Available to cash out';

  @override
  String riderCashOutMinimum(Object amount) {
    return 'Minimum $amount';
  }

  @override
  String get riderCashOutManualNote =>
      'Payouts are handed over by the platform team — nothing transfers automatically.';

  @override
  String get riderCashOutRequest => 'Request cash-out';

  @override
  String get riderCashOutAmountLabel => 'Amount';

  @override
  String get riderCashOutAlreadyOpen =>
      'A cash-out request is already on its way.';

  @override
  String get riderCashOutFailed => 'The cash-out could not be requested.';

  @override
  String riderCashOutOpenLine(Object amount) {
    return '$amount requested — waiting on the payout';
  }

  @override
  String get riderCashOutLastRefused => 'Your last cash-out was refused.';

  @override
  String get riderCashOutHistory => 'Recent requests';

  @override
  String riderTipLine(Object tip) {
    return '+$tip tip';
  }

  @override
  String riderReimbursedLine(Object amount) {
    return '+$amount reimbursed';
  }

  @override
  String riderLastSeen(Object when) {
    return 'Last seen $when';
  }

  @override
  String get riderDutyChangeFailed => 'Could not update your duty state.';

  @override
  String get riderDutyNotYetDeclared => 'You have not gone on duty yet.';

  @override
  String get riderEtaCaption => 'Live ETA';

  @override
  String riderEtaAway(Object distance) {
    return '$distance away';
  }

  @override
  String riderEtaArrivingAt(Object time) {
    return 'arriving about $time';
  }

  @override
  String riderKmUnit(Object km) {
    return '$km km';
  }

  @override
  String riderMetreUnit(Object m) {
    return '$m m';
  }

  @override
  String riderEtaComputedBy(Object provider) {
    return 'Estimated by $provider';
  }

  @override
  String get riderChatTitle => 'Customer chat';

  @override
  String get riderChatHint => 'Type a message…';

  @override
  String get riderChatSend => 'Send';

  @override
  String get riderChatClosed => 'This conversation has closed.';

  @override
  String get riderChatEmpty => 'No messages yet.';

  @override
  String get riderChatCouldNotLoad => 'Could not load the conversation';

  @override
  String get riderChatSendFailed => 'The message was not sent.';

  @override
  String get riderChatReconnecting => 'Reconnecting…';

  @override
  String get wizDocsIntro =>
      'Clear photos or PDFs. You can replace any document until a decision is made.';

  @override
  String get wizDocFileTypes => 'Photos and PDFs';

  @override
  String get wizDocAdd => 'Add';

  @override
  String get wizDocReplace => 'Replace';

  @override
  String get wizDocRemove => 'Remove';

  @override
  String get wizDocReadyToSend => 'Ready to send';

  @override
  String get wizDocNotAddedYet => 'Not added yet';

  @override
  String get wizDocSentOnSubmit =>
      'Your documents are sent when you submit the application.';

  @override
  String get wizDocTooLarge => 'That file is too large';

  @override
  String get wizDocUploadFailed => 'The upload did not go through';

  @override
  String get wizDocUploading => 'Uploading…';

  @override
  String get wizDocCouldNotLoad => 'Could not load your documents';

  @override
  String get wizDocsPendingTitle => 'Your documents';

  @override
  String get wizDocsPendingBlurb =>
      'A refused document can be replaced and will be reviewed again.';

  @override
  String get wizDocsNoneYet => 'Nothing uploaded yet';

  @override
  String get wizCouldNotSendDocuments =>
      'Your application is in, but a document did not go through.';

  @override
  String get wizPayoutAccountHolder => 'Account holder';

  @override
  String get wizPayoutAccountHolderHint =>
      'The name exactly as the bank has it';

  @override
  String get wizPayoutIban => 'IBAN';

  @override
  String get wizPayoutIbanHint => 'Starts with the country code, e.g. SA…';

  @override
  String get wizPayoutIbanInvalid =>
      'That IBAN does not check out — a digit is probably wrong or two are swapped';

  @override
  String get wizPayoutIbanFormat =>
      'An IBAN starts with two letters for the country and two check digits';

  @override
  String get wizPayoutIbanBounds => 'An IBAN is between 15 and 34 characters';

  @override
  String wizPayoutIbanLength(Object country, Object expected) {
    return 'An IBAN for $country is $expected characters';
  }

  @override
  String get wizPayoutCouldNotSave => 'The bank details could not be saved';

  @override
  String get wizPayoutCouldNotLoad => 'Could not load your bank details';

  @override
  String get wizPayoutSave => 'Save bank details';

  @override
  String get wizPayoutChange => 'Change';

  @override
  String get wizPayoutSentOnSubmit =>
      'Your bank details are sent when you submit the application.';

  @override
  String get wizCouldNotSendPayout =>
      'Your application is in, but the bank details did not go through.';

  @override
  String get merchPinShopLocation => 'Shop location';

  @override
  String get merchPinDropHint =>
      'Tap the map to put the pin on your shop, then save.';

  @override
  String get merchPinWhyItMatters =>
      'Customers see this pin, and delivery distance is measured from it.';

  @override
  String get merchPinNoneYet => 'No location pinned yet';

  @override
  String get merchPinSetIt => 'Set location';

  @override
  String get merchPinSaved => 'Shop location saved';

  @override
  String get merchPinCleared => 'Shop location removed';

  @override
  String get merchMapUnavailable => 'Map could not load';

  @override
  String merchUpOnPrevious(Object percent, Object days) {
    return '$percent% up on the $days days before';
  }

  @override
  String merchDownOnPrevious(Object percent, Object days) {
    return '$percent% down on the $days days before';
  }

  @override
  String merchSameAsPrevious(Object days) {
    return 'Same as the $days days before';
  }

  @override
  String merchNonePrevious(Object days) {
    return 'Nothing in the $days days before';
  }

  @override
  String get merchNothingEitherPeriod => 'Nothing in either period';

  @override
  String get merchAnalyticsBlurb =>
      'Every day in the window, split by how fast the customer asked for the delivery.';

  @override
  String get merchTierSplit => 'By delivery speed';

  @override
  String get merchOrderValue => 'Order value';

  @override
  String get merchOrderValueNote =>
      'What customers paid in total, delivery and any express premium included — not your payout.';

  @override
  String get deliveryTierStandard => 'Standard';

  @override
  String get deliveryTierExpress => 'Express';

  @override
  String get custPinYourDoor => 'Pin your door';

  @override
  String get custSetHere => 'Set here';

  @override
  String get locMyLocation => 'My location';

  @override
  String get locServicesOff => 'Location is turned off on this phone.';

  @override
  String get locTurnOn => 'Turn on';

  @override
  String get locPermissionNeeded =>
      'Allow location access to point the map at you.';

  @override
  String get locOpenSettings => 'Open settings';

  @override
  String get locNoFix => 'Couldn\'t get your location. Try again in the open.';

  @override
  String get custNamingThisPlace => 'Looking up this place…';

  @override
  String get custMapUnavailable =>
      'The map could not load. The address you type is what we will use.';

  @override
  String get custYourAddress => 'Your address';

  @override
  String get custTheRider => 'The rider';

  @override
  String get custDeliverySpeed => 'Delivery speed';

  @override
  String get custExpressSurchargeApplies => 'Surcharge applies';

  @override
  String get custExpressNote =>
      'Express costs extra. The platform sets the amount and your receipt shows it as its own line. A free-delivery offer does not cover it.';

  @override
  String get authResetYourPasscode => 'Reset your passcode';

  @override
  String get authChangeYourPasscode => 'Change your passcode';

  @override
  String get authResetAskForAddress =>
      'Tell us the email on your account. If it has one, a six-digit code goes to it.';

  @override
  String get authResetToYourAddress =>
      'A six-digit code goes to the email on your account.';

  @override
  String authResetCodeMaybeSent(Object destination) {
    return 'If $destination has an account, a 6-digit code is on its way. It expires in 10 minutes and can be used once.';
  }

  @override
  String get authSetNewPasscode => 'Set new passcode';

  @override
  String get authPasscodeChanged => 'Passcode changed';

  @override
  String get authPasscodeChangedSignIn =>
      'Sign in with your new six-digit passcode.';

  @override
  String get authPasscodeChangedSignedIn =>
      'Use your new six-digit passcode the next time you sign in.';

  @override
  String get custProfileFieldsFixed =>
      'Your name and email were set when the account was created and cannot be changed from the app yet.';

  @override
  String get custNoEmailOnAccount =>
      'This account has no email address on it, so there is nowhere to send a code.';

  @override
  String get custCouldNotOpenThat => 'Nothing on this phone could open that.';

  @override
  String get custHelpIntro =>
      'Answers to the things people ask most, and the ways to reach a person when the answer is not here.';

  @override
  String get custHelpTalkToUs => 'Talk to us';

  @override
  String get custChatOnWhatsApp => 'Chat on WhatsApp';

  @override
  String get custEmailSupport => 'Email support';

  @override
  String get custHelpNoChannelsYet =>
      'No support channel is set up in this build yet. Your orders still carry a chat with the rider once one is assigned.';

  @override
  String get custHelpOrdering => 'Ordering';

  @override
  String get custHelpDelivery => 'Delivery';

  @override
  String get custHelpPayments => 'Payments';

  @override
  String get custHelpAccount => 'Your account';

  @override
  String get custHelpApplying => 'Selling and riding';

  @override
  String get custFaqOneShopQ => 'Why can my basket only hold one shop?';

  @override
  String get custFaqOneShopA =>
      'One order goes to one shop and is carried by one rider. Two shops means two collections, two fees and two journeys, so the basket asks you to finish one before starting the other.';

  @override
  String get custFaqMinimumQ => 'What is a minimum order?';

  @override
  String get custFaqMinimumA =>
      'Some shops will not send a rider out below a certain amount. The basket shows the shop\'s minimum and exactly how much is still missing, and checkout stays closed until it is met.';

  @override
  String get custFaqChangeOrderQ => 'Can I change or cancel an order?';

  @override
  String get custFaqChangeOrderA =>
      'An order cannot be edited after it is placed. The order page lists what you can still do with it, and cancelling leaves that list once the shop has started preparing. Once a rider is assigned you can message them from the order page.';

  @override
  String get custFaqTiersQ =>
      'What is the difference between Standard and Express?';

  @override
  String get custFaqTiersA =>
      'Express asks for the order to be treated as urgent and adds a surcharge on top of the delivery fee. The platform sets that amount, not the shop, and your receipt shows it as its own line. A free-delivery offer covers the delivery fee only — the express surcharge stays payable.';

  @override
  String get custFaqWhereIsRiderQ => 'Where is my rider?';

  @override
  String get custFaqWhereIsRiderA =>
      'The order page draws the rider\'s recorded positions on a map from the moment they collect your order. The arrival time comes from the tracking service; when it has no recent position to measure from, it says so instead of showing a guess.';

  @override
  String get custFaqDeliveryFeeQ => 'How is the delivery fee worked out?';

  @override
  String get custFaqDeliveryFeeA =>
      'By the area you are delivering to, which is why a saved address carries an area. A promotion can waive it, and when it does the basket names the promotion rather than only showing a zero.';

  @override
  String get custFaqAddressPinQ => 'Why should I drop a pin on the map?';

  @override
  String get custFaqAddressPinA =>
      'A typed line gets the rider to the street; the pin gets them to the door, and it is the point the arrival time is measured against. Without one your order still arrives, but there is nothing on the map to estimate from.';

  @override
  String get custFaqPayMethodsQ => 'Which payment methods really work?';

  @override
  String get custFaqPayMethodsA =>
      'Cash on delivery is the only method in this build that moves real money. Card and wallet are wired to a test payment provider and are labelled \"Test payment\" at checkout: choosing one authorises against that provider and nothing is charged.';

  @override
  String get custFaqPromoQ => 'How do promo codes work?';

  @override
  String get custFaqPromoA =>
      'Type one in the basket and it is checked against what is in the basket right then, so a code can start applying the moment you cross its minimum. What is actually billed is recomputed by the server when the order is placed, and the confirmation shows that figure.';

  @override
  String get custFaqRefundQ => 'How do I get a refund?';

  @override
  String get custFaqRefundA =>
      'There is no refund button in the app. Cash orders are settled at the door, so a problem with one is sorted with us directly — message or email support with your order number and what went wrong.';

  @override
  String get custFaqPasscodeQ => 'I forgot my passcode.';

  @override
  String get custFaqPasscodeA =>
      'Tap \"Forgot password?\" on the sign-in screen. A six-digit code goes to the email on the account, lasts ten minutes and works once. From inside the app the same steps are under Edit on this screen.';

  @override
  String get custFaqProfileQ => 'Can I change my name or email?';

  @override
  String get custFaqProfileA =>
      'Not from the app yet. They were set when the account was created; the passcode is the one thing on the account you can change yourself.';

  @override
  String get custFaqApplyQ => 'How do I sell on YouDrop, or deliver for it?';

  @override
  String get custFaqApplyA =>
      'From the welcome screen, before signing in: choose shop or rider and fill in the application. You will be asked for contact details, documents and payout details, and you get an account at the end so you can sign in and follow it.';

  @override
  String get custFaqApplyWaitQ => 'How long does an application take?';

  @override
  String get custFaqApplyWaitA =>
      'A person reads it, so there is no fixed time. Your application screen shows the stage it is at and whether any document was sent back for a correction — that screen is the status, and nothing is decided automatically.';

  @override
  String deliveryTierExpressSurcharge(Object amount) {
    return 'Express +$amount';
  }

  @override
  String get riderTierExpress => 'Express';

  @override
  String get riderCompletionRate => 'Completed';

  @override
  String riderHoursValue(Object hours) {
    return '$hours h';
  }

  @override
  String riderPerformanceLine(Object delivered, Object claimed, Object days) {
    return '$delivered of $claimed claimed jobs delivered in $days days';
  }

  @override
  String riderPerformanceDropped(Object count) {
    return ' · $count dropped after claiming';
  }

  @override
  String ratingWithCount(Object average, Object ratings) {
    return '$average · $ratings ratings';
  }

  @override
  String get riderMapYouAreHere => 'You';

  @override
  String get riderMapNoFixYet => 'Waiting for your first GPS fix';

  @override
  String get riderMapUnavailable => 'Map unavailable';

  @override
  String get riderNavigateFailed => 'No map app could be opened.';

  @override
  String get riderRegionAllAreas => 'Every area';

  @override
  String get riderHelpTitle => 'Help & support';

  @override
  String get riderHelpConversations => 'Your conversations';

  @override
  String get riderHelpNoConversations =>
      'A chat opens with the customer on every job you are assigned.';

  @override
  String get riderHelpCouldNotLoad => 'Could not load your conversations';

  @override
  String riderHelpOrderThread(Object ref) {
    return 'Order $ref';
  }

  @override
  String get riderHelpThreadClosed => 'Closed';

  @override
  String get riderHelpHowItWorks => 'How this works';

  @override
  String get riderHelpDuty =>
      'You only receive work while you are on duty and your phone is reporting its position.';

  @override
  String get riderHelpClaim =>
      'A job is yours the moment you accept it. If someone accepted it first, the board says so.';

  @override
  String get riderHelpCashOut =>
      'Cash-out is requested from the Earnings tab and handed over by the platform team.';

  @override
  String get riderHelpExpress =>
      'An Express job is a customer who paid for speed. The premium is the platform\'s, not part of your fee.';

  @override
  String get riderDocumentsTitle => 'Documents & licences';

  @override
  String get riderDocumentsCouldNotLoad => 'Could not load your documents';

  @override
  String get riderPayoutCouldNotLoad => 'Could not load your bank details';

  @override
  String get authPinYourArea => 'Tap the map to mark where you will be working';

  @override
  String authPinnedAt(Object lat, Object lng) {
    return 'Pinned at $lat, $lng';
  }

  @override
  String get authPinClear => 'Remove pin';

  @override
  String get authMapUnavailable => 'Map unavailable';

  @override
  String get riderStatementTitle => 'Reconciliation';

  @override
  String get riderStatementRowSubtitle =>
      'Cash you are holding, against what you have earned';

  @override
  String get riderStatementPeriodThisMonth => 'This month';

  @override
  String get riderStatementPeriodLastMonth => 'Last month';

  @override
  String riderStatementRangeLine(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String riderStatementGeneratedAt(Object when) {
    return 'Worked out $when';
  }

  @override
  String get riderStatementCouldNotLoad => 'Could not load your statement';

  @override
  String get riderStatementNothingYet => 'No money moved in this period.';

  @override
  String get riderStatementSummary => 'How it adds up';

  @override
  String get riderStatementOrders => 'Orders in this period';

  @override
  String riderStatementCollectedLine(Object amount) {
    return 'You collected $amount at the door';
  }

  @override
  String get riderStatementYouOwe => 'You owe the platform';

  @override
  String get riderStatementOwedToYou => 'The platform owes you';

  @override
  String get riderStatementSettled => 'Nothing outstanding either way';

  @override
  String get riderStatementDirectionUnclear => 'This balance could not be read';

  @override
  String get riderStatementDebtNote =>
      'This is normal. Cash you take at the door belongs to the platform until you hand it over — it is not a deduction from your pay.';

  @override
  String get riderStatementCreditNote =>
      'This is your money, still to reach you.';

  @override
  String get riderStatementSettledNote =>
      'Everything you have collected has been accounted for.';

  @override
  String get riderStatementUnclearNote =>
      'This app could not tell which way this balance points. Ask the platform before acting on it.';
}
