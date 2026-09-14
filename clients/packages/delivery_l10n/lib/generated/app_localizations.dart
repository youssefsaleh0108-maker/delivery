import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of DeliveryStrings
/// returned by `DeliveryStrings.of(context)`.
///
/// Applications need to include `DeliveryStrings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: DeliveryStrings.localizationsDelegates,
///   supportedLocales: DeliveryStrings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the DeliveryStrings.supportedLocales
/// property.
abstract class DeliveryStrings {
  DeliveryStrings(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DeliveryStrings of(BuildContext context) {
    return Localizations.of<DeliveryStrings>(context, DeliveryStrings)!;
  }

  static const LocalizationsDelegate<DeliveryStrings> delegate =
      _DeliveryStringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'YouDrop'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navShops.
  ///
  /// In en, this message translates to:
  /// **'Shops'**
  String get navShops;

  /// No description provided for @navBasket.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get navBasket;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navButler.
  ///
  /// In en, this message translates to:
  /// **'Butler'**
  String get navButler;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deliverTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get deliverTo;

  /// No description provided for @setDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Set delivery address'**
  String get setDeliveryAddress;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'12 Test Street, Flat 4'**
  String get addressHint;

  /// No description provided for @labelOptional.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get labelOptional;

  /// No description provided for @labelHint.
  ///
  /// In en, this message translates to:
  /// **'Home, Work'**
  String get labelHint;

  /// No description provided for @riderNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes for the rider (optional)'**
  String get riderNotesOptional;

  /// No description provided for @riderNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Buzzer 4, second floor'**
  String get riderNotesHint;

  /// No description provided for @deliverHere.
  ///
  /// In en, this message translates to:
  /// **'Deliver here'**
  String get deliverHere;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @whereShouldWeBring.
  ///
  /// In en, this message translates to:
  /// **'Where should we bring your order?'**
  String get whereShouldWeBring;

  /// No description provided for @forgetThisAddress.
  ///
  /// In en, this message translates to:
  /// **'Forget this address'**
  String get forgetThisAddress;

  /// No description provided for @addressTooShort.
  ///
  /// In en, this message translates to:
  /// **'A bit more detail so the rider can find you'**
  String get addressTooShort;

  /// No description provided for @searchShops.
  ///
  /// In en, this message translates to:
  /// **'Search shops and cuisines'**
  String get searchShops;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @allStores.
  ///
  /// In en, this message translates to:
  /// **'All stores'**
  String get allStores;

  /// No description provided for @yourFavourites.
  ///
  /// In en, this message translates to:
  /// **'Your favourites'**
  String get yourFavourites;

  /// No description provided for @starredShops.
  ///
  /// In en, this message translates to:
  /// **'Starred shops'**
  String get starredShops;

  /// No description provided for @offersForYou.
  ///
  /// In en, this message translates to:
  /// **'Offers for you'**
  String get offersForYou;

  /// No description provided for @shopsDelivering.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shop delivering to you} other{{count} shops delivering to you}}'**
  String shopsDelivering(int count);

  /// No description provided for @noShopsMatch.
  ///
  /// In en, this message translates to:
  /// **'No shops match'**
  String get noShopsMatch;

  /// No description provided for @tryClearingAFilter.
  ///
  /// In en, this message translates to:
  /// **'Try clearing a filter or two.'**
  String get tryClearingAFilter;

  /// No description provided for @nothingDeliveringHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing is delivering here just yet.'**
  String get nothingDeliveringHere;

  /// No description provided for @couldNotLoadStorefront.
  ///
  /// In en, this message translates to:
  /// **'Could not load the storefront'**
  String get couldNotLoadStorefront;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @filterOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get filterOffers;

  /// No description provided for @filterUnder30.
  ///
  /// In en, this message translates to:
  /// **'Under 30 min'**
  String get filterUnder30;

  /// No description provided for @filterFreeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get filterFreeDelivery;

  /// No description provided for @filterHighlyRated.
  ///
  /// In en, this message translates to:
  /// **'4.5+'**
  String get filterHighlyRated;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @statusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpen;

  /// No description provided for @statusBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get statusBusy;

  /// No description provided for @statusClosingSoon.
  ///
  /// In en, this message translates to:
  /// **'Closing soon'**
  String get statusClosingSoon;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @ratingNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get ratingNew;

  /// No description provided for @freeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get freeDelivery;

  /// No description provided for @deliveryFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'{amount} delivery'**
  String deliveryFeeLabel(String amount);

  /// No description provided for @etaRange.
  ///
  /// In en, this message translates to:
  /// **'{from}-{to} min'**
  String etaRange(int from, int to);

  /// No description provided for @tabShop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get tabShop;

  /// No description provided for @tabAisles.
  ///
  /// In en, this message translates to:
  /// **'Aisles'**
  String get tabAisles;

  /// No description provided for @tabOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get tabOffers;

  /// No description provided for @tabBuyAgain.
  ///
  /// In en, this message translates to:
  /// **'Buy Again'**
  String get tabBuyAgain;

  /// No description provided for @everything.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get everything;

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemCount(int count);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @nothingOnShelves.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the shelves yet'**
  String get nothingOnShelves;

  /// No description provided for @nothingInAisle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this aisle'**
  String get nothingInAisle;

  /// No description provided for @noOffersHere.
  ///
  /// In en, this message translates to:
  /// **'No offers running here right now'**
  String get noOffersHere;

  /// No description provided for @noHistoryHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing from this shop in your history yet'**
  String get noHistoryHere;

  /// No description provided for @appliesEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Applies everywhere'**
  String get appliesEverywhere;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @soldOut.
  ///
  /// In en, this message translates to:
  /// **'sold out'**
  String get soldOut;

  /// No description provided for @addWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Add · {total}'**
  String addWithTotal(String total);

  /// No description provided for @basket.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get basket;

  /// No description provided for @basketEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your basket is empty'**
  String get basketEmpty;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @checkoutWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Checkout · {total}'**
  String checkoutWithTotal(String total);

  /// No description provided for @minimumNotReached.
  ///
  /// In en, this message translates to:
  /// **'Minimum not reached'**
  String get minimumNotReached;

  /// No description provided for @minimumExplanation.
  ///
  /// In en, this message translates to:
  /// **'This shop has a minimum of {minimum} — add {shortfall} more.'**
  String minimumExplanation(String minimum, String shortfall);

  /// No description provided for @viewBasket.
  ///
  /// In en, this message translates to:
  /// **'View basket'**
  String get viewBasket;

  /// No description provided for @startNewBasket.
  ///
  /// In en, this message translates to:
  /// **'Start a new basket?'**
  String get startNewBasket;

  /// No description provided for @basketFromAnotherShop.
  ///
  /// In en, this message translates to:
  /// **'Your basket has items from {shop}. We can only deliver from one shop at a time.'**
  String basketFromAnotherShop(String shop);

  /// No description provided for @keepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get keepIt;

  /// No description provided for @startHere.
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get startHere;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @payWithCash.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get payWithCash;

  /// No description provided for @payWithCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get payWithCard;

  /// No description provided for @paidWith.
  ///
  /// In en, this message translates to:
  /// **'Paid with'**
  String get paidWith;

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetails;

  /// No description provided for @yourOrder.
  ///
  /// In en, this message translates to:
  /// **'Your order'**
  String get yourOrder;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @deliveredOn.
  ///
  /// In en, this message translates to:
  /// **'Delivered on: {when}'**
  String deliveredOn(String when);

  /// No description provided for @placedOn.
  ///
  /// In en, this message translates to:
  /// **'Placed on: {when}'**
  String placedOn(String when);

  /// No description provided for @deliveryCharge.
  ///
  /// In en, this message translates to:
  /// **'Delivery Charge'**
  String get deliveryCharge;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @couldNotLoadOrder.
  ///
  /// In en, this message translates to:
  /// **'Could not load this order'**
  String get couldNotLoadOrder;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get noOrdersYet;

  /// No description provided for @tracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @stepPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get stepPlaced;

  /// No description provided for @stepAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get stepAccepted;

  /// No description provided for @stepPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get stepPreparing;

  /// No description provided for @stepReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get stepReady;

  /// No description provided for @stepOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get stepOnTheWay;

  /// No description provided for @stepDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get stepDelivered;

  /// No description provided for @waitingForRider.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the rider\'s first location.'**
  String get waitingForRider;

  /// No description provided for @locationAfterPickup.
  ///
  /// In en, this message translates to:
  /// **'The rider\'s location appears once your order is picked up.'**
  String get locationAfterPickup;

  /// No description provided for @fixes.
  ///
  /// In en, this message translates to:
  /// **'Fixes'**
  String get fixes;

  /// No description provided for @travelled.
  ///
  /// In en, this message translates to:
  /// **'Travelled'**
  String get travelled;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// No description provided for @rateYourOrder.
  ///
  /// In en, this message translates to:
  /// **'Rate your order'**
  String get rateYourOrder;

  /// No description provided for @yourRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get yourRating;

  /// No description provided for @leaveAComment.
  ///
  /// In en, this message translates to:
  /// **'Leave a comment (optional)'**
  String get leaveAComment;

  /// No description provided for @submitReview.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitReview;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @noReviewsYet.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet'**
  String get noReviewsYet;

  /// No description provided for @butler.
  ///
  /// In en, this message translates to:
  /// **'Butler'**
  String get butler;

  /// No description provided for @butlerTagline.
  ///
  /// In en, this message translates to:
  /// **'Anything that fits on a bike'**
  String get butlerTagline;

  /// No description provided for @butlerBlurb.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you need and where from. A shopper buys it and brings it to you.'**
  String get butlerBlurb;

  /// No description provided for @butlerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Need something that is not on here? We will buy it for you.'**
  String get butlerPrompt;

  /// No description provided for @whatDoYouNeed.
  ///
  /// In en, this message translates to:
  /// **'What do you need?'**
  String get whatDoYouNeed;

  /// No description provided for @whereFromOptional.
  ///
  /// In en, this message translates to:
  /// **'Where from? (optional)'**
  String get whereFromOptional;

  /// No description provided for @budgetCapOptional.
  ///
  /// In en, this message translates to:
  /// **'Budget cap (optional)'**
  String get budgetCapOptional;

  /// No description provided for @requestAButler.
  ///
  /// In en, this message translates to:
  /// **'Request a Butler'**
  String get requestAButler;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @nothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get nothingYet;

  /// No description provided for @orderUpdatesHere.
  ///
  /// In en, this message translates to:
  /// **'Order updates will show up here.'**
  String get orderUpdatesHere;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Groceries, food and more — delivered.'**
  String get splashTagline;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not sign you in.'**
  String get signInFailed;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to order.'**
  String get signOutConfirm;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @roles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get roles;

  /// No description provided for @selectRequiredOptions.
  ///
  /// In en, this message translates to:
  /// **'Select required options'**
  String get selectRequiredOptions;

  /// No description provided for @orderPlacedToast.
  ///
  /// In en, this message translates to:
  /// **'Order #{id} placed · {total}'**
  String orderPlacedToast(String id, String total);

  /// No description provided for @deliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get deliveryAddress;

  /// No description provided for @addressRequired.
  ///
  /// In en, this message translates to:
  /// **'We need somewhere to deliver to'**
  String get addressRequired;

  /// No description provided for @contactPhoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Contact phone (optional)'**
  String get contactPhoneOptional;

  /// No description provided for @merchantNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes for the merchant (optional)'**
  String get merchantNotesOptional;

  /// No description provided for @couldNotLoadShop.
  ///
  /// In en, this message translates to:
  /// **'Could not load this shop'**
  String get couldNotLoadShop;

  /// No description provided for @couldNotLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Could not load more — try again'**
  String get couldNotLoadMore;

  /// No description provided for @chooseUpTo.
  ///
  /// In en, this message translates to:
  /// **'Choose up to {count} under {group}'**
  String chooseUpTo(int count, String group);

  /// No description provided for @cancelThisOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get cancelThisOrder;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @couldNotLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Could not load your orders.'**
  String get couldNotLoadOrders;

  /// No description provided for @browseAndPlaceFirst.
  ///
  /// In en, this message translates to:
  /// **'Browse the catalog and place your first one.'**
  String get browseAndPlaceFirst;

  /// No description provided for @replaceYourBasket.
  ///
  /// In en, this message translates to:
  /// **'Replace your basket?'**
  String get replaceYourBasket;

  /// No description provided for @basketFromShopReplace.
  ///
  /// In en, this message translates to:
  /// **'Your basket has items from {shop}. Reordering will replace it.'**
  String basketFromShopReplace(String shop);

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @openStore.
  ///
  /// In en, this message translates to:
  /// **'Open {store}'**
  String openStore(String store);

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @couldNotLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications'**
  String get couldNotLoadNotifications;

  /// No description provided for @pullDownToTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again.'**
  String get pullDownToTryAgain;

  /// No description provided for @setAddressFirst.
  ///
  /// In en, this message translates to:
  /// **'Set a delivery address first'**
  String get setAddressFirst;

  /// No description provided for @whatAreWeMoving.
  ///
  /// In en, this message translates to:
  /// **'What are we moving?'**
  String get whatAreWeMoving;

  /// No description provided for @pickUpFrom.
  ///
  /// In en, this message translates to:
  /// **'Pick up from'**
  String get pickUpFrom;

  /// No description provided for @whoReceivesItOptional.
  ///
  /// In en, this message translates to:
  /// **'Who receives it? (optional)'**
  String get whoReceivesItOptional;

  /// No description provided for @buyMeSomething.
  ///
  /// In en, this message translates to:
  /// **'Buy me something'**
  String get buyMeSomething;

  /// No description provided for @aShopperBuysIt.
  ///
  /// In en, this message translates to:
  /// **'A shopper buys it'**
  String get aShopperBuysIt;

  /// No description provided for @deliverYourStuff.
  ///
  /// In en, this message translates to:
  /// **'Deliver your stuff'**
  String get deliverYourStuff;

  /// No description provided for @youAlreadyHaveIt.
  ///
  /// In en, this message translates to:
  /// **'You already have it'**
  String get youAlreadyHaveIt;

  /// No description provided for @yourErrands.
  ///
  /// In en, this message translates to:
  /// **'Your errands'**
  String get yourErrands;

  /// No description provided for @couldNotLoadErrands.
  ///
  /// In en, this message translates to:
  /// **'Could not load your errands'**
  String get couldNotLoadErrands;

  /// No description provided for @noThanks.
  ///
  /// In en, this message translates to:
  /// **'No thanks'**
  String get noThanks;

  /// No description provided for @payAmount.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String payAmount(String amount);

  /// No description provided for @trackIt.
  ///
  /// In en, this message translates to:
  /// **'Track it'**
  String get trackIt;

  /// No description provided for @whatDidItCost.
  ///
  /// In en, this message translates to:
  /// **'What did it cost?'**
  String get whatDidItCost;

  /// No description provided for @cappedAt.
  ///
  /// In en, this message translates to:
  /// **'They capped it at {amount}'**
  String cappedAt(String amount);

  /// No description provided for @goodsTotal.
  ///
  /// In en, this message translates to:
  /// **'Goods total'**
  String get goodsTotal;

  /// No description provided for @receiptNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Receipt number (optional)'**
  String get receiptNumberOptional;

  /// No description provided for @sendForApproval.
  ///
  /// In en, this message translates to:
  /// **'Send for approval'**
  String get sendForApproval;

  /// No description provided for @noErrandsWaiting.
  ///
  /// In en, this message translates to:
  /// **'No errands waiting.'**
  String get noErrandsWaiting;

  /// No description provided for @nothingToClaim.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting to be claimed.'**
  String get nothingToClaim;

  /// No description provided for @claim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get claim;

  /// No description provided for @reportWhatItCost.
  ///
  /// In en, this message translates to:
  /// **'Report what it cost'**
  String get reportWhatItCost;

  /// No description provided for @deliveries.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get deliveries;

  /// No description provided for @contactLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact: {phone}'**
  String contactLabel(String phone);

  /// No description provided for @couldNotUpdateFavourites.
  ///
  /// In en, this message translates to:
  /// **'Could not update your favourites.'**
  String get couldNotUpdateFavourites;

  /// No description provided for @itemNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'One of these items is no longer available.'**
  String get itemNoLongerAvailable;

  /// No description provided for @checkDeliveryDetails.
  ///
  /// In en, this message translates to:
  /// **'Please check the delivery details.'**
  String get checkDeliveryDetails;

  /// No description provided for @couldNotPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Could not place the order. Please try again.'**
  String get couldNotPlaceOrder;

  /// No description provided for @placing.
  ///
  /// In en, this message translates to:
  /// **'Placing…'**
  String get placing;

  /// No description provided for @placeOrderWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Place order · {total}'**
  String placeOrderWithTotal(String total);

  /// No description provided for @nothingStillAvailable.
  ///
  /// In en, this message translates to:
  /// **'Nothing from this order is still available.'**
  String get nothingStillAvailable;

  /// No description provided for @addedToBasket.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 item to your basket} other{Added {count} items to your basket}}'**
  String addedToBasket(int count);

  /// No description provided for @addedSomeMissing.
  ///
  /// In en, this message translates to:
  /// **'Added {added}; {missing} no longer available'**
  String addedSomeMissing(int added, int missing);

  /// No description provided for @couldNotReorder.
  ///
  /// In en, this message translates to:
  /// **'Could not reorder just now.'**
  String get couldNotReorder;

  /// No description provided for @reorderWillReplace.
  ///
  /// In en, this message translates to:
  /// **'Reordering will start a new one.'**
  String get reorderWillReplace;

  /// No description provided for @setByStoreCharged.
  ///
  /// In en, this message translates to:
  /// **'Set by {store} and charged on delivery.'**
  String setByStoreCharged(String store);

  /// No description provided for @cancelBeforeAccepted.
  ///
  /// In en, this message translates to:
  /// **'You can only cancel before the merchant accepts it. This cannot be undone.'**
  String get cancelBeforeAccepted;

  /// No description provided for @cancelledByCustomer.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by customer'**
  String get cancelledByCustomer;

  /// No description provided for @tooLateToCancel.
  ///
  /// In en, this message translates to:
  /// **'Too late — the merchant has already started this order.'**
  String get tooLateToCancel;

  /// No description provided for @couldNotCancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel the order.'**
  String get couldNotCancelOrder;

  /// No description provided for @riderAt.
  ///
  /// In en, this message translates to:
  /// **'Rider at {lat}, {lng}'**
  String riderAt(String lat, String lng);

  /// No description provided for @couldNotPriceCombination.
  ///
  /// In en, this message translates to:
  /// **'Could not price that combination.'**
  String get couldNotPriceCombination;

  /// No description provided for @optionSoldOut.
  ///
  /// In en, this message translates to:
  /// **'{name} — sold out'**
  String optionSoldOut(String name);

  /// No description provided for @addToReachMinimum.
  ///
  /// In en, this message translates to:
  /// **'Add {amount} to reach the minimum'**
  String addToReachMinimum(String amount);

  /// No description provided for @removeFromFavourites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFromFavourites;

  /// No description provided for @addToFavourites.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get addToFavourites;

  /// No description provided for @minOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Min {amount}'**
  String minOrderLabel(String amount);

  /// No description provided for @closesAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Closes {when}'**
  String closesAtLabel(String when);

  /// No description provided for @noAislesYet.
  ///
  /// In en, this message translates to:
  /// **'This shop has no aisles yet'**
  String get noAislesYet;

  /// No description provided for @signInToSeeHistory.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see what you ordered before'**
  String get signInToSeeHistory;

  /// No description provided for @tabAislesCount.
  ///
  /// In en, this message translates to:
  /// **'Aisles ({count})'**
  String tabAislesCount(int count);

  /// No description provided for @tabOffersCount.
  ///
  /// In en, this message translates to:
  /// **'Offers ({count})'**
  String tabOffersCount(int count);

  /// No description provided for @basketFromAnotherShopSingle.
  ///
  /// In en, this message translates to:
  /// **'We can only deliver from one shop at a time.'**
  String get basketFromAnotherShopSingle;

  /// No description provided for @basketHasOtherShopItems.
  ///
  /// In en, this message translates to:
  /// **'This basket already has items from another shop.'**
  String get basketHasOtherShopItems;

  /// No description provided for @distanceKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String distanceKm(String km);

  /// No description provided for @distanceM.
  ///
  /// In en, this message translates to:
  /// **'{m} m'**
  String distanceM(String m);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}s ago'**
  String secondsAgo(int count);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// No description provided for @lineQuantity.
  ///
  /// In en, this message translates to:
  /// **'{qty} × {name}'**
  String lineQuantity(int qty, String name);

  /// No description provided for @lineQtyPrice.
  ///
  /// In en, this message translates to:
  /// **'{qty} × {price}'**
  String lineQtyPrice(int qty, String price);

  /// No description provided for @orderRefWithAddress.
  ///
  /// In en, this message translates to:
  /// **'#{ref} · {address}'**
  String orderRefWithAddress(String ref, String address);

  /// No description provided for @sentBuyConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Sent. A shopper will pick it up and tell you what it costs before you pay.'**
  String get sentBuyConfirmation;

  /// No description provided for @sentMoveConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Sent. A rider will collect it.'**
  String get sentMoveConfirmation;

  /// No description provided for @cannotRequestErrands.
  ///
  /// In en, this message translates to:
  /// **'This account cannot request errands'**
  String get cannotRequestErrands;

  /// No description provided for @couldNotSendRequest.
  ///
  /// In en, this message translates to:
  /// **'Could not send that request'**
  String get couldNotSendRequest;

  /// No description provided for @butlerMoveTagline.
  ///
  /// In en, this message translates to:
  /// **'Send something across town'**
  String get butlerMoveTagline;

  /// No description provided for @butlerMoveBlurb.
  ///
  /// In en, this message translates to:
  /// **'Already have it? A rider collects it from one address and drops it at another. Nothing is bought.'**
  String get butlerMoveBlurb;

  /// No description provided for @buyHint.
  ///
  /// In en, this message translates to:
  /// **'A phone charger, USB-C, and a bottle of still water'**
  String get buyHint;

  /// No description provided for @buyValidator.
  ///
  /// In en, this message translates to:
  /// **'A bit more detail so the shopper knows what to buy'**
  String get buyValidator;

  /// No description provided for @whereFromHint.
  ///
  /// In en, this message translates to:
  /// **'Any pharmacy near Hamra'**
  String get whereFromHint;

  /// No description provided for @budgetValidator.
  ///
  /// In en, this message translates to:
  /// **'A number, or leave it blank'**
  String get budgetValidator;

  /// No description provided for @moveHint.
  ///
  /// In en, this message translates to:
  /// **'A4 envelope with documents, nothing fragile'**
  String get moveHint;

  /// No description provided for @moveValidator.
  ///
  /// In en, this message translates to:
  /// **'A bit more detail so the rider knows what to expect'**
  String get moveValidator;

  /// No description provided for @pickUpHint.
  ///
  /// In en, this message translates to:
  /// **'8 Clemenceau Street, reception desk'**
  String get pickUpHint;

  /// No description provided for @pickUpValidator.
  ///
  /// In en, this message translates to:
  /// **'Where should the rider collect it?'**
  String get pickUpValidator;

  /// No description provided for @receiverHint.
  ///
  /// In en, this message translates to:
  /// **'Name and phone number'**
  String get receiverHint;

  /// No description provided for @requestAPickup.
  ///
  /// In en, this message translates to:
  /// **'Request a pickup'**
  String get requestAPickup;

  /// No description provided for @errandFeeBuy.
  ///
  /// In en, this message translates to:
  /// **'Errand fee {fee}. The shopper tells you what the goods cost before you pay anything.'**
  String errandFeeBuy(String fee);

  /// No description provided for @errandFeeMove.
  ///
  /// In en, this message translates to:
  /// **'Errand fee {fee}. Nothing is bought, so that is the whole price.'**
  String errandFeeMove(String fee);

  /// No description provided for @dropOffAt.
  ///
  /// In en, this message translates to:
  /// **'Drop off at'**
  String get dropOffAt;

  /// No description provided for @thatDidNotWork.
  ///
  /// In en, this message translates to:
  /// **'That did not work'**
  String get thatDidNotWork;

  /// No description provided for @aboveYourCap.
  ///
  /// In en, this message translates to:
  /// **'That is above the {cap} cap you set.'**
  String aboveYourCap(String cap);

  /// No description provided for @declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get declined;

  /// No description provided for @approvedOnItsWay.
  ///
  /// In en, this message translates to:
  /// **'Approved — it is on its way'**
  String get approvedOnItsWay;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @waitingForShopper.
  ///
  /// In en, this message translates to:
  /// **'Waiting for someone to take it · fee {fee}'**
  String waitingForShopper(String fee);

  /// No description provided for @shopperIsOnIt.
  ///
  /// In en, this message translates to:
  /// **'A shopper is on it. They will tell you what it costs.'**
  String get shopperIsOnIt;

  /// No description provided for @riderOnTheWayToCollect.
  ///
  /// In en, this message translates to:
  /// **'A rider is on the way to collect it · {total}'**
  String riderOnTheWayToCollect(String total);

  /// No description provided for @goodsPlusFee.
  ///
  /// In en, this message translates to:
  /// **'Goods {goods} + fee {fee} = {total}'**
  String goodsPlusFee(String goods, String fee, String total);

  /// No description provided for @agreedAt.
  ///
  /// In en, this message translates to:
  /// **'Agreed at {total}'**
  String agreedAt(String total);

  /// No description provided for @youDeclinedThisPrice.
  ///
  /// In en, this message translates to:
  /// **'You declined this price'**
  String get youDeclinedThisPrice;

  /// No description provided for @nobodyPickedThisUp.
  ///
  /// In en, this message translates to:
  /// **'Nobody picked this up'**
  String get nobodyPickedThisUp;

  /// No description provided for @butlerStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get butlerStatusOpen;

  /// No description provided for @butlerStatusClaimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get butlerStatusClaimed;

  /// No description provided for @butlerStatusYourCall.
  ///
  /// In en, this message translates to:
  /// **'Your call'**
  String get butlerStatusYourCall;

  /// No description provided for @butlerStatusAgreed.
  ///
  /// In en, this message translates to:
  /// **'Agreed'**
  String get butlerStatusAgreed;

  /// No description provided for @butlerStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get butlerStatusExpired;

  /// Header of the page a customer's Butler errand opens onto from the recent-tasks list.
  ///
  /// In en, this message translates to:
  /// **'Errand details'**
  String get butlerDetailsTitle;

  /// Accessibility label for the chevron on a Butler errand row that opens its details.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get butlerViewDetails;

  /// No description provided for @butlerCancelErrand.
  ///
  /// In en, this message translates to:
  /// **'Cancel errand'**
  String get butlerCancelErrand;

  /// No description provided for @butlerCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this errand?'**
  String get butlerCancelConfirmTitle;

  /// No description provided for @butlerCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It is withdrawn straight away and nobody will go for it. You can always ask again.'**
  String get butlerCancelConfirmBody;

  /// No description provided for @butlerCancelConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get butlerCancelConfirmYes;

  /// Opens the order an agreed Butler errand became, where its delivery is tracked.
  ///
  /// In en, this message translates to:
  /// **'Track order'**
  String get butlerTrackOrder;

  /// No description provided for @butlerDetailProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get butlerDetailProgress;

  /// No description provided for @butlerDetailTheErrand.
  ///
  /// In en, this message translates to:
  /// **'The errand'**
  String get butlerDetailTheErrand;

  /// No description provided for @butlerDetailWhereFrom.
  ///
  /// In en, this message translates to:
  /// **'Where from'**
  String get butlerDetailWhereFrom;

  /// No description provided for @butlerDetailRecipient.
  ///
  /// In en, this message translates to:
  /// **'Who receives it'**
  String get butlerDetailRecipient;

  /// No description provided for @butlerDetailContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get butlerDetailContactPhone;

  /// No description provided for @butlerDetailPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get butlerDetailPrice;

  /// No description provided for @butlerDetailBudgetCap.
  ///
  /// In en, this message translates to:
  /// **'Your budget cap'**
  String get butlerDetailBudgetCap;

  /// No description provided for @butlerDetailGoods.
  ///
  /// In en, this message translates to:
  /// **'Goods'**
  String get butlerDetailGoods;

  /// Shown in place of the goods price of a purchase errand before the shopper has bought it.
  ///
  /// In en, this message translates to:
  /// **'Known once the shopper has paid'**
  String get butlerDetailGoodsPending;

  /// No description provided for @butlerDetailErrandFee.
  ///
  /// In en, this message translates to:
  /// **'Errand fee'**
  String get butlerDetailErrandFee;

  /// No description provided for @butlerDetailTotal.
  ///
  /// In en, this message translates to:
  /// **'Total to pay'**
  String get butlerDetailTotal;

  /// No description provided for @butlerDetailReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt reference'**
  String get butlerDetailReceipt;

  /// No description provided for @butlerDeclineReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String butlerDeclineReason(String reason);

  /// No description provided for @butlerStepRequested.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get butlerStepRequested;

  /// No description provided for @butlerStepClaimedBuy.
  ///
  /// In en, this message translates to:
  /// **'A shopper took it'**
  String get butlerStepClaimedBuy;

  /// No description provided for @butlerStepClaimedSend.
  ///
  /// In en, this message translates to:
  /// **'A rider took it'**
  String get butlerStepClaimedSend;

  /// No description provided for @butlerStepQuoted.
  ///
  /// In en, this message translates to:
  /// **'Price quoted'**
  String get butlerStepQuoted;

  /// No description provided for @butlerStepAgreed.
  ///
  /// In en, this message translates to:
  /// **'Price agreed'**
  String get butlerStepAgreed;

  /// Last step of a send errand, which has no price to agree — the rider is booked to carry it.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get butlerStepConfirmed;

  /// Timeline step of a purchase errand nobody has taken yet. Worded as not-yet-happened on purpose: its finished form is butlerStepClaimedBuy.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a shopper'**
  String get butlerStepClaimBuyPending;

  /// No description provided for @butlerStepClaimSendPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a rider'**
  String get butlerStepClaimSendPending;

  /// No description provided for @butlerStepQuotePending.
  ///
  /// In en, this message translates to:
  /// **'The shopper tells you the price'**
  String get butlerStepQuotePending;

  /// No description provided for @butlerStepAgreePending.
  ///
  /// In en, this message translates to:
  /// **'You agree the price'**
  String get butlerStepAgreePending;

  /// Timeline step of a send errand still waiting for the customer to confirm the errand fee.
  ///
  /// In en, this message translates to:
  /// **'You confirm the fee'**
  String get butlerStepConfirmPending;

  /// Read by a screen reader before a finished step of an errand's timeline.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get butlerStepStateDone;

  /// Read by a screen reader before the timeline step the errand is currently waiting on.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get butlerStepStateNow;

  /// Read by a screen reader before a timeline step the errand has not reached yet.
  ///
  /// In en, this message translates to:
  /// **'Still to come'**
  String get butlerStepStateNext;

  /// Read by a screen reader before the step that ended an errand without an agreement (declined, cancelled, expired).
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get butlerStepStateEnded;

  /// The total a declined errand was quoted at — shown so the customer sees what they turned down, without saying it is owed.
  ///
  /// In en, this message translates to:
  /// **'Quoted total'**
  String get butlerDetailQuotedTotal;

  /// Button: the customer confirms a send errand a rider has taken, at this fee. This is what turns it into an order.
  ///
  /// In en, this message translates to:
  /// **'Confirm {amount}'**
  String butlerConfirmFee(String amount);

  /// No description provided for @butlerSendConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed. The rider will collect it.'**
  String get butlerSendConfirmed;

  /// No description provided for @butlerSendAwaitingConfirm.
  ///
  /// In en, this message translates to:
  /// **'A rider took it. Confirm the fee of {fee} and they will collect it.'**
  String butlerSendAwaitingConfirm(String fee);

  /// No description provided for @butlerDeclineConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn down this price?'**
  String get butlerDeclineConfirmTitle;

  /// No description provided for @butlerDeclineConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The errand ends here and cannot be reopened. The shopper has already paid for the goods.'**
  String get butlerDeclineConfirmBody;

  /// No description provided for @butlerDeclineConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, decline'**
  String get butlerDeclineConfirmYes;

  /// No description provided for @somebodyElseClaimed.
  ///
  /// In en, this message translates to:
  /// **'Somebody else claimed that one'**
  String get somebodyElseClaimed;

  /// No description provided for @whatYouPaidBeforeFee.
  ///
  /// In en, this message translates to:
  /// **'What you paid, before the errand fee'**
  String get whatYouPaidBeforeFee;

  /// No description provided for @sentForApproval.
  ///
  /// In en, this message translates to:
  /// **'Sent. They will approve the price before you deliver.'**
  String get sentForApproval;

  /// No description provided for @cappedAtBudget.
  ///
  /// In en, this message translates to:
  /// **'They capped it at {amount}'**
  String cappedAtBudget(String amount);

  /// No description provided for @yours.
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get yours;

  /// No description provided for @buyAndBring.
  ///
  /// In en, this message translates to:
  /// **'Buy and bring'**
  String get buyAndBring;

  /// No description provided for @collectAndDrop.
  ///
  /// In en, this message translates to:
  /// **'Collect and drop'**
  String get collectAndDrop;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @collectAndDropInstruction.
  ///
  /// In en, this message translates to:
  /// **'Collect it and drop it off. It is in your Deliveries tab.'**
  String get collectAndDropInstruction;

  /// No description provided for @waitingOnApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting on them to approve. Do not deliver until they do.'**
  String get waitingOnApproval;

  /// No description provided for @approvedDeliverIt.
  ///
  /// In en, this message translates to:
  /// **'Approved. Deliver it from your Deliveries tab.'**
  String get approvedDeliverIt;

  /// No description provided for @headingWithCount.
  ///
  /// In en, this message translates to:
  /// **'{label} ({count})'**
  String headingWithCount(String label, int count);

  /// No description provided for @availableWithCount.
  ///
  /// In en, this message translates to:
  /// **'Available ({count})'**
  String availableWithCount(int count);

  /// No description provided for @mineWithCount.
  ///
  /// In en, this message translates to:
  /// **'Mine ({count})'**
  String mineWithCount(int count);

  /// No description provided for @errands.
  ///
  /// In en, this message translates to:
  /// **'Errands'**
  String get errands;

  /// No description provided for @nothingWaitingForPickup.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting for pickup right now.'**
  String get nothingWaitingForPickup;

  /// No description provided for @noActiveDeliveries.
  ///
  /// In en, this message translates to:
  /// **'You have no active deliveries.'**
  String get noActiveDeliveries;

  /// No description provided for @anotherRiderClaimedIt.
  ///
  /// In en, this message translates to:
  /// **'Another rider claimed that one first.'**
  String get anotherRiderClaimedIt;

  /// No description provided for @orderAlreadyMovedOn.
  ///
  /// In en, this message translates to:
  /// **'That order has already moved on.'**
  String get orderAlreadyMovedOn;

  /// No description provided for @contactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact: {phone}'**
  String contactPhone(String phone);

  /// No description provided for @statusReadyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get statusReadyForPickup;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @actionAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get actionAccept;

  /// No description provided for @actionPrepare.
  ///
  /// In en, this message translates to:
  /// **'Start preparing'**
  String get actionPrepare;

  /// No description provided for @actionMarkReady.
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get actionMarkReady;

  /// No description provided for @actionClaim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get actionClaim;

  /// No description provided for @actionPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get actionPickedUp;

  /// No description provided for @actionDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get actionDelivered;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @verticalRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get verticalRestaurants;

  /// No description provided for @verticalCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get verticalCoffee;

  /// No description provided for @verticalGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get verticalGroceries;

  /// No description provided for @verticalConvenience.
  ///
  /// In en, this message translates to:
  /// **'Convenience'**
  String get verticalConvenience;

  /// No description provided for @verticalPharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy'**
  String get verticalPharmacy;

  /// No description provided for @verticalElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get verticalElectronics;

  /// No description provided for @verticalFlowersGifts.
  ///
  /// In en, this message translates to:
  /// **'Flowers & Gifts'**
  String get verticalFlowersGifts;

  /// No description provided for @orderPlacedToastShort.
  ///
  /// In en, this message translates to:
  /// **'Order #{ref} placed · {total}'**
  String orderPlacedToastShort(String ref, String total);

  /// No description provided for @minimumExplanationFull.
  ///
  /// In en, this message translates to:
  /// **'This shop has a minimum of {minimum} — add {shortfall} more.'**
  String minimumExplanationFull(String minimum, String shortfall);

  /// No description provided for @addToReachMinimumShort.
  ///
  /// In en, this message translates to:
  /// **'Add {amount} to reach the minimum'**
  String addToReachMinimumShort(String amount);

  /// No description provided for @actionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not {action}.'**
  String actionFailed(String action);

  /// No description provided for @actionOnOrder.
  ///
  /// In en, this message translates to:
  /// **'{action} · #{ref}'**
  String actionOnOrder(String action, String ref);

  /// No description provided for @itemCountWithDot.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemCountWithDot(int count);

  /// No description provided for @riderAtShort.
  ///
  /// In en, this message translates to:
  /// **'Rider at {lat}, {lng}'**
  String riderAtShort(String lat, String lng);

  /// No description provided for @waitingOnApprovalOf.
  ///
  /// In en, this message translates to:
  /// **'Waiting on them to approve {total}. Do not deliver until they do.'**
  String waitingOnApprovalOf(String total);

  /// No description provided for @aislesCount.
  ///
  /// In en, this message translates to:
  /// **'Aisles'**
  String get aislesCount;

  /// No description provided for @signInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see what you ordered before'**
  String get signInPrompt;

  /// No description provided for @merchantPortal.
  ///
  /// In en, this message translates to:
  /// **'Merchant Portal'**
  String get merchantPortal;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get navDelivery;

  /// No description provided for @navMyShop.
  ///
  /// In en, this message translates to:
  /// **'My Shop'**
  String get navMyShop;

  /// No description provided for @manageYourCatalog.
  ///
  /// In en, this message translates to:
  /// **'Manage your catalog'**
  String get manageYourCatalog;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @notAMerchant.
  ///
  /// In en, this message translates to:
  /// **'This account is not registered as a merchant.'**
  String get notAMerchant;

  /// No description provided for @signInAsSomeoneElse.
  ///
  /// In en, this message translates to:
  /// **'Sign in as someone else'**
  String get signInAsSomeoneElse;

  /// No description provided for @carrierNotAvailableToYou.
  ///
  /// In en, this message translates to:
  /// **'That carrier is not available to you'**
  String get carrierNotAvailableToYou;

  /// No description provided for @couldNotLoadCarriers.
  ///
  /// In en, this message translates to:
  /// **'Could not load carriers: {error}'**
  String couldNotLoadCarriers(String error);

  /// No description provided for @whoCarriesYourOrders.
  ///
  /// In en, this message translates to:
  /// **'Who carries your orders'**
  String get whoCarriesYourOrders;

  /// No description provided for @whoCarriesBlurb.
  ///
  /// In en, this message translates to:
  /// **'Who carries your orders. This applies from the moment an order is ready to collect — orders already on their way keep the carrier they went out with.'**
  String get whoCarriesBlurb;

  /// No description provided for @yourOwnDrivers.
  ///
  /// In en, this message translates to:
  /// **'Your own drivers'**
  String get yourOwnDrivers;

  /// No description provided for @fleetRidersBlurb.
  ///
  /// In en, this message translates to:
  /// **'Riders are added to your fleet by the platform. A fleet with nobody in it cannot collect anything.'**
  String get fleetRidersBlurb;

  /// No description provided for @whenCarrierCannotTake.
  ///
  /// In en, this message translates to:
  /// **'When your carrier cannot take an order'**
  String get whenCarrierCannotTake;

  /// No description provided for @letThePlatformChoose.
  ///
  /// In en, this message translates to:
  /// **'Let the platform choose'**
  String get letThePlatformChoose;

  /// No description provided for @whoeverIsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Whoever is available and can take the job. This is the default.'**
  String get whoeverIsAvailable;

  /// No description provided for @thePlatformWillChoose.
  ///
  /// In en, this message translates to:
  /// **'The platform will choose'**
  String get thePlatformWillChoose;

  /// No description provided for @notTakingWorkNow.
  ///
  /// In en, this message translates to:
  /// **'{kind}  ·  not taking work at the moment'**
  String notTakingWorkNow(String kind);

  /// No description provided for @carrierWillCarry.
  ///
  /// In en, this message translates to:
  /// **'{name} will carry your orders'**
  String carrierWillCarry(String name);

  /// No description provided for @ownDriversBlurb.
  ///
  /// In en, this message translates to:
  /// **'If you already have drivers, they can carry your orders and the platform will only step in when they are busy.'**
  String get ownDriversBlurb;

  /// No description provided for @yourFleetIsSetUp.
  ///
  /// In en, this message translates to:
  /// **'Your fleet is set up'**
  String get yourFleetIsSetUp;

  /// No description provided for @setUpMyOwnDrivers.
  ///
  /// In en, this message translates to:
  /// **'Set up my own drivers'**
  String get setUpMyOwnDrivers;

  /// No description provided for @anotherCarrierMayStepIn.
  ///
  /// In en, this message translates to:
  /// **'Another carrier may step in'**
  String get anotherCarrierMayStepIn;

  /// No description provided for @onlyYourChosenCarrier.
  ///
  /// In en, this message translates to:
  /// **'Only your chosen carrier will be used'**
  String get onlyYourChosenCarrier;

  /// No description provided for @letSomeoneElseStepIn.
  ///
  /// In en, this message translates to:
  /// **'Let someone else step in'**
  String get letSomeoneElseStepIn;

  /// No description provided for @onlyAppliesOnceChosen.
  ///
  /// In en, this message translates to:
  /// **'Only applies once you have chosen a carrier.'**
  String get onlyAppliesOnceChosen;

  /// No description provided for @fallbackOnBlurb.
  ///
  /// In en, this message translates to:
  /// **'If your carrier cannot take an order, another one will. Orders go out late rather than not at all.'**
  String get fallbackOnBlurb;

  /// No description provided for @fallbackOffBlurb.
  ///
  /// In en, this message translates to:
  /// **'Orders wait for your carrier. Nothing goes out with anybody else — and an order they cannot take stays on your counter.'**
  String get fallbackOffBlurb;

  /// No description provided for @cancelledByMerchant.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by merchant'**
  String get cancelledByMerchant;

  /// No description provided for @orderAlreadyMovedRefreshing.
  ///
  /// In en, this message translates to:
  /// **'That order has already moved on. Refreshing.'**
  String get orderAlreadyMovedRefreshing;

  /// No description provided for @columnToAccept.
  ///
  /// In en, this message translates to:
  /// **'To accept'**
  String get columnToAccept;

  /// No description provided for @columnPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get columnPreparing;

  /// No description provided for @columnAwaitingRider.
  ///
  /// In en, this message translates to:
  /// **'Awaiting a rider'**
  String get columnAwaitingRider;

  /// No description provided for @columnDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get columnDelivered;

  /// No description provided for @showCompleted.
  ///
  /// In en, this message translates to:
  /// **'Show completed'**
  String get showCompleted;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @updatesEvery.
  ///
  /// In en, this message translates to:
  /// **'Updates every {seconds}s'**
  String updatesEvery(int seconds);

  /// No description provided for @liveOrders.
  ///
  /// In en, this message translates to:
  /// **'Live orders'**
  String get liveOrders;

  /// No description provided for @couldNotLoadOrdersShort.
  ///
  /// In en, this message translates to:
  /// **'Could not load orders.'**
  String get couldNotLoadOrdersShort;

  /// No description provided for @noOrdersYetMerchant.
  ///
  /// In en, this message translates to:
  /// **'No orders yet.'**
  String get noOrdersYetMerchant;

  /// No description provided for @noOrdersNeedingAttention.
  ///
  /// In en, this message translates to:
  /// **'No orders needing attention.'**
  String get noOrdersNeedingAttention;

  /// No description provided for @riderAssigned.
  ///
  /// In en, this message translates to:
  /// **'rider assigned'**
  String get riderAssigned;

  /// No description provided for @noteWithText.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String noteWithText(String note);

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @couldNotSaveProduct.
  ///
  /// In en, this message translates to:
  /// **'Could not save this product'**
  String get couldNotSaveProduct;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @couldNotOpenPicker.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker: {reason}'**
  String couldNotOpenPicker(Object reason);

  /// No description provided for @uploadFailedBecause.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {reason}'**
  String uploadFailedBecause(Object reason);

  /// No description provided for @newProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get newProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get editProduct;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @priceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceLabel;

  /// No description provided for @enterANumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get enterANumber;

  /// No description provided for @priceMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'Price must be greater than zero'**
  String get priceMustBePositive;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @uncategorised.
  ///
  /// In en, this message translates to:
  /// **'Uncategorised'**
  String get uncategorised;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveProductFirst.
  ///
  /// In en, this message translates to:
  /// **'Save the product first, then add photos.'**
  String get saveProductFirst;

  /// No description provided for @merchbAddPhotosNow.
  ///
  /// In en, this message translates to:
  /// **'Add photos now — they upload when you save.'**
  String get merchbAddPhotosNow;

  /// No description provided for @merchbPhotosAddedOnSave.
  ///
  /// In en, this message translates to:
  /// **'These photos are added when you save.'**
  String get merchbPhotosAddedOnSave;

  /// No description provided for @merchbPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get merchbPending;

  /// No description provided for @needsAPhotoToPublish.
  ///
  /// In en, this message translates to:
  /// **'A product needs at least one photo before it can be published.'**
  String get needsAPhotoToPublish;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @couldNotPublishProduct.
  ///
  /// In en, this message translates to:
  /// **'Could not publish this product'**
  String get couldNotPublishProduct;

  /// No description provided for @archiveThisProduct.
  ///
  /// In en, this message translates to:
  /// **'Archive this product?'**
  String get archiveThisProduct;

  /// No description provided for @archiveConfirm.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be withdrawn from the catalog. Existing orders that reference it are unaffected.'**
  String archiveConfirm(String name);

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @myProducts.
  ///
  /// In en, this message translates to:
  /// **'My products'**
  String get myProducts;

  /// No description provided for @onSale.
  ///
  /// In en, this message translates to:
  /// **'On sale'**
  String get onSale;

  /// No description provided for @productsTotal.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 total} other{{count} total}}'**
  String productsTotal(int count);

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @noPhoto.
  ///
  /// In en, this message translates to:
  /// **'No photo'**
  String get noPhoto;

  /// Badge on a product thumbnail that carries more than one photo, and its label for assistive tech.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String photoCount(int count);

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @yourProducts.
  ///
  /// In en, this message translates to:
  /// **'Your products'**
  String get yourProducts;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @noProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get noProductsYet;

  /// No description provided for @createYourFirstProduct.
  ///
  /// In en, this message translates to:
  /// **'Create your first product, add a photo, then publish it.'**
  String get createYourFirstProduct;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @detailWithRef.
  ///
  /// In en, this message translates to:
  /// **'{detail} (ref: {ref})'**
  String detailWithRef(String detail, String ref);

  /// No description provided for @thatDidNotWorkWith.
  ///
  /// In en, this message translates to:
  /// **'That did not work: {error}'**
  String thatDidNotWorkWith(String error);

  /// No description provided for @shopSaved.
  ///
  /// In en, this message translates to:
  /// **'Shop saved'**
  String get shopSaved;

  /// No description provided for @couldNotLoadYourShop.
  ///
  /// In en, this message translates to:
  /// **'Could not load your shop'**
  String get couldNotLoadYourShop;

  /// No description provided for @noShopYet.
  ///
  /// In en, this message translates to:
  /// **'No shop yet'**
  String get noShopYet;

  /// No description provided for @shopCreatedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Add your first product and a shop is created for you automatically.'**
  String get shopCreatedAutomatically;

  /// No description provided for @howYourShopAppears.
  ///
  /// In en, this message translates to:
  /// **'How your shop appears on the storefront'**
  String get howYourShopAppears;

  /// No description provided for @shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get shopName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Tagline'**
  String get tagline;

  /// No description provided for @taglineHint.
  ///
  /// In en, this message translates to:
  /// **'Charcoal grills and mezze, all day'**
  String get taglineHint;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @tagsHint.
  ///
  /// In en, this message translates to:
  /// **'Lebanese, Grills, Mezze  (comma separated)'**
  String get tagsHint;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel;

  /// No description provided for @pictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures'**
  String get pictures;

  /// No description provided for @logoRecognisedBy.
  ///
  /// In en, this message translates to:
  /// **'Your logo is what customers recognise you by in search results'**
  String get logoRecognisedBy;

  /// No description provided for @logo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get logo;

  /// No description provided for @logoHint.
  ///
  /// In en, this message translates to:
  /// **'Square works best. Shown on every store card.'**
  String get logoHint;

  /// No description provided for @cover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get cover;

  /// No description provided for @coverHint.
  ///
  /// In en, this message translates to:
  /// **'Wide. Sits behind your shop header.'**
  String get coverHint;

  /// No description provided for @generatedTileBlurb.
  ///
  /// In en, this message translates to:
  /// **'Until you upload one, customers see a generated tile with your initials — consistent and on-brand, but not yours.'**
  String get generatedTileBlurb;

  /// No description provided for @whatCustomersAreCharged.
  ///
  /// In en, this message translates to:
  /// **'What customers are charged and told to expect'**
  String get whatCustomersAreCharged;

  /// No description provided for @deliveryFeeLabelMerchant.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get deliveryFeeLabelMerchant;

  /// No description provided for @minimumOrder.
  ///
  /// In en, this message translates to:
  /// **'Minimum order'**
  String get minimumOrder;

  /// No description provided for @etaFromMin.
  ///
  /// In en, this message translates to:
  /// **'ETA from (min)'**
  String get etaFromMin;

  /// No description provided for @etaToMin.
  ///
  /// In en, this message translates to:
  /// **'ETA to (min)'**
  String get etaToMin;

  /// No description provided for @serverAppliesTerms.
  ///
  /// In en, this message translates to:
  /// **'Both are applied by the server when an order is placed — a basket under the minimum is refused, and the fee is added to the customer\'s total.'**
  String get serverAppliesTerms;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening hours'**
  String get openingHours;

  /// No description provided for @openingHoursBlurb.
  ///
  /// In en, this message translates to:
  /// **'Your shop shows as Open, Closing soon or Closed based on these'**
  String get openingHoursBlurb;

  /// No description provided for @addASecondWindow.
  ///
  /// In en, this message translates to:
  /// **'Add a second window'**
  String get addASecondWindow;

  /// No description provided for @secondWindowBlurb.
  ///
  /// In en, this message translates to:
  /// **'Add a second window for a day to split your hours — for example a morning service and an evening one, closed in between.'**
  String get secondWindowBlurb;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @listedOnStorefront.
  ///
  /// In en, this message translates to:
  /// **'Listed on the storefront'**
  String get listedOnStorefront;

  /// No description provided for @notListedYet.
  ///
  /// In en, this message translates to:
  /// **'Not listed yet'**
  String get notListedYet;

  /// No description provided for @markedBusy30.
  ///
  /// In en, this message translates to:
  /// **'Marked busy for 30 minutes'**
  String get markedBusy30;

  /// No description provided for @busy30m.
  ///
  /// In en, this message translates to:
  /// **'Busy 30m'**
  String get busy30m;

  /// No description provided for @noLongerBusy.
  ///
  /// In en, this message translates to:
  /// **'No longer marked busy'**
  String get noLongerBusy;

  /// No description provided for @notBusy.
  ///
  /// In en, this message translates to:
  /// **'Not busy'**
  String get notBusy;

  /// No description provided for @yourShopIsLive.
  ///
  /// In en, this message translates to:
  /// **'Your shop is live'**
  String get yourShopIsLive;

  /// No description provided for @opens.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get opens;

  /// No description provided for @closes.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get closes;

  /// No description provided for @removeThisWindow.
  ///
  /// In en, this message translates to:
  /// **'Remove this window'**
  String get removeThisWindow;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @labelRemoved.
  ///
  /// In en, this message translates to:
  /// **'{label} removed'**
  String labelRemoved(String label);

  /// No description provided for @pictureUpdated.
  ///
  /// In en, this message translates to:
  /// **'Picture updated'**
  String get pictureUpdated;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @aNumber.
  ///
  /// In en, this message translates to:
  /// **'A number'**
  String get aNumber;

  /// No description provided for @cannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Cannot be negative'**
  String get cannotBeNegative;

  /// No description provided for @signInFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get signInFailedShort;

  /// No description provided for @providerKindInHouse.
  ///
  /// In en, this message translates to:
  /// **'In-house'**
  String get providerKindInHouse;

  /// No description provided for @providerKindCompany.
  ///
  /// In en, this message translates to:
  /// **'Delivery company'**
  String get providerKindCompany;

  /// No description provided for @providerKindOwnDrivers.
  ///
  /// In en, this message translates to:
  /// **'Own drivers'**
  String get providerKindOwnDrivers;

  /// No description provided for @carrierPortal.
  ///
  /// In en, this message translates to:
  /// **'Carrier Portal'**
  String get carrierPortal;

  /// No description provided for @carrierPortalTagline.
  ///
  /// In en, this message translates to:
  /// **'Your company, your fleet and how much work you are offered.'**
  String get carrierPortalTagline;

  /// No description provided for @notACarrier.
  ///
  /// In en, this message translates to:
  /// **'This account is not registered to a delivery company.'**
  String get notACarrier;

  /// No description provided for @noCompanyYet.
  ///
  /// In en, this message translates to:
  /// **'No company attached to this account yet'**
  String get noCompanyYet;

  /// No description provided for @askThePlatformToAttachYou.
  ///
  /// In en, this message translates to:
  /// **'Ask the platform to attach you to your delivery company.'**
  String get askThePlatformToAttachYou;

  /// No description provided for @howYouAreDoing.
  ///
  /// In en, this message translates to:
  /// **'How you are doing'**
  String get howYouAreDoing;

  /// No description provided for @deliveryScore.
  ///
  /// In en, this message translates to:
  /// **'Delivery score'**
  String get deliveryScore;

  /// No description provided for @tooEarlyToTell.
  ///
  /// In en, this message translates to:
  /// **'too early to tell'**
  String get tooEarlyToTell;

  /// No description provided for @ordersDelivered.
  ///
  /// In en, this message translates to:
  /// **'Orders delivered'**
  String get ordersDelivered;

  /// No description provided for @timeToClaim.
  ///
  /// In en, this message translates to:
  /// **'Time to claim'**
  String get timeToClaim;

  /// No description provided for @timeOnTheRoad.
  ///
  /// In en, this message translates to:
  /// **'Time on the road'**
  String get timeOnTheRoad;

  /// No description provided for @scoreBlurb.
  ///
  /// In en, this message translates to:
  /// **'This score decides how much work you are offered when a merchant lets the platform choose. Delivering what you take matters most; claiming promptly comes next.'**
  String get scoreBlurb;

  /// No description provided for @scoreProvisionalBlurb.
  ///
  /// In en, this message translates to:
  /// **'You are still being given work on the benefit of the doubt. The score becomes yours rather than an assumption once you have a few more orders behind you.'**
  String get scoreProvisionalBlurb;

  /// No description provided for @takingOrders.
  ///
  /// In en, this message translates to:
  /// **'Taking orders'**
  String get takingOrders;

  /// No description provided for @takingWork.
  ///
  /// In en, this message translates to:
  /// **'Taking work'**
  String get takingWork;

  /// No description provided for @youAreTakingOrders.
  ///
  /// In en, this message translates to:
  /// **'You are taking orders'**
  String get youAreTakingOrders;

  /// No description provided for @youAreNotTakingOrders.
  ///
  /// In en, this message translates to:
  /// **'You are not taking orders'**
  String get youAreNotTakingOrders;

  /// No description provided for @pauseExplanation.
  ///
  /// In en, this message translates to:
  /// **'Pausing stops new orders being sent to you. Anything already assigned to your riders is unaffected.'**
  String get pauseExplanation;

  /// No description provided for @suspendedByPlatform.
  ///
  /// In en, this message translates to:
  /// **'The platform has suspended your company. You cannot resume yourself — talk to the platform.'**
  String get suspendedByPlatform;

  /// No description provided for @pauseNewOrders.
  ///
  /// In en, this message translates to:
  /// **'Pause new orders'**
  String get pauseNewOrders;

  /// No description provided for @startTakingOrders.
  ///
  /// In en, this message translates to:
  /// **'Start taking orders'**
  String get startTakingOrders;

  /// No description provided for @pausedNoNewOrders.
  ///
  /// In en, this message translates to:
  /// **'Paused. No new orders will be sent to you.'**
  String get pausedNoNewOrders;

  /// No description provided for @resumedTakingOrders.
  ///
  /// In en, this message translates to:
  /// **'You are taking orders again.'**
  String get resumedTakingOrders;

  /// No description provided for @yourFleet.
  ///
  /// In en, this message translates to:
  /// **'Your fleet'**
  String get yourFleet;

  /// No description provided for @noRidersBlurb.
  ///
  /// In en, this message translates to:
  /// **'You have no riders. Your company looks available and can collect nothing, which is the most confusing way to be sent no work — ask the platform to add your riders.'**
  String get noRidersBlurb;

  /// No description provided for @ridersAddedByPlatform.
  ///
  /// In en, this message translates to:
  /// **'Riders are added to your fleet by the platform.'**
  String get ridersAddedByPlatform;

  /// No description provided for @gettingPaid.
  ///
  /// In en, this message translates to:
  /// **'Getting paid'**
  String get gettingPaid;

  /// No description provided for @noPayoutAccount.
  ///
  /// In en, this message translates to:
  /// **'No payout account on file'**
  String get noPayoutAccount;

  /// No description provided for @payoutNeedsAttentionBlurb.
  ///
  /// In en, this message translates to:
  /// **'The bank has not confirmed this account. Payments to you may fail — the platform can re-check it.'**
  String get payoutNeedsAttentionBlurb;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @pickYourArea.
  ///
  /// In en, this message translates to:
  /// **'Pick your area so we know who can reach you'**
  String get pickYourArea;

  /// No description provided for @feeToArea.
  ///
  /// In en, this message translates to:
  /// **'Delivery to {area}: {fee}'**
  String feeToArea(String area, String fee);

  /// No description provided for @doesNotDeliverToArea.
  ///
  /// In en, this message translates to:
  /// **'This shop does not deliver to {area}'**
  String doesNotDeliverToArea(String area);

  /// No description provided for @deliveryAreas.
  ///
  /// In en, this message translates to:
  /// **'Delivery areas'**
  String get deliveryAreas;

  /// No description provided for @whereYouDeliver.
  ///
  /// In en, this message translates to:
  /// **'Where you deliver, and what you charge to get there'**
  String get whereYouDeliver;

  /// No description provided for @flatFeeEverywhere.
  ///
  /// In en, this message translates to:
  /// **'You charge one fee everywhere'**
  String get flatFeeEverywhere;

  /// No description provided for @flatFeeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Add an area below to charge by distance instead. Until you add one, every order costs your standard delivery fee and you deliver anywhere.'**
  String get flatFeeExplanation;

  /// No description provided for @addAnArea.
  ///
  /// In en, this message translates to:
  /// **'Add an area'**
  String get addAnArea;

  /// No description provided for @feeToHere.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get feeToHere;

  /// No description provided for @minimumHere.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get minimumHere;

  /// No description provided for @extraMinutes.
  ///
  /// In en, this message translates to:
  /// **'Extra minutes'**
  String get extraMinutes;

  /// No description provided for @usesShopMinimum.
  ///
  /// In en, this message translates to:
  /// **'uses your shop minimum'**
  String get usesShopMinimum;

  /// No description provided for @stopDelivering.
  ///
  /// In en, this message translates to:
  /// **'Stop delivering here'**
  String get stopDelivering;

  /// No description provided for @areasYouServe.
  ///
  /// In en, this message translates to:
  /// **'Areas you deliver to'**
  String get areasYouServe;

  /// No description provided for @onlyTheseAreas.
  ///
  /// In en, this message translates to:
  /// **'You deliver only to the areas listed here. Orders from anywhere else are refused.'**
  String get onlyTheseAreas;

  /// No description provided for @manageAreas.
  ///
  /// In en, this message translates to:
  /// **'Delivery areas'**
  String get manageAreas;

  /// No description provided for @manageAreasBlurb.
  ///
  /// In en, this message translates to:
  /// **'The list customers pick from when they enter an address. Shops price their delivery per area.'**
  String get manageAreasBlurb;

  /// No description provided for @newArea.
  ///
  /// In en, this message translates to:
  /// **'New area'**
  String get newArea;

  /// No description provided for @areaName.
  ///
  /// In en, this message translates to:
  /// **'Area name'**
  String get areaName;

  /// No description provided for @regionOptional.
  ///
  /// In en, this message translates to:
  /// **'Region (optional)'**
  String get regionOptional;

  /// No description provided for @sortOrder.
  ///
  /// In en, this message translates to:
  /// **'Order in the list'**
  String get sortOrder;

  /// No description provided for @retire.
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get retire;

  /// No description provided for @reinstate.
  ///
  /// In en, this message translates to:
  /// **'Reinstate'**
  String get reinstate;

  /// No description provided for @retired.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get retired;

  /// No description provided for @retiredExplanation.
  ///
  /// In en, this message translates to:
  /// **'Retired areas leave the picker but keep working for addresses that already name them.'**
  String get retiredExplanation;

  /// No description provided for @noAreasYet.
  ///
  /// In en, this message translates to:
  /// **'No areas yet'**
  String get noAreasYet;

  /// No description provided for @noAreasBlurb.
  ///
  /// In en, this message translates to:
  /// **'Until you add areas, every shop charges one delivery fee and delivers anywhere.'**
  String get noAreasBlurb;

  /// No description provided for @navWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get navWhatsApp;

  /// No description provided for @whatsappInbox.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp inbox'**
  String get whatsappInbox;

  /// No description provided for @whatsappInboxBlurb.
  ///
  /// In en, this message translates to:
  /// **'Customers who message your shop. Turn what they asked for into an order without leaving this screen.'**
  String get whatsappInboxBlurb;

  /// No description provided for @noConversations.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noConversations;

  /// No description provided for @noConversationsBlurb.
  ///
  /// In en, this message translates to:
  /// **'When a customer messages your connected number, the conversation appears here.'**
  String get noConversationsBlurb;

  /// No description provided for @connectedNumbers.
  ///
  /// In en, this message translates to:
  /// **'Connected numbers'**
  String get connectedNumbers;

  /// No description provided for @connectNumber.
  ///
  /// In en, this message translates to:
  /// **'Connect a number'**
  String get connectNumber;

  /// No description provided for @numberId.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp number ID'**
  String get numberId;

  /// No description provided for @numberLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get numberLabel;

  /// No description provided for @displayNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get displayNumber;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @disconnectNumberWarning.
  ///
  /// In en, this message translates to:
  /// **'New messages to this number stop arriving. Your existing conversations are kept.'**
  String get disconnectNumberWarning;

  /// No description provided for @noNumbersYet.
  ///
  /// In en, this message translates to:
  /// **'No number connected'**
  String get noNumbersYet;

  /// No description provided for @noNumbersBlurb.
  ///
  /// In en, this message translates to:
  /// **'Connect the WhatsApp number your customers already write to.'**
  String get noNumbersBlurb;

  /// No description provided for @selectAConversation.
  ///
  /// In en, this message translates to:
  /// **'Pick a conversation'**
  String get selectAConversation;

  /// No description provided for @selectAConversationBlurb.
  ///
  /// In en, this message translates to:
  /// **'Choose someone on the left to read what they asked for.'**
  String get selectAConversationBlurb;

  /// No description provided for @showArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived'**
  String get showArchived;

  /// No description provided for @showActive.
  ///
  /// In en, this message translates to:
  /// **'Show active'**
  String get showActive;

  /// No description provided for @typeAReply.
  ///
  /// In en, this message translates to:
  /// **'Write a reply'**
  String get typeAReply;

  /// No description provided for @sendReply.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendReply;

  /// No description provided for @replyNotSent.
  ///
  /// In en, this message translates to:
  /// **'Saved, but it could not be sent'**
  String get replyNotSent;

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNote;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @locationPin.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationPin;

  /// No description provided for @unsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unsupported message'**
  String get unsupportedMessage;

  /// No description provided for @startAnOrder.
  ///
  /// In en, this message translates to:
  /// **'Start an order'**
  String get startAnOrder;

  /// No description provided for @theRequest.
  ///
  /// In en, this message translates to:
  /// **'What they asked for'**
  String get theRequest;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get estimate;

  /// No description provided for @estimateNote.
  ///
  /// In en, this message translates to:
  /// **'An estimate at today’s prices. The final total is calculated when you confirm.'**
  String get estimateNote;

  /// No description provided for @deliveryDetails.
  ///
  /// In en, this message translates to:
  /// **'Delivery details'**
  String get deliveryDetails;

  /// No description provided for @orderNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get orderNotes;

  /// No description provided for @confirmOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm order'**
  String get confirmOrder;

  /// No description provided for @confirmOrderWarning.
  ///
  /// In en, this message translates to:
  /// **'This places a real order and books a rider.'**
  String get confirmOrderWarning;

  /// No description provided for @discardRequest.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardRequest;

  /// No description provided for @orderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Order placed'**
  String get orderPlaced;

  /// No description provided for @draftDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get draftDiscarded;

  /// No description provided for @nothingToOrderYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing added yet'**
  String get nothingToOrderYet;

  /// No description provided for @nothingToOrderYetBlurb.
  ///
  /// In en, this message translates to:
  /// **'Add what the customer asked for from your own menu.'**
  String get nothingToOrderYetBlurb;

  /// No description provided for @chooseOptions.
  ///
  /// In en, this message translates to:
  /// **'Choose options'**
  String get chooseOptions;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @addToOrder.
  ///
  /// In en, this message translates to:
  /// **'Add to order'**
  String get addToOrder;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneLabel;

  /// No description provided for @budgetExhausted.
  ///
  /// In en, this message translates to:
  /// **'The budget is spent. No further waivers will be granted until revenue catches up.'**
  String get budgetExhausted;

  /// No description provided for @deliveryWasFree.
  ///
  /// In en, this message translates to:
  /// **'Normally {amount} — we covered it'**
  String deliveryWasFree(String amount);

  /// No description provided for @noCommissionOnThisOrder.
  ///
  /// In en, this message translates to:
  /// **'No commission on this order'**
  String get noCommissionOnThisOrder;

  /// No description provided for @deliveryPaidByPlatform.
  ///
  /// In en, this message translates to:
  /// **'Delivery paid by the platform'**
  String get deliveryPaidByPlatform;

  /// No description provided for @navCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get navCompany;

  /// No description provided for @navJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get navJobs;

  /// No description provided for @navEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get navEarnings;

  /// No description provided for @jobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your jobs'**
  String get jobsTitle;

  /// No description provided for @jobsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Everything your riders are carrying, and everything they have delivered.'**
  String get jobsBlurb;

  /// No description provided for @noJobsYet.
  ///
  /// In en, this message translates to:
  /// **'No jobs yet'**
  String get noJobsYet;

  /// No description provided for @noJobsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Orders assigned to your company will appear here.'**
  String get noJobsBlurb;

  /// No description provided for @earningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get earningsTitle;

  /// No description provided for @earned.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get earned;

  /// No description provided for @expected.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get expected;

  /// No description provided for @jobsDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get jobsDelivered;

  /// No description provided for @jobsInFlight.
  ///
  /// In en, this message translates to:
  /// **'In flight'**
  String get jobsInFlight;

  /// No description provided for @savedByOffers.
  ///
  /// In en, this message translates to:
  /// **'Saved by offers'**
  String get savedByOffers;

  /// No description provided for @earningsWindowNote.
  ///
  /// In en, this message translates to:
  /// **'Over the last {days} days, after the platform\'s {cut}% share of each delivery fee.'**
  String earningsWindowNote(int days, String cut);

  /// No description provided for @savedByOffersNote.
  ///
  /// In en, this message translates to:
  /// **'The platform waived its share on some of your deliveries, so you kept the whole fee.'**
  String get savedByOffersNote;

  /// No description provided for @expectedNote.
  ///
  /// In en, this message translates to:
  /// **'What the work in flight is worth if it all completes. Not yet owed.'**
  String get expectedNote;

  /// No description provided for @yourFeeOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your fee'**
  String get yourFeeOnThis;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @signInWithAPasscode.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a passcode'**
  String get signInWithAPasscode;

  /// No description provided for @couldNotSignInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in did not complete.'**
  String get couldNotSignInWithGoogle;

  /// No description provided for @enterYourPasscode.
  ///
  /// In en, this message translates to:
  /// **'Enter your passcode'**
  String get enterYourPasscode;

  /// No description provided for @chooseAPasscode.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode'**
  String get chooseAPasscode;

  /// No description provided for @confirmYourPasscode.
  ///
  /// In en, this message translates to:
  /// **'Enter it again'**
  String get confirmYourPasscode;

  /// No description provided for @sixDigitsYouWillUseToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Six digits you will use to sign in'**
  String get sixDigitsYouWillUseToSignIn;

  /// No description provided for @passcodeMustBeSixDigits.
  ///
  /// In en, this message translates to:
  /// **'Your passcode must be six digits.'**
  String get passcodeMustBeSixDigits;

  /// No description provided for @passcodesDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Those did not match. Try again.'**
  String get passcodesDoNotMatch;

  /// No description provided for @merchantHome.
  ///
  /// In en, this message translates to:
  /// **'Your shop'**
  String get merchantHome;

  /// No description provided for @orJoinUs.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orJoinUs;

  /// No description provided for @sellOrDeliverWithUs.
  ///
  /// In en, this message translates to:
  /// **'Sell or deliver with us'**
  String get sellOrDeliverWithUs;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @usernameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get usernameOrEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @noAccountYet.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get noAccountYet;

  /// No description provided for @couldNotReachTheServer.
  ///
  /// In en, this message translates to:
  /// **'We could not reach the server. Check your connection and try again.'**
  String get couldNotReachTheServer;

  /// No description provided for @whatIsYourEmail.
  ///
  /// In en, this message translates to:
  /// **'What\'s your email?'**
  String get whatIsYourEmail;

  /// No description provided for @enterAValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get enterAValidEmail;

  /// No description provided for @lastNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Last name (optional)'**
  String get lastNameOptional;

  /// No description provided for @choosePassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a password'**
  String get choosePassword;

  /// No description provided for @atLeastEightCharacters.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get atLeastEightCharacters;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get passwordTooShort;

  /// No description provided for @deliveryPortal.
  ///
  /// In en, this message translates to:
  /// **'Delivery Portal'**
  String get deliveryPortal;

  /// No description provided for @backoffice.
  ///
  /// In en, this message translates to:
  /// **'Backoffice'**
  String get backoffice;

  /// No description provided for @switchArea.
  ///
  /// In en, this message translates to:
  /// **'Switch portal'**
  String get switchArea;

  /// No description provided for @navCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// No description provided for @navCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get navCatalog;

  /// No description provided for @navBanners.
  ///
  /// In en, this message translates to:
  /// **'Banners'**
  String get navBanners;

  /// No description provided for @navOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Onboarding'**
  String get navOnboarding;

  /// No description provided for @navCarriers.
  ///
  /// In en, this message translates to:
  /// **'Carriers'**
  String get navCarriers;

  /// No description provided for @navAreas.
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get navAreas;

  /// No description provided for @navFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get navFinance;

  /// No description provided for @navOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get navOffers;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @howTradeIsGoing.
  ///
  /// In en, this message translates to:
  /// **'How trade is going'**
  String get howTradeIsGoing;

  /// No description provided for @howWorkIsGoing.
  ///
  /// In en, this message translates to:
  /// **'How the work is going'**
  String get howWorkIsGoing;

  /// No description provided for @ordersToday.
  ///
  /// In en, this message translates to:
  /// **'Orders today'**
  String get ordersToday;

  /// No description provided for @salesToday.
  ///
  /// In en, this message translates to:
  /// **'Sales today'**
  String get salesToday;

  /// No description provided for @jobsToday.
  ///
  /// In en, this message translates to:
  /// **'Jobs today'**
  String get jobsToday;

  /// No description provided for @earnedToday.
  ///
  /// In en, this message translates to:
  /// **'Earned today'**
  String get earnedToday;

  /// No description provided for @upOnYesterday.
  ///
  /// In en, this message translates to:
  /// **'{percent}% up on yesterday'**
  String upOnYesterday(int percent);

  /// No description provided for @downOnYesterday.
  ///
  /// In en, this message translates to:
  /// **'{percent}% down on yesterday'**
  String downOnYesterday(int percent);

  /// No description provided for @sameAsYesterday.
  ///
  /// In en, this message translates to:
  /// **'Same as yesterday'**
  String get sameAsYesterday;

  /// No description provided for @noneYesterday.
  ///
  /// In en, this message translates to:
  /// **'Nothing yesterday'**
  String get noneYesterday;

  /// No description provided for @nothingYetToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet today'**
  String get nothingYetToday;

  /// No description provided for @needsYouNow.
  ///
  /// In en, this message translates to:
  /// **'Needs you now'**
  String get needsYouNow;

  /// No description provided for @toAccept.
  ///
  /// In en, this message translates to:
  /// **'To accept'**
  String get toAccept;

  /// No description provided for @preparingNow.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get preparingNow;

  /// No description provided for @readyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get readyForPickup;

  /// No description provided for @outForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Out for delivery'**
  String get outForDelivery;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting on you.'**
  String get allCaughtUp;

  /// No description provided for @lastDaysHeading.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String lastDaysHeading(int days);

  /// No description provided for @quietSoFar.
  ///
  /// In en, this message translates to:
  /// **'No trade in this period yet.'**
  String get quietSoFar;

  /// No description provided for @noJobsSoFar.
  ///
  /// In en, this message translates to:
  /// **'No jobs in this period yet.'**
  String get noJobsSoFar;

  /// No description provided for @barChartLegend.
  ///
  /// In en, this message translates to:
  /// **'Solid is delivered; pale is placed but not delivered.'**
  String get barChartLegend;

  /// No description provided for @ordersInWindow.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersInWindow;

  /// No description provided for @deliveredInWindow.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get deliveredInWindow;

  /// No description provided for @salesInWindow.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesInWindow;

  /// No description provided for @feesInWindow.
  ///
  /// In en, this message translates to:
  /// **'Platform fees'**
  String get feesInWindow;

  /// No description provided for @feesInWindowNote.
  ///
  /// In en, this message translates to:
  /// **'{cut}% of delivered sales.'**
  String feesInWindowNote(String cut);

  /// No description provided for @bestSellers.
  ///
  /// In en, this message translates to:
  /// **'Best sellers'**
  String get bestSellers;

  /// No description provided for @nothingSoldYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing has sold in this period yet.'**
  String get nothingSoldYet;

  /// No description provided for @soldQty.
  ///
  /// In en, this message translates to:
  /// **'{qty} sold'**
  String soldQty(int qty);

  /// No description provided for @savedForYou.
  ///
  /// In en, this message translates to:
  /// **'Saved by offers'**
  String get savedForYou;

  /// No description provided for @savedForYouNote.
  ///
  /// In en, this message translates to:
  /// **'The platform waived its share on some of your orders.'**
  String get savedForYouNote;

  /// No description provided for @navApplicants.
  ///
  /// In en, this message translates to:
  /// **'Applicants'**
  String get navApplicants;

  /// No description provided for @waitingOnYou.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting on you'**
  String waitingOnYou(int count);

  /// No description provided for @everyoneWhoApplied.
  ///
  /// In en, this message translates to:
  /// **'Everyone who has applied to ride for you.'**
  String get everyoneWhoApplied;

  /// No description provided for @waitingOnly.
  ///
  /// In en, this message translates to:
  /// **'Waiting only'**
  String get waitingOnly;

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @nobodyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Nobody is waiting on you.'**
  String get nobodyWaiting;

  /// No description provided for @nobodyHasApplied.
  ///
  /// In en, this message translates to:
  /// **'Nobody has applied yet.'**
  String get nobodyHasApplied;

  /// No description provided for @hiringAlsoCreatesTheirAccount.
  ///
  /// In en, this message translates to:
  /// **'Adding them creates their account and puts them on your fleet, so they can be sent work straight away.'**
  String get hiringAlsoCreatesTheirAccount;

  /// No description provided for @addToMyFleet.
  ///
  /// In en, this message translates to:
  /// **'Add to my fleet'**
  String get addToMyFleet;

  /// No description provided for @turnDown.
  ///
  /// In en, this message translates to:
  /// **'Turn down'**
  String get turnDown;

  /// No description provided for @turnDownName.
  ///
  /// In en, this message translates to:
  /// **'Turn down {name}'**
  String turnDownName(String name);

  /// No description provided for @theyAreSentThisWordForWord.
  ///
  /// In en, this message translates to:
  /// **'They are sent this word for word. Say what would have to change.'**
  String get theyAreSentThisWordForWord;

  /// No description provided for @riderAdded.
  ///
  /// In en, this message translates to:
  /// **'{name} is on your fleet. We have emailed them how to sign in.'**
  String riderAdded(String name);

  /// No description provided for @applicantTurnedDown.
  ///
  /// In en, this message translates to:
  /// **'{name} has been told.'**
  String applicantTurnedDown(String name);

  /// No description provided for @turnedDownBecause.
  ///
  /// In en, this message translates to:
  /// **'Turned down: {reason}'**
  String turnedDownBecause(String reason);

  /// No description provided for @onYourFleetNow.
  ///
  /// In en, this message translates to:
  /// **'On your fleet. They can be sent work.'**
  String get onYourFleetNow;

  /// No description provided for @thatDidNotGoThrough.
  ///
  /// In en, this message translates to:
  /// **'That did not go through. Try again.'**
  String get thatDidNotGoThrough;

  /// No description provided for @wantToRideForACompany.
  ///
  /// In en, this message translates to:
  /// **'Want to ride for a delivery company?'**
  String get wantToRideForACompany;

  /// No description provided for @rideWithUs.
  ///
  /// In en, this message translates to:
  /// **'Ride with us'**
  String get rideWithUs;

  /// No description provided for @whoWouldYouRideFor.
  ///
  /// In en, this message translates to:
  /// **'Who would you ride for?'**
  String get whoWouldYouRideFor;

  /// No description provided for @theCompanyDecidesNotUs.
  ///
  /// In en, this message translates to:
  /// **'You are applying to the company, not to us. They read it and decide, and we let you know either way.'**
  String get theCompanyDecidesNotUs;

  /// No description provided for @couldNotLoadCompanies.
  ///
  /// In en, this message translates to:
  /// **'We could not load the companies.'**
  String get couldNotLoadCompanies;

  /// No description provided for @nobodyIsHiringRightNow.
  ///
  /// In en, this message translates to:
  /// **'No delivery companies are taking applications right now.'**
  String get nobodyIsHiringRightNow;

  /// No description provided for @aboutYou.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get aboutYou;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @anythingWeShouldKnowRider.
  ///
  /// In en, this message translates to:
  /// **'Anything they should know? (optional)'**
  String get anythingWeShouldKnowRider;

  /// No description provided for @yourEmail.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get yourEmail;

  /// No description provided for @weSendACodeToCheckItReachesYou.
  ///
  /// In en, this message translates to:
  /// **'We send a six-digit code to check it reaches you. Everything after this goes there, including how to sign in.'**
  String get weSendACodeToCheckItReachesYou;

  /// No description provided for @yourPhoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Your phone (optional)'**
  String get yourPhoneOptional;

  /// No description provided for @aNumberHelpsWhenAnOrderNeedsSorting.
  ///
  /// In en, this message translates to:
  /// **'Useful when something about a delivery needs sorting out quickly. Skip it if you would rather not.'**
  String get aNumberHelpsWhenAnOrderNeedsSorting;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @sendAnother.
  ///
  /// In en, this message translates to:
  /// **'Send another'**
  String get sendAnother;

  /// No description provided for @theCodeWeSent.
  ///
  /// In en, this message translates to:
  /// **'The code we sent'**
  String get theCodeWeSent;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @skipThis.
  ///
  /// In en, this message translates to:
  /// **'Skip this'**
  String get skipThis;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @sendApplication.
  ///
  /// In en, this message translates to:
  /// **'Send application'**
  String get sendApplication;

  /// No description provided for @applicationSent.
  ///
  /// In en, this message translates to:
  /// **'Application sent'**
  String get applicationSent;

  /// No description provided for @companyWillBeInTouch.
  ///
  /// In en, this message translates to:
  /// **'{company} will read it and be in touch by email.'**
  String companyWillBeInTouch(String company);

  /// No description provided for @keepThisReference.
  ///
  /// In en, this message translates to:
  /// **'Keep this reference'**
  String get keepThisReference;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get paymentMethod;

  /// No description provided for @cashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get cashOnDelivery;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @payTheRiderWhenItArrives.
  ///
  /// In en, this message translates to:
  /// **'Pay the rider when your order arrives'**
  String get payTheRiderWhenItArrives;

  /// No description provided for @cardNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get cardNotAvailableYet;

  /// No description provided for @paymentDue.
  ///
  /// In en, this message translates to:
  /// **'Due on delivery'**
  String get paymentDue;

  /// No description provided for @paymentAwaitingAuthorisation.
  ///
  /// In en, this message translates to:
  /// **'Awaiting authorisation'**
  String get paymentAwaitingAuthorisation;

  /// No description provided for @paymentAuthorised.
  ///
  /// In en, this message translates to:
  /// **'Authorised'**
  String get paymentAuthorised;

  /// No description provided for @paymentPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paymentPaid;

  /// No description provided for @paymentRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get paymentRefunded;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentFailed;

  /// No description provided for @chooseAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Choose an address'**
  String get chooseAnAddress;

  /// No description provided for @addANewAddress.
  ///
  /// In en, this message translates to:
  /// **'Add a new address'**
  String get addANewAddress;

  /// No description provided for @riderGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String riderGreeting(String name);

  /// No description provided for @riderHeaderLine.
  ///
  /// In en, this message translates to:
  /// **'Here is what is on the board right now.'**
  String get riderHeaderLine;

  /// No description provided for @riderWaitingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String riderWaitingCount(int count);

  /// No description provided for @riderOnTheWayCount.
  ///
  /// In en, this message translates to:
  /// **'{count} on the way'**
  String riderOnTheWayCount(int count);

  /// No description provided for @newJobsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'New jobs land here as soon as a shop marks an order ready.'**
  String get newJobsAppearHere;

  /// No description provided for @claimOneToSeeItHere.
  ///
  /// In en, this message translates to:
  /// **'Claim one from Available and it will show up here.'**
  String get claimOneToSeeItHere;

  /// No description provided for @collectCash.
  ///
  /// In en, this message translates to:
  /// **'Collect {amount} cash'**
  String collectCash(String amount);

  /// No description provided for @alreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'Already paid'**
  String get alreadyPaid;

  /// No description provided for @partnerChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell or deliver with us'**
  String get partnerChoiceTitle;

  /// No description provided for @partnerChoiceIntro.
  ///
  /// In en, this message translates to:
  /// **'Tell us which one you are and we will take you through it.'**
  String get partnerChoiceIntro;

  /// No description provided for @applyAsMerchant.
  ///
  /// In en, this message translates to:
  /// **'Sell on YouDrop'**
  String get applyAsMerchant;

  /// No description provided for @applyAsMerchantBlurb.
  ///
  /// In en, this message translates to:
  /// **'You run a shop and want your products in the app.'**
  String get applyAsMerchantBlurb;

  /// No description provided for @applyAsRider.
  ///
  /// In en, this message translates to:
  /// **'Deliver with YouDrop'**
  String get applyAsRider;

  /// No description provided for @applyAsRiderBlurb.
  ///
  /// In en, this message translates to:
  /// **'You want to carry orders and get paid for each one.'**
  String get applyAsRiderBlurb;

  /// No description provided for @whoWillYouRideFor.
  ///
  /// In en, this message translates to:
  /// **'Who will you ride for?'**
  String get whoWillYouRideFor;

  /// No description provided for @rideForYouDrop.
  ///
  /// In en, this message translates to:
  /// **'YouDrop'**
  String get rideForYouDrop;

  /// No description provided for @rideForYouDropBlurb.
  ///
  /// In en, this message translates to:
  /// **'Join our own fleet. We review your application and we pay you.'**
  String get rideForYouDropBlurb;

  /// No description provided for @rideForACompany.
  ///
  /// In en, this message translates to:
  /// **'A delivery company'**
  String get rideForACompany;

  /// No description provided for @rideForACompanyBlurb.
  ///
  /// In en, this message translates to:
  /// **'Apply to one of the companies below. They decide, not us.'**
  String get rideForACompanyBlurb;

  /// No description provided for @yourBusiness.
  ///
  /// In en, this message translates to:
  /// **'Your business'**
  String get yourBusiness;

  /// No description provided for @businessName.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get businessName;

  /// No description provided for @theNameCustomersWillSee.
  ///
  /// In en, this message translates to:
  /// **'The name customers will see in the app.'**
  String get theNameCustomersWillSee;

  /// No description provided for @yourNameAsOwner.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourNameAsOwner;

  /// No description provided for @anythingWeShouldKnowMerchant.
  ///
  /// In en, this message translates to:
  /// **'Anything we should know? (optional)'**
  String get anythingWeShouldKnowMerchant;

  /// No description provided for @weWillBeInTouch.
  ///
  /// In en, this message translates to:
  /// **'We will read it and be in touch by email.'**
  String get weWillBeInTouch;

  /// No description provided for @finishSettingUpInTheApp.
  ///
  /// In en, this message translates to:
  /// **'Set your shop up now and look around. Publishing to the market unlocks once you are approved.'**
  String get finishSettingUpInTheApp;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue without an account'**
  String get continueAsGuest;

  /// No description provided for @guestApplicationExplainer.
  ///
  /// In en, this message translates to:
  /// **'No account needed to apply. You choose a passcode at the end and can sign in straight away, then watch your application while we read it.'**
  String get guestApplicationExplainer;

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {destination}. It expires in 10 minutes and can be used once.'**
  String codeSentTo(String destination);

  /// No description provided for @enterTheCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get enterTheCode;

  /// No description provided for @didntGetIt.
  ///
  /// In en, this message translates to:
  /// **'Did not get it?'**
  String get didntGetIt;

  /// No description provided for @yourApplicationReference.
  ///
  /// In en, this message translates to:
  /// **'Your application reference'**
  String get yourApplicationReference;

  /// No description provided for @referenceExplainer.
  ///
  /// In en, this message translates to:
  /// **'Quote this if you contact us, and use it to check your application at any time. It is not a password and it is not needed to sign in.'**
  String get referenceExplainer;

  /// No description provided for @unlockWithFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint'**
  String get unlockWithFingerprint;

  /// No description provided for @useFingerprintNextTime.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint next time'**
  String get useFingerprintNextTime;

  /// No description provided for @fingerprintKeepsYourAccountClosed.
  ///
  /// In en, this message translates to:
  /// **'Your session stays locked until you unlock it, so someone holding your phone cannot open your account.'**
  String get fingerprintKeepsYourAccountClosed;

  /// No description provided for @fingerprintNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'No fingerprint or face is set up on this phone yet. Add one in Android Settings, under Biometrics, then come back.'**
  String get fingerprintNotSetUp;

  /// No description provided for @couldNotVerifyYou.
  ///
  /// In en, this message translates to:
  /// **'We could not verify you. Try again, or sign in with your passcode.'**
  String get couldNotVerifyYou;

  /// No description provided for @signInWithPasscodeInstead.
  ///
  /// In en, this message translates to:
  /// **'Use my passcode instead'**
  String get signInWithPasscodeInstead;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock'**
  String get biometricUnlock;

  /// No description provided for @chooseYourPasscode.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode'**
  String get chooseYourPasscode;

  /// No description provided for @passcodeLetsYouFollowIt.
  ///
  /// In en, this message translates to:
  /// **'Six digits. You will use them to sign in and follow your application while we read it.'**
  String get passcodeLetsYouFollowIt;

  /// No description provided for @applicationPending.
  ///
  /// In en, this message translates to:
  /// **'Application received'**
  String get applicationPending;

  /// No description provided for @weAreReadingIt.
  ///
  /// In en, this message translates to:
  /// **'We are reading your application. You will get an email as soon as there is a decision, and this screen keeps the status.'**
  String get weAreReadingIt;

  /// No description provided for @companyIsReadingIt.
  ///
  /// In en, this message translates to:
  /// **'{company} is reading your application. You will get an email as soon as they decide.'**
  String companyIsReadingIt(String company);

  /// No description provided for @applicationStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get applicationStatus;

  /// No description provided for @statusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be read'**
  String get statusSubmitted;

  /// No description provided for @statusInReview.
  ///
  /// In en, this message translates to:
  /// **'Being read now'**
  String get statusInReview;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved — setting up your account'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Not accepted'**
  String get statusRejected;

  /// No description provided for @statusProvisioned.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusProvisioned;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong setting you up. We are on it.'**
  String get statusFailed;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @whatHappensNext.
  ///
  /// In en, this message translates to:
  /// **'What happens next'**
  String get whatHappensNext;

  /// No description provided for @nextStepsPending.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do for now. When you are approved this app becomes your shop or your job board — same sign-in, same passcode.'**
  String get nextStepsPending;

  /// No description provided for @couldNotCreateSignIn.
  ///
  /// In en, this message translates to:
  /// **'We could not set up your sign-in. Your application was still received.'**
  String get couldNotCreateSignIn;

  /// No description provided for @pendingBannerMerchant.
  ///
  /// In en, this message translates to:
  /// **'Your application is being reviewed. Set your shop up now — you can publish to the market once you are approved.'**
  String get pendingBannerMerchant;

  /// No description provided for @pendingBannerRider.
  ///
  /// In en, this message translates to:
  /// **'Your application is being reviewed. Look around the board — you can take deliveries once you are approved.'**
  String get pendingBannerRider;

  /// No description provided for @notWhilePending.
  ///
  /// In en, this message translates to:
  /// **'You can do this once your application is approved.'**
  String get notWhilePending;

  /// No description provided for @viewApplication.
  ///
  /// In en, this message translates to:
  /// **'View application'**
  String get viewApplication;

  /// No description provided for @accountReadySignInInstead.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready, but signing you in did not work. Close this and sign in with your email and the passcode you just chose.'**
  String get accountReadySignInInstead;

  /// No description provided for @dayByDay.
  ///
  /// In en, this message translates to:
  /// **'Day by day'**
  String get dayByDay;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Anything delivered, anywhere'**
  String get authTagline;

  /// No description provided for @authRoleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get authRoleCustomer;

  /// No description provided for @authRoleCustomerBlurb.
  ///
  /// In en, this message translates to:
  /// **'Order and get deliveries'**
  String get authRoleCustomerBlurb;

  /// No description provided for @authRoleRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get authRoleRider;

  /// No description provided for @authRoleRiderBlurb.
  ///
  /// In en, this message translates to:
  /// **'Deliver and earn'**
  String get authRoleRiderBlurb;

  /// No description provided for @authRoleMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get authRoleMerchant;

  /// No description provided for @authRoleMerchantBlurb.
  ///
  /// In en, this message translates to:
  /// **'Sell and grow your business'**
  String get authRoleMerchantBlurb;

  /// No description provided for @authJoinYoudrop.
  ///
  /// In en, this message translates to:
  /// **'Join YouDrop'**
  String get authJoinYoudrop;

  /// No description provided for @authChooseHowToUse.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to use YouDrop'**
  String get authChooseHowToUse;

  /// No description provided for @authRolePopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get authRolePopular;

  /// No description provided for @authRoleWantOrder.
  ///
  /// In en, this message translates to:
  /// **'I want to Order'**
  String get authRoleWantOrder;

  /// No description provided for @authRoleWantOrderBlurb.
  ///
  /// In en, this message translates to:
  /// **'Get food, groceries & parcels delivered fast'**
  String get authRoleWantOrderBlurb;

  /// No description provided for @authRoleWantDeliver.
  ///
  /// In en, this message translates to:
  /// **'I want to Deliver'**
  String get authRoleWantDeliver;

  /// No description provided for @authRoleWantDeliverBlurb.
  ///
  /// In en, this message translates to:
  /// **'Drive on your schedule, keep 100% of tips'**
  String get authRoleWantDeliverBlurb;

  /// No description provided for @authRoleWantSell.
  ///
  /// In en, this message translates to:
  /// **'I want to Sell'**
  String get authRoleWantSell;

  /// No description provided for @authRoleWantSellBlurb.
  ///
  /// In en, this message translates to:
  /// **'Grow your restaurant or store business'**
  String get authRoleWantSellBlurb;

  /// No description provided for @riderIntroHeader.
  ///
  /// In en, this message translates to:
  /// **'Apply as Partner'**
  String get riderIntroHeader;

  /// No description provided for @riderIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Earn on Your Schedule'**
  String get riderIntroTitle;

  /// No description provided for @riderIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Lebanon\'s premier delivery fleet. Drive a scooter, motorcycle or car, and start earning today.'**
  String get riderIntroSubtitle;

  /// No description provided for @riderPerk1Title.
  ///
  /// In en, this message translates to:
  /// **'Drive on Your Own Time'**
  String get riderPerk1Title;

  /// No description provided for @riderPerk1Body.
  ///
  /// In en, this message translates to:
  /// **'No minimum hours, completely flexible shifts.'**
  String get riderPerk1Body;

  /// No description provided for @riderPerk2Title.
  ///
  /// In en, this message translates to:
  /// **'Fast Payouts in Cash & USD'**
  String get riderPerk2Title;

  /// No description provided for @riderPerk2Body.
  ///
  /// In en, this message translates to:
  /// **'Get paid daily or weekly directly in fresh cash.'**
  String get riderPerk2Body;

  /// No description provided for @riderPerk3Title.
  ///
  /// In en, this message translates to:
  /// **'Rider Fuel Rewards'**
  String get riderPerk3Title;

  /// No description provided for @riderPerk3Body.
  ///
  /// In en, this message translates to:
  /// **'Access discounted fuel partners across Lebanon.'**
  String get riderPerk3Body;

  /// No description provided for @applyToDeliver.
  ///
  /// In en, this message translates to:
  /// **'Apply to Deliver'**
  String get applyToDeliver;

  /// No description provided for @merchantIntroHeader.
  ///
  /// In en, this message translates to:
  /// **'Grow with Us'**
  String get merchantIntroHeader;

  /// No description provided for @merchantIntroHeaderLogin.
  ///
  /// In en, this message translates to:
  /// **'Partner already?'**
  String get merchantIntroHeaderLogin;

  /// No description provided for @merchantIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Grow Your Business'**
  String get merchantIntroTitle;

  /// No description provided for @merchantIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Partner with YouDrop and offer fast delivery or takeout to residents across Beirut and Lebanon.'**
  String get merchantIntroSubtitle;

  /// No description provided for @merchantBenefit1Title.
  ///
  /// In en, this message translates to:
  /// **'Reach 50,000+ Customers'**
  String get merchantBenefit1Title;

  /// No description provided for @merchantBenefit1Body.
  ///
  /// In en, this message translates to:
  /// **'Instant visibility to hungry customers in your radius.'**
  String get merchantBenefit1Body;

  /// No description provided for @merchantBenefit2Title.
  ///
  /// In en, this message translates to:
  /// **'Zero Setup Fee & Easy Menus'**
  String get merchantBenefit2Title;

  /// No description provided for @merchantBenefit2Body.
  ///
  /// In en, this message translates to:
  /// **'Our team builds and styles your online menu or store catalog.'**
  String get merchantBenefit2Body;

  /// No description provided for @merchantBenefit3Title.
  ///
  /// In en, this message translates to:
  /// **'Direct Payouts & Dashboard'**
  String get merchantBenefit3Title;

  /// No description provided for @merchantBenefit3Body.
  ///
  /// In en, this message translates to:
  /// **'Track sales, orders, and withdraw cash in real-time.'**
  String get merchantBenefit3Body;

  /// No description provided for @registerStoreNow.
  ///
  /// In en, this message translates to:
  /// **'Register Store Now'**
  String get registerStoreNow;

  /// No description provided for @authAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authAlreadyHaveAnAccount;

  /// No description provided for @authDontHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authDontHaveAnAccount;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authSignUp;

  /// No description provided for @authSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter your credentials to log in.'**
  String get authSignInSubtitle;

  /// No description provided for @authSignInAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your YouDrop account'**
  String get authSignInAccountSubtitle;

  /// No description provided for @authTaglineLebanon.
  ///
  /// In en, this message translates to:
  /// **'Deliver everything in Lebanon'**
  String get authTaglineLebanon;

  /// No description provided for @authLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get authLogIn;

  /// No description provided for @authForgotShort.
  ///
  /// In en, this message translates to:
  /// **'Forgot?'**
  String get authForgotShort;

  /// No description provided for @authSocialComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{provider} sign-in is coming soon.'**
  String authSocialComingSoon(String provider);

  /// No description provided for @authStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String authStepOf(int current, int total);

  /// No description provided for @authEmailOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Email or Phone'**
  String get authEmailOrPhone;

  /// No description provided for @authEmailOrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. name@domain.com or +961…'**
  String get authEmailOrPhoneHint;

  /// No description provided for @authPasscodeHint.
  ///
  /// In en, this message translates to:
  /// **'Your six-digit passcode'**
  String get authPasscodeHint;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authUseTheKeypad.
  ///
  /// In en, this message translates to:
  /// **'Use the keypad'**
  String get authUseTheKeypad;

  /// No description provided for @authOrContinueWith.
  ///
  /// In en, this message translates to:
  /// **'Or continue with'**
  String get authOrContinueWith;

  /// No description provided for @authComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get authComingSoon;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show passcode'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide passcode'**
  String get authHidePassword;

  /// No description provided for @authDeleteDigit.
  ///
  /// In en, this message translates to:
  /// **'Delete last digit'**
  String get authDeleteDigit;

  /// No description provided for @authCreateAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start getting anything delivered anywhere.'**
  String get authCreateAccountSubtitle;

  /// No description provided for @authFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// No description provided for @authFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sarah Jenkins'**
  String get authFullNameHint;

  /// No description provided for @authEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get authEmailAddress;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. sarah.j@gmail.com'**
  String get authEmailHint;

  /// No description provided for @authPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get authPhoneNumber;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'70 123 456'**
  String get authPhoneHint;

  /// No description provided for @authConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm passcode'**
  String get authConfirmPassword;

  /// No description provided for @authPasscodeKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get authPasscodeKeepGoing;

  /// No description provided for @authPasscodeComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get authPasscodeComplete;

  /// No description provided for @authAgreeToTerms.
  ///
  /// In en, this message translates to:
  /// **'I agree to the terms and the privacy policy'**
  String get authAgreeToTerms;

  /// No description provided for @authTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'By signing up, you agree to our '**
  String get authTermsPrefix;

  /// No description provided for @authTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get authTermsOfService;

  /// No description provided for @authTermsAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get authTermsAnd;

  /// No description provided for @authPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get authPrivacyPolicy;

  /// No description provided for @authPleaseAcceptTheTerms.
  ///
  /// In en, this message translates to:
  /// **'Please accept the terms to continue.'**
  String get authPleaseAcceptTheTerms;

  /// No description provided for @authVerifyYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyYourEmail;

  /// No description provided for @authVerifyYourNumber.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get authVerifyYourNumber;

  /// No description provided for @authStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get authStep;

  /// No description provided for @authComplete.
  ///
  /// In en, this message translates to:
  /// **'complete'**
  String get authComplete;

  /// No description provided for @authNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get authNext;

  /// No description provided for @authGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get authGetStarted;

  /// No description provided for @authSubmitApplication.
  ///
  /// In en, this message translates to:
  /// **'Submit application'**
  String get authSubmitApplication;

  /// No description provided for @authSendingApplication.
  ///
  /// In en, this message translates to:
  /// **'Sending your application…'**
  String get authSendingApplication;

  /// No description provided for @authCouldNotSendApplication.
  ///
  /// In en, this message translates to:
  /// **'We could not send your application. Nothing was lost — try again.'**
  String get authCouldNotSendApplication;

  /// No description provided for @authRiderIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Join as a rider'**
  String get authRiderIntroTitle;

  /// No description provided for @authRiderIntroBlurb.
  ///
  /// In en, this message translates to:
  /// **'Flexible hours, competitive pay, and easy navigation — start delivering with YouDrop in a few minutes.'**
  String get authRiderIntroBlurb;

  /// No description provided for @authRiderBenefitHours.
  ///
  /// In en, this message translates to:
  /// **'Flexible hours'**
  String get authRiderBenefitHours;

  /// No description provided for @authRiderBenefitPay.
  ///
  /// In en, this message translates to:
  /// **'Competitive pay'**
  String get authRiderBenefitPay;

  /// No description provided for @authRiderBenefitNavigation.
  ///
  /// In en, this message translates to:
  /// **'Easy navigation'**
  String get authRiderBenefitNavigation;

  /// No description provided for @authWhatYouNeedToSignUp.
  ///
  /// In en, this message translates to:
  /// **'What you\'ll need to sign up'**
  String get authWhatYouNeedToSignUp;

  /// No description provided for @authNeedValidId.
  ///
  /// In en, this message translates to:
  /// **'Valid ID'**
  String get authNeedValidId;

  /// No description provided for @authNeedDriversLicence.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get authNeedDriversLicence;

  /// No description provided for @authNeedVehicleDocuments.
  ///
  /// In en, this message translates to:
  /// **'Vehicle documents'**
  String get authNeedVehicleDocuments;

  /// No description provided for @authMerchantSignUp.
  ///
  /// In en, this message translates to:
  /// **'Merchant sign up'**
  String get authMerchantSignUp;

  /// No description provided for @authMerchantIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Register your business'**
  String get authMerchantIntroTitle;

  /// No description provided for @authMerchantIntroBlurb.
  ///
  /// In en, this message translates to:
  /// **'Reach more customers, manage products easily, and track performance in real time.'**
  String get authMerchantIntroBlurb;

  /// No description provided for @authWhatYouGet.
  ///
  /// In en, this message translates to:
  /// **'What you\'ll get'**
  String get authWhatYouGet;

  /// No description provided for @authMerchantBenefitReach.
  ///
  /// In en, this message translates to:
  /// **'Reach more customers through our delivery network'**
  String get authMerchantBenefitReach;

  /// No description provided for @authMerchantBenefitManage.
  ///
  /// In en, this message translates to:
  /// **'Easy product management and order fulfilment'**
  String get authMerchantBenefitManage;

  /// No description provided for @authMerchantBenefitAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Real-time analytics to optimise your sales'**
  String get authMerchantBenefitAnalytics;

  /// No description provided for @authWhatYouNeed.
  ///
  /// In en, this message translates to:
  /// **'What you\'ll need'**
  String get authWhatYouNeed;

  /// No description provided for @authNeedBusinessLicence.
  ///
  /// In en, this message translates to:
  /// **'Business licence'**
  String get authNeedBusinessLicence;

  /// No description provided for @authNeedTaxCertificate.
  ///
  /// In en, this message translates to:
  /// **'Tax certificate'**
  String get authNeedTaxCertificate;

  /// No description provided for @authNeedBankDetails.
  ///
  /// In en, this message translates to:
  /// **'Bank details'**
  String get authNeedBankDetails;

  /// No description provided for @authPersonalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal information'**
  String get authPersonalInformation;

  /// No description provided for @authPersonalInformationBlurb.
  ///
  /// In en, this message translates to:
  /// **'Please fill in your primary details to establish your rider profile.'**
  String get authPersonalInformationBlurb;

  /// No description provided for @authDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get authDateOfBirth;

  /// No description provided for @authDateOfBirthHint.
  ///
  /// In en, this message translates to:
  /// **'DD / MM / YYYY'**
  String get authDateOfBirthHint;

  /// No description provided for @authNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID number'**
  String get authNationalId;

  /// No description provided for @authNationalIdHint.
  ///
  /// In en, this message translates to:
  /// **'As printed on your ID'**
  String get authNationalIdHint;

  /// No description provided for @authVehicleDetails.
  ///
  /// In en, this message translates to:
  /// **'Vehicle details'**
  String get authVehicleDetails;

  /// No description provided for @authVehicleDetailsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Select your vehicle category and register its official details.'**
  String get authVehicleDetailsBlurb;

  /// No description provided for @authVehicleType.
  ///
  /// In en, this message translates to:
  /// **'Vehicle type'**
  String get authVehicleType;

  /// No description provided for @authVehicleMotorcycle.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get authVehicleMotorcycle;

  /// No description provided for @authVehicleCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get authVehicleCar;

  /// No description provided for @authVehicleBicycle.
  ///
  /// In en, this message translates to:
  /// **'Bicycle'**
  String get authVehicleBicycle;

  /// No description provided for @authVehicleVan.
  ///
  /// In en, this message translates to:
  /// **'Van'**
  String get authVehicleVan;

  /// No description provided for @authVehicleModel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle make / model'**
  String get authVehicleModel;

  /// No description provided for @authVehicleModelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Yamaha TMAX / Toyota Yaris'**
  String get authVehicleModelHint;

  /// No description provided for @authPlateNumber.
  ///
  /// In en, this message translates to:
  /// **'Plate number'**
  String get authPlateNumber;

  /// No description provided for @authPlateNumberHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1234 ABC'**
  String get authPlateNumberHint;

  /// No description provided for @authVehicleYear.
  ///
  /// In en, this message translates to:
  /// **'Vehicle year'**
  String get authVehicleYear;

  /// No description provided for @authVehicleYearHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2024'**
  String get authVehicleYearHint;

  /// No description provided for @authSelectDeliveryZone.
  ///
  /// In en, this message translates to:
  /// **'Select delivery zone'**
  String get authSelectDeliveryZone;

  /// No description provided for @authSelectDeliveryZoneBlurb.
  ///
  /// In en, this message translates to:
  /// **'Which parts of the city do you prefer to deliver in?'**
  String get authSelectDeliveryZoneBlurb;

  /// No description provided for @authMapComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coverage map coming soon'**
  String get authMapComingSoon;

  /// No description provided for @authPreferredArea.
  ///
  /// In en, this message translates to:
  /// **'Preferred area'**
  String get authPreferredArea;

  /// No description provided for @authPreferredAreaHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Hamra, Achrafieh'**
  String get authPreferredAreaHint;

  /// No description provided for @authAvailableZones.
  ///
  /// In en, this message translates to:
  /// **'Available zones'**
  String get authAvailableZones;

  /// No description provided for @authZonesNoneToPickTitle.
  ///
  /// In en, this message translates to:
  /// **'No zones to pick'**
  String get authZonesNoneToPickTitle;

  /// No description provided for @authZonesNoneToPickBlurb.
  ///
  /// In en, this message translates to:
  /// **'Nothing ties a rider to a fixed zone on this platform. The pin you placed and the area you typed above are what a reviewer goes by.'**
  String get authZonesNoneToPickBlurb;

  /// No description provided for @authBusinessInformation.
  ///
  /// In en, this message translates to:
  /// **'Business information'**
  String get authBusinessInformation;

  /// No description provided for @authBusinessInformationBlurb.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your company and the contact person.'**
  String get authBusinessInformationBlurb;

  /// No description provided for @authBusinessShopName.
  ///
  /// In en, this message translates to:
  /// **'Business / shop name'**
  String get authBusinessShopName;

  /// No description provided for @authBusinessShopNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Rose Garden Pizzeria'**
  String get authBusinessShopNameHint;

  /// No description provided for @authOwnerFullName.
  ///
  /// In en, this message translates to:
  /// **'Owner full name'**
  String get authOwnerFullName;

  /// No description provided for @authOwnerFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Jane Cooper'**
  String get authOwnerFullNameHint;

  /// No description provided for @authBusinessType.
  ///
  /// In en, this message translates to:
  /// **'Business type'**
  String get authBusinessType;

  /// No description provided for @authBusinessTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Choose one'**
  String get authBusinessTypeHint;

  /// No description provided for @authBusinessTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get authBusinessTypeRestaurant;

  /// No description provided for @authBusinessTypeGrocery.
  ///
  /// In en, this message translates to:
  /// **'Grocery'**
  String get authBusinessTypeGrocery;

  /// No description provided for @authBusinessTypePharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy'**
  String get authBusinessTypePharmacy;

  /// No description provided for @authBusinessTypeBakery.
  ///
  /// In en, this message translates to:
  /// **'Bakery'**
  String get authBusinessTypeBakery;

  /// No description provided for @authBusinessTypeRetail.
  ///
  /// In en, this message translates to:
  /// **'Retail'**
  String get authBusinessTypeRetail;

  /// No description provided for @authBusinessTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get authBusinessTypeOther;

  /// No description provided for @authContactEmail.
  ///
  /// In en, this message translates to:
  /// **'Contact email address'**
  String get authContactEmail;

  /// No description provided for @authReviewAndSubmit.
  ///
  /// In en, this message translates to:
  /// **'Review and submit'**
  String get authReviewAndSubmit;

  /// No description provided for @authReviewAndSubmitBlurb.
  ///
  /// In en, this message translates to:
  /// **'Check what we are about to send. You can go back and change any of it.'**
  String get authReviewAndSubmitBlurb;

  /// No description provided for @authDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get authDocuments;

  /// No description provided for @authDocumentsBlurb.
  ///
  /// In en, this message translates to:
  /// **'The papers we will need before you can start.'**
  String get authDocumentsBlurb;

  /// No description provided for @authDocumentsComingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Uploading opens shortly'**
  String get authDocumentsComingSoonTitle;

  /// No description provided for @authDocumentsComingSoonBlurb.
  ///
  /// In en, this message translates to:
  /// **'You can finish your application without it — we will ask for the papers by email before you start.'**
  String get authDocumentsComingSoonBlurb;

  /// No description provided for @authBankDetails.
  ///
  /// In en, this message translates to:
  /// **'Bank details'**
  String get authBankDetails;

  /// No description provided for @authBankDetailsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Where your payouts will go.'**
  String get authBankDetailsBlurb;

  /// No description provided for @authBankComingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Payout setup opens shortly'**
  String get authBankComingSoonTitle;

  /// No description provided for @authBankComingSoonBlurb.
  ///
  /// In en, this message translates to:
  /// **'We never take bank details before a decision. You will set payouts up once you are approved.'**
  String get authBankComingSoonBlurb;

  /// No description provided for @authApplicationSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Application submitted'**
  String get authApplicationSubmitted;

  /// No description provided for @authApplicationSubmittedBlurb.
  ///
  /// In en, this message translates to:
  /// **'We have your application and our operations team is reading it now.'**
  String get authApplicationSubmittedBlurb;

  /// No description provided for @authWhatToExpectNext.
  ///
  /// In en, this message translates to:
  /// **'What to expect next'**
  String get authWhatToExpectNext;

  /// No description provided for @authExpectVerification.
  ///
  /// In en, this message translates to:
  /// **'We check your details (1–3 days)'**
  String get authExpectVerification;

  /// No description provided for @authExpectBackgroundCheck.
  ///
  /// In en, this message translates to:
  /// **'Background check'**
  String get authExpectBackgroundCheck;

  /// No description provided for @authExpectTrainingInvite.
  ///
  /// In en, this message translates to:
  /// **'Invitation to rider training'**
  String get authExpectTrainingInvite;

  /// No description provided for @authWeWillNotifyYou.
  ///
  /// In en, this message translates to:
  /// **'We will let you know by email as soon as there is a decision.'**
  String get authWeWillNotifyYou;

  /// No description provided for @authApplicationUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Application under review'**
  String get authApplicationUnderReview;

  /// No description provided for @authApplicationUnderReviewBlurb.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your registration is in and our team is checking it over. This usually takes a day or two.'**
  String get authApplicationUnderReviewBlurb;

  /// No description provided for @authExplorationModeActive.
  ///
  /// In en, this message translates to:
  /// **'Exploration mode is on'**
  String get authExplorationModeActive;

  /// No description provided for @authExplorationModeBlurb.
  ///
  /// In en, this message translates to:
  /// **'While you wait you can set your products and menus up and look around. Nothing goes live until you are approved.'**
  String get authExplorationModeBlurb;

  /// No description provided for @authApplicationChecklist.
  ///
  /// In en, this message translates to:
  /// **'Application checklist'**
  String get authApplicationChecklist;

  /// No description provided for @authChecklistAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get authChecklistAccountCreated;

  /// No description provided for @authChecklistDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents uploaded'**
  String get authChecklistDocuments;

  /// No description provided for @authChecklistAudit.
  ///
  /// In en, this message translates to:
  /// **'Security and compliance check'**
  String get authChecklistAudit;

  /// No description provided for @authChecklistActivation.
  ///
  /// In en, this message translates to:
  /// **'Shop activated and published'**
  String get authChecklistActivation;

  /// No description provided for @authExploreDashboard.
  ///
  /// In en, this message translates to:
  /// **'Explore dashboard'**
  String get authExploreDashboard;

  /// No description provided for @custSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get custSeeAll;

  /// No description provided for @custShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get custShowLess;

  /// No description provided for @custAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get custAllCategories;

  /// No description provided for @custFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get custFilters;

  /// No description provided for @custSearchInCategory.
  ///
  /// In en, this message translates to:
  /// **'Search in {name}'**
  String custSearchInCategory(String name);

  /// No description provided for @custMyBasket.
  ///
  /// In en, this message translates to:
  /// **'My Basket'**
  String get custMyBasket;

  /// No description provided for @custPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Promo Code'**
  String get custPromoCode;

  /// No description provided for @custApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get custApply;

  /// No description provided for @custOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get custOrderSummary;

  /// No description provided for @custDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get custDiscounts;

  /// No description provided for @custTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get custTotalAmount;

  /// No description provided for @custProceedToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Proceed to Checkout'**
  String get custProceedToCheckout;

  /// No description provided for @custAddToBasket.
  ///
  /// In en, this message translates to:
  /// **'Add to Basket'**
  String get custAddToBasket;

  /// No description provided for @custProductDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get custProductDetails;

  /// No description provided for @custYourOrders.
  ///
  /// In en, this message translates to:
  /// **'Your Orders'**
  String get custYourOrders;

  /// No description provided for @custActiveOrdersTab.
  ///
  /// In en, this message translates to:
  /// **'Active Orders ({count})'**
  String custActiveOrdersTab(int count);

  /// No description provided for @custPastOrdersTab.
  ///
  /// In en, this message translates to:
  /// **'Past Orders'**
  String get custPastOrdersTab;

  /// No description provided for @custItemsCountLine.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String custItemsCountLine(int count);

  /// No description provided for @custReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get custReorder;

  /// No description provided for @custActiveStoresNearby.
  ///
  /// In en, this message translates to:
  /// **'Active Stores Nearby'**
  String get custActiveStoresNearby;

  /// No description provided for @custShowingShops.
  ///
  /// In en, this message translates to:
  /// **'Showing {count, plural, =1{1 shop} other{{count} shops}}'**
  String custShowingShops(int count);

  /// No description provided for @custSortFilter.
  ///
  /// In en, this message translates to:
  /// **'Sort / Filter'**
  String get custSortFilter;

  /// No description provided for @custTrackConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get custTrackConfirmed;

  /// No description provided for @custTrackPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get custTrackPreparing;

  /// No description provided for @custTrackOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the Way'**
  String get custTrackOnTheWay;

  /// No description provided for @custTrackDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get custTrackDelivered;

  /// No description provided for @custButlerBanner.
  ///
  /// In en, this message translates to:
  /// **'We buy or deliver anything!'**
  String get custButlerBanner;

  /// No description provided for @custButlerBannerBlurb.
  ///
  /// In en, this message translates to:
  /// **'Forgot something? Need keys retrieved, or shopping from a store not listed? Describe it and a YouDrop rider gets it done.'**
  String get custButlerBannerBlurb;

  /// No description provided for @custPlatformRate.
  ///
  /// In en, this message translates to:
  /// **'Platform Rate: \$1 = {rate} LBP'**
  String custPlatformRate(String rate);

  /// No description provided for @custRateLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked rate — the lira total you approve is the lira total collected.'**
  String get custRateLocked;

  /// No description provided for @custSplitPayment.
  ///
  /// In en, this message translates to:
  /// **'Lebanese Split Payment'**
  String get custSplitPayment;

  /// No description provided for @custSplitBlurb.
  ///
  /// In en, this message translates to:
  /// **'Mix your bills! Pay part in USD cash and the rest in Lebanese Lira.'**
  String get custSplitBlurb;

  /// No description provided for @custPayInUsd.
  ///
  /// In en, this message translates to:
  /// **'Pay in Fresh USD'**
  String get custPayInUsd;

  /// No description provided for @custPayInLbp.
  ///
  /// In en, this message translates to:
  /// **'Pay in LBP (Lira)'**
  String get custPayInLbp;

  /// No description provided for @custRiderChange.
  ///
  /// In en, this message translates to:
  /// **'Rider carries change for up to {amount} LBP and cash USD.'**
  String custRiderChange(String amount);

  /// No description provided for @custLocalPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Local Payment Methods'**
  String get custLocalPaymentMethods;

  /// No description provided for @custCashUsdLbp.
  ///
  /// In en, this message translates to:
  /// **'Cash on Delivery (USD/LBP)'**
  String get custCashUsdLbp;

  /// No description provided for @custWhishTransfer.
  ///
  /// In en, this message translates to:
  /// **'Whish Money Transfer'**
  String get custWhishTransfer;

  /// No description provided for @custOmtTransfer.
  ///
  /// In en, this message translates to:
  /// **'OMT (Online Money Transfer)'**
  String get custOmtTransfer;

  /// No description provided for @custPlaceOrderAmount.
  ///
  /// In en, this message translates to:
  /// **'Place Order ({amount})'**
  String custPlaceOrderAmount(String amount);

  /// No description provided for @custPctUsd.
  ///
  /// In en, this message translates to:
  /// **'{pct}% USD'**
  String custPctUsd(int pct);

  /// No description provided for @custPctLbp.
  ///
  /// In en, this message translates to:
  /// **'{pct}% LBP'**
  String custPctLbp(int pct);

  /// No description provided for @custPowerMains.
  ///
  /// In en, this message translates to:
  /// **'Mains Power'**
  String get custPowerMains;

  /// No description provided for @custPowerGenerator.
  ///
  /// In en, this message translates to:
  /// **'Generator'**
  String get custPowerGenerator;

  /// No description provided for @custPowerDark.
  ///
  /// In en, this message translates to:
  /// **'Currently Dark'**
  String get custPowerDark;

  /// No description provided for @custGeneratorBanner.
  ///
  /// In en, this message translates to:
  /// **'Generator hours — delivery may take longer'**
  String get custGeneratorBanner;

  /// No description provided for @custDarkBanner.
  ///
  /// In en, this message translates to:
  /// **'This shop is dark right now — orders may wait for power'**
  String get custDarkBanner;

  /// No description provided for @custContinueAs.
  ///
  /// In en, this message translates to:
  /// **'Continue as {name}'**
  String custContinueAs(String name);

  /// No description provided for @custNotYou.
  ///
  /// In en, this message translates to:
  /// **'Not you? Sign in with another account'**
  String get custNotYou;

  /// No description provided for @custBioExpired.
  ///
  /// In en, this message translates to:
  /// **'That saved sign-in expired — enter your passcode.'**
  String get custBioExpired;

  /// No description provided for @carrForCarriers.
  ///
  /// In en, this message translates to:
  /// **'For carriers'**
  String get carrForCarriers;

  /// No description provided for @carrPartnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Partner with YouDrop'**
  String get carrPartnerTitle;

  /// No description provided for @carrPartnerBlurb.
  ///
  /// In en, this message translates to:
  /// **'Grow your delivery business across Lebanon with our unified B2B carrier logistics engine.'**
  String get carrPartnerBlurb;

  /// No description provided for @carrBenefitOrders.
  ///
  /// In en, this message translates to:
  /// **'Guaranteed daily orders'**
  String get carrBenefitOrders;

  /// No description provided for @carrBenefitOrdersBlurb.
  ///
  /// In en, this message translates to:
  /// **'Instant access to on-demand local partner streams.'**
  String get carrBenefitOrdersBlurb;

  /// No description provided for @carrBenefitTracking.
  ///
  /// In en, this message translates to:
  /// **'Real-time fleet tracking'**
  String get carrBenefitTracking;

  /// No description provided for @carrBenefitTrackingBlurb.
  ///
  /// In en, this message translates to:
  /// **'Smart dashboard for route optimisation and dispatch.'**
  String get carrBenefitTrackingBlurb;

  /// No description provided for @carrBenefitPayouts.
  ///
  /// In en, this message translates to:
  /// **'Weekly payouts in Fresh USD'**
  String get carrBenefitPayouts;

  /// No description provided for @carrBenefitPayoutsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Reliable financial integrations with instant settlements.'**
  String get carrBenefitPayoutsBlurb;

  /// No description provided for @carrRegisterCompany.
  ///
  /// In en, this message translates to:
  /// **'Register Your Company'**
  String get carrRegisterCompany;

  /// No description provided for @carrChoiceCard.
  ///
  /// In en, this message translates to:
  /// **'I run a delivery company'**
  String get carrChoiceCard;

  /// No description provided for @carrChoiceCardBlurb.
  ///
  /// In en, this message translates to:
  /// **'Bring your fleet and dispatch YouDrop orders'**
  String get carrChoiceCardBlurb;

  /// No description provided for @carrCompanyInformation.
  ///
  /// In en, this message translates to:
  /// **'Company Information'**
  String get carrCompanyInformation;

  /// No description provided for @carrCompanyInformationBlurb.
  ///
  /// In en, this message translates to:
  /// **'Who the platform is signing with.'**
  String get carrCompanyInformationBlurb;

  /// No description provided for @carrCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get carrCompanyName;

  /// No description provided for @carrCompanyNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Beirut Express Delivery'**
  String get carrCompanyNameHint;

  /// No description provided for @carrCrNumber.
  ///
  /// In en, this message translates to:
  /// **'Commercial Registration (CR) Number'**
  String get carrCrNumber;

  /// No description provided for @carrCompanyType.
  ///
  /// In en, this message translates to:
  /// **'Company Type'**
  String get carrCompanyType;

  /// No description provided for @carrFleetSizeBand.
  ///
  /// In en, this message translates to:
  /// **'Fleet Size'**
  String get carrFleetSizeBand;

  /// No description provided for @carrCoverageArea.
  ///
  /// In en, this message translates to:
  /// **'Coverage Area (Lebanon)'**
  String get carrCoverageArea;

  /// No description provided for @carrContactPerson.
  ///
  /// In en, this message translates to:
  /// **'Contact Person'**
  String get carrContactPerson;

  /// No description provided for @carrFleetDetails.
  ///
  /// In en, this message translates to:
  /// **'Fleet & Vehicle Details'**
  String get carrFleetDetails;

  /// No description provided for @carrFleetDetailsBlurb.
  ///
  /// In en, this message translates to:
  /// **'What your fleet can actually carry.'**
  String get carrFleetDetailsBlurb;

  /// No description provided for @carrActiveVehicles.
  ///
  /// In en, this message translates to:
  /// **'Active vehicles count'**
  String get carrActiveVehicles;

  /// No description provided for @carrMotorcycles.
  ///
  /// In en, this message translates to:
  /// **'Motorcycles'**
  String get carrMotorcycles;

  /// No description provided for @carrCars.
  ///
  /// In en, this message translates to:
  /// **'Cars'**
  String get carrCars;

  /// No description provided for @carrVans.
  ///
  /// In en, this message translates to:
  /// **'Vans'**
  String get carrVans;

  /// No description provided for @carrTrucks.
  ///
  /// In en, this message translates to:
  /// **'Trucks'**
  String get carrTrucks;

  /// No description provided for @carrOperatingHours.
  ///
  /// In en, this message translates to:
  /// **'Operating hours'**
  String get carrOperatingHours;

  /// No description provided for @carrWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get carrWeekdays;

  /// No description provided for @carrWeekends.
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get carrWeekends;

  /// No description provided for @carrCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Fleet capabilities'**
  String get carrCapabilities;

  /// No description provided for @carrCapColdChain.
  ///
  /// In en, this message translates to:
  /// **'Generator-equipped cold chain'**
  String get carrCapColdChain;

  /// No description provided for @carrCapFood.
  ///
  /// In en, this message translates to:
  /// **'Food Delivery Support'**
  String get carrCapFood;

  /// No description provided for @carrCapGrocery.
  ///
  /// In en, this message translates to:
  /// **'Grocery Delivery Support'**
  String get carrCapGrocery;

  /// No description provided for @carrCapPharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy Delivery Support'**
  String get carrCapPharmacy;

  /// No description provided for @carrCapParcel.
  ///
  /// In en, this message translates to:
  /// **'Parcel Delivery Support'**
  String get carrCapParcel;

  /// No description provided for @carrCapButler.
  ///
  /// In en, this message translates to:
  /// **'Custom Butler services'**
  String get carrCapButler;

  /// No description provided for @carrPayoutSetup.
  ///
  /// In en, this message translates to:
  /// **'Payout & Financial Setup'**
  String get carrPayoutSetup;

  /// No description provided for @carrPayoutSetupBlurb.
  ///
  /// In en, this message translates to:
  /// **'How your company gets paid.'**
  String get carrPayoutSetupBlurb;

  /// No description provided for @carrCommissionRate.
  ///
  /// In en, this message translates to:
  /// **'Commission rate'**
  String get carrCommissionRate;

  /// No description provided for @carrPayoutSchedule.
  ///
  /// In en, this message translates to:
  /// **'Payout schedule'**
  String get carrPayoutSchedule;

  /// No description provided for @carrEveryMonday.
  ///
  /// In en, this message translates to:
  /// **'Every Monday'**
  String get carrEveryMonday;

  /// No description provided for @carrAgreement.
  ///
  /// In en, this message translates to:
  /// **'I agree to the YouDrop Carrier Partnership & Service Agreement. Commission rates and payout periods are subject to monthly volume audits.'**
  String get carrAgreement;

  /// No description provided for @carrSubmitApplication.
  ///
  /// In en, this message translates to:
  /// **'Submit Application'**
  String get carrSubmitApplication;

  /// No description provided for @carrDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get carrDashboard;

  /// No description provided for @carrOrdersTab.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get carrOrdersTab;

  /// No description provided for @carrFleetTab.
  ///
  /// In en, this message translates to:
  /// **'Fleet'**
  String get carrFleetTab;

  /// No description provided for @carrEarningsTab.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get carrEarningsTab;

  /// No description provided for @carrSettingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get carrSettingsTab;

  /// No description provided for @carrActiveDeliveries.
  ///
  /// In en, this message translates to:
  /// **'Active deliveries'**
  String get carrActiveDeliveries;

  /// No description provided for @carrPendingOrders.
  ///
  /// In en, this message translates to:
  /// **'Pending orders'**
  String get carrPendingOrders;

  /// No description provided for @carrRidersOnline.
  ///
  /// In en, this message translates to:
  /// **'Riders on fleet'**
  String get carrRidersOnline;

  /// No description provided for @carrWindowEarned.
  ///
  /// In en, this message translates to:
  /// **'Earned ({days}d)'**
  String carrWindowEarned(int days);

  /// No description provided for @carrRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get carrRecentActivity;

  /// No description provided for @carrFleetManagement.
  ///
  /// In en, this message translates to:
  /// **'Fleet Management'**
  String get carrFleetManagement;

  /// No description provided for @carrDeliveriesToday.
  ///
  /// In en, this message translates to:
  /// **'{count} deliveries in window'**
  String carrDeliveriesToday(int count);

  /// No description provided for @carrCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get carrCall;

  /// No description provided for @carrTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total revenue'**
  String get carrTotalRevenue;

  /// No description provided for @carrNetEarnings.
  ///
  /// In en, this message translates to:
  /// **'Net earnings'**
  String get carrNetEarnings;

  /// No description provided for @carrCommissionPaid.
  ///
  /// In en, this message translates to:
  /// **'Commission paid to YouDrop'**
  String get carrCommissionPaid;

  /// No description provided for @carrCompanyPaused.
  ///
  /// In en, this message translates to:
  /// **'Company paused — no new work is offered'**
  String get carrCompanyPaused;

  /// No description provided for @carrPauseCompany.
  ///
  /// In en, this message translates to:
  /// **'Pause company'**
  String get carrPauseCompany;

  /// No description provided for @carrResumeCompany.
  ///
  /// In en, this message translates to:
  /// **'Resume company'**
  String get carrResumeCompany;

  /// No description provided for @carrScore.
  ///
  /// In en, this message translates to:
  /// **'Carrier score'**
  String get carrScore;

  /// No description provided for @carrCompletionRate.
  ///
  /// In en, this message translates to:
  /// **'Completion rate'**
  String get carrCompletionRate;

  /// No description provided for @carrOrdersDelivered.
  ///
  /// In en, this message translates to:
  /// **'Orders delivered'**
  String get carrOrdersDelivered;

  /// No description provided for @carrAlreadyPartner.
  ///
  /// In en, this message translates to:
  /// **'Already a partner?'**
  String get carrAlreadyPartner;

  /// No description provided for @carrBusinessEmail.
  ///
  /// In en, this message translates to:
  /// **'Business Email'**
  String get carrBusinessEmail;

  /// No description provided for @carrBusinessEmailHint.
  ///
  /// In en, this message translates to:
  /// **'partner@company.com'**
  String get carrBusinessEmailHint;

  /// No description provided for @carrContactPersonHint.
  ///
  /// In en, this message translates to:
  /// **'Full name of representative'**
  String get carrContactPersonHint;

  /// No description provided for @carrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'+961 70 123 456'**
  String get carrPhoneHint;

  /// No description provided for @carrDocsTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload Verification Documents'**
  String get carrDocsTitle;

  /// No description provided for @carrVerificationNote.
  ///
  /// In en, this message translates to:
  /// **'Documents are reviewed by the YouDrop Operations Desk. Verification typically completes within 24–48 hours.'**
  String get carrVerificationNote;

  /// No description provided for @carrPayoutMethod.
  ///
  /// In en, this message translates to:
  /// **'Preferred payout method'**
  String get carrPayoutMethod;

  /// No description provided for @carrPayoutCash.
  ///
  /// In en, this message translates to:
  /// **'Fresh USD Cash (Office pickup)'**
  String get carrPayoutCash;

  /// No description provided for @carrPayoutCashBlurb.
  ///
  /// In en, this message translates to:
  /// **'No service charges, weekly cash settlement'**
  String get carrPayoutCashBlurb;

  /// No description provided for @carrPayoutWhish.
  ///
  /// In en, this message translates to:
  /// **'Whish Money transfer'**
  String get carrPayoutWhish;

  /// No description provided for @carrPayoutWhishBlurb.
  ///
  /// In en, this message translates to:
  /// **'Standard Lebanese local wallet payout'**
  String get carrPayoutWhishBlurb;

  /// No description provided for @carrPayoutOmt.
  ///
  /// In en, this message translates to:
  /// **'OMT Cash Out'**
  String get carrPayoutOmt;

  /// No description provided for @carrPayoutOmtBlurb.
  ///
  /// In en, this message translates to:
  /// **'Payout sent directly via the OMT network'**
  String get carrPayoutOmtBlurb;

  /// No description provided for @carrPayoutBank.
  ///
  /// In en, this message translates to:
  /// **'USD Bank Transfer'**
  String get carrPayoutBank;

  /// No description provided for @carrPayoutBankBlurb.
  ///
  /// In en, this message translates to:
  /// **'Fresh USD wire to a Lebanese bank account'**
  String get carrPayoutBankBlurb;

  /// No description provided for @carrFlatFee.
  ///
  /// In en, this message translates to:
  /// **'{rate}% flat fee'**
  String carrFlatFee(int rate);

  /// No description provided for @carrSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Application Submitted!'**
  String get carrSubmittedTitle;

  /// No description provided for @carrAppId.
  ///
  /// In en, this message translates to:
  /// **'App ID: {reference}'**
  String carrAppId(String reference);

  /// No description provided for @carrApplicationStatus.
  ///
  /// In en, this message translates to:
  /// **'Application status'**
  String get carrApplicationStatus;

  /// No description provided for @carrStageReceived.
  ///
  /// In en, this message translates to:
  /// **'Application Received'**
  String get carrStageReceived;

  /// No description provided for @carrStageReceivedSub.
  ///
  /// In en, this message translates to:
  /// **'Submitted on {date}'**
  String carrStageReceivedSub(String date);

  /// No description provided for @carrStageDocs.
  ///
  /// In en, this message translates to:
  /// **'Document Verification'**
  String get carrStageDocs;

  /// No description provided for @carrStageDocsSub.
  ///
  /// In en, this message translates to:
  /// **'Under review (takes 24–48 hours)'**
  String get carrStageDocsSub;

  /// No description provided for @carrStageInspection.
  ///
  /// In en, this message translates to:
  /// **'Fleet Inspection'**
  String get carrStageInspection;

  /// No description provided for @carrStageInspectionSub.
  ///
  /// In en, this message translates to:
  /// **'Scheduled at your vehicle yard'**
  String get carrStageInspectionSub;

  /// No description provided for @carrStageActivation.
  ///
  /// In en, this message translates to:
  /// **'Account Activation'**
  String get carrStageActivation;

  /// No description provided for @carrStageActivationSub.
  ///
  /// In en, this message translates to:
  /// **'Access to YouDrop carrier dispatch'**
  String get carrStageActivationSub;

  /// No description provided for @carrPendingSupportBlurb.
  ///
  /// In en, this message translates to:
  /// **'We have sent you a confirmation email. Need urgent help with your submission?'**
  String get carrPendingSupportBlurb;

  /// No description provided for @carrChatSupport.
  ///
  /// In en, this message translates to:
  /// **'Chat with Partner Support'**
  String get carrChatSupport;

  /// No description provided for @carrReturnHome.
  ///
  /// In en, this message translates to:
  /// **'Return to Home'**
  String get carrReturnHome;

  /// No description provided for @carrBadgeLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get carrBadgeLive;

  /// No description provided for @carrBadgeWaiting.
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get carrBadgeWaiting;

  /// No description provided for @carrBadgeFleet.
  ///
  /// In en, this message translates to:
  /// **'FLEET'**
  String get carrBadgeFleet;

  /// No description provided for @carrBadgeUsd.
  ///
  /// In en, this message translates to:
  /// **'USD'**
  String get carrBadgeUsd;

  /// No description provided for @carrTodayRevenue.
  ///
  /// In en, this message translates to:
  /// **'Today\'s revenue'**
  String get carrTodayRevenue;

  /// No description provided for @carrCoverageMapBlurb.
  ///
  /// In en, this message translates to:
  /// **'The circles your riders work. Tap to edit.'**
  String get carrCoverageMapBlurb;

  /// No description provided for @carrIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get carrIncoming;

  /// No description provided for @carrCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get carrCompleted;

  /// No description provided for @carrUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned order'**
  String get carrUnassigned;

  /// No description provided for @carrWaitingDispatch.
  ///
  /// In en, this message translates to:
  /// **'Waiting for dispatch'**
  String get carrWaitingDispatch;

  /// No description provided for @carrShowingRiders.
  ///
  /// In en, this message translates to:
  /// **'{count} riders on the fleet'**
  String carrShowingRiders(int count);

  /// No description provided for @carrNoRiders.
  ///
  /// In en, this message translates to:
  /// **'No riders on the fleet yet — the platform assigns riders after onboarding.'**
  String get carrNoRiders;

  /// No description provided for @carrDelivering.
  ///
  /// In en, this message translates to:
  /// **'Delivering #{id}'**
  String carrDelivering(String id);

  /// No description provided for @carrAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get carrAvailable;

  /// No description provided for @carrWeeklySummary.
  ///
  /// In en, this message translates to:
  /// **'Weekly summary'**
  String get carrWeeklySummary;

  /// No description provided for @carrDeliveriesBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Deliveries breakdown'**
  String get carrDeliveriesBreakdown;

  /// No description provided for @carrCommissionPct.
  ///
  /// In en, this message translates to:
  /// **'Commission paid to YouDrop ({rate}%)'**
  String carrCommissionPct(int rate);

  /// No description provided for @carrNextPayout.
  ///
  /// In en, this message translates to:
  /// **'Next payout scheduled'**
  String get carrNextPayout;

  /// No description provided for @carrPickupFrom.
  ///
  /// In en, this message translates to:
  /// **'Pickup from'**
  String get carrPickupFrom;

  /// No description provided for @carrDeliverTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get carrDeliverTo;

  /// No description provided for @carrPaymentCommission.
  ///
  /// In en, this message translates to:
  /// **'Payment & commission'**
  String get carrPaymentCommission;

  /// No description provided for @carrDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery total (Fresh USD)'**
  String get carrDeliveryFee;

  /// No description provided for @carrLbpRate.
  ///
  /// In en, this message translates to:
  /// **'LBP conversion rate ({rate})'**
  String carrLbpRate(String rate);

  /// No description provided for @carrPlatformFee.
  ///
  /// In en, this message translates to:
  /// **'YouDrop platform fee ({rate}%)'**
  String carrPlatformFee(int rate);

  /// No description provided for @carrStepReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get carrStepReceived;

  /// No description provided for @carrStepAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get carrStepAssigned;

  /// No description provided for @carrStepPickingUp.
  ///
  /// In en, this message translates to:
  /// **'Picking up'**
  String get carrStepPickingUp;

  /// No description provided for @carrStepEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get carrStepEnRoute;

  /// No description provided for @carrStepDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get carrStepDelivered;

  /// No description provided for @carrOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get carrOperations;

  /// No description provided for @carrPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get carrPayments;

  /// No description provided for @carrAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get carrAccountSection;

  /// No description provided for @carrHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get carrHelpSupport;

  /// No description provided for @carrVersionCaption.
  ///
  /// In en, this message translates to:
  /// **'YouDrop Carrier v{version}'**
  String carrVersionCaption(String version);

  /// No description provided for @carrCoverageZones.
  ///
  /// In en, this message translates to:
  /// **'Coverage Zones'**
  String get carrCoverageZones;

  /// No description provided for @carrAddZone.
  ///
  /// In en, this message translates to:
  /// **'Add zone'**
  String get carrAddZone;

  /// No description provided for @carrZoneName.
  ///
  /// In en, this message translates to:
  /// **'Zone name'**
  String get carrZoneName;

  /// No description provided for @carrZoneNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Central Beirut'**
  String get carrZoneNameHint;

  /// No description provided for @carrZoneRadiusKm.
  ///
  /// In en, this message translates to:
  /// **'Radius: {km} km'**
  String carrZoneRadiusKm(String km);

  /// No description provided for @carrZoneActive.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get carrZoneActive;

  /// No description provided for @carrZonePaused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get carrZonePaused;

  /// No description provided for @carrDeleteZoneAsk.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}? Riders keep working the other zones.'**
  String carrDeleteZoneAsk(String name);

  /// No description provided for @carrNoZones.
  ///
  /// In en, this message translates to:
  /// **'No zones yet. Draw the first circle your riders work.'**
  String get carrNoZones;

  /// No description provided for @carrEditZone.
  ///
  /// In en, this message translates to:
  /// **'Edit zone'**
  String get carrEditZone;

  /// No description provided for @carrNewZone.
  ///
  /// In en, this message translates to:
  /// **'New zone'**
  String get carrNewZone;

  /// No description provided for @custVerifiedLocal.
  ///
  /// In en, this message translates to:
  /// **'Verified Local'**
  String get custVerifiedLocal;

  /// No description provided for @custPowerDeclared.
  ///
  /// In en, this message translates to:
  /// **'Power status — declared by the shops themselves'**
  String get custPowerDeclared;

  /// No description provided for @merchbPowerHeading.
  ///
  /// In en, this message translates to:
  /// **'Power status'**
  String get merchbPowerHeading;

  /// No description provided for @merchbPowerHint.
  ///
  /// In en, this message translates to:
  /// **'Tell customers what the lights are doing — it shows on your storefront card.'**
  String get merchbPowerHint;

  /// No description provided for @merchbDeliveryAreaOff.
  ///
  /// In en, this message translates to:
  /// **'No delivery limit — zones alone decide'**
  String get merchbDeliveryAreaOff;

  /// No description provided for @merchbDeliverWithin.
  ///
  /// In en, this message translates to:
  /// **'Deliver within {km} km'**
  String merchbDeliverWithin(String km);

  /// No description provided for @custOutsideDeliveryArea.
  ///
  /// In en, this message translates to:
  /// **'{store} delivers within {km} km of the shop — that address is outside its area.'**
  String custOutsideDeliveryArea(String store, String km);

  /// No description provided for @custHyperlocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood Dekkane'**
  String get custHyperlocalTitle;

  /// No description provided for @custHyperlocalSub.
  ///
  /// In en, this message translates to:
  /// **'The local shops of your streets'**
  String get custHyperlocalSub;

  /// No description provided for @custDistricts.
  ///
  /// In en, this message translates to:
  /// **'Districts'**
  String get custDistricts;

  /// No description provided for @custSearchArabiziHint.
  ///
  /// In en, this message translates to:
  /// **'Search: 2ahwe, man\'oushe, knefe...'**
  String get custSearchArabiziHint;

  /// No description provided for @custAllDistricts.
  ///
  /// In en, this message translates to:
  /// **'All districts'**
  String get custAllDistricts;

  /// No description provided for @custDiasporaSub.
  ///
  /// In en, this message translates to:
  /// **'Diaspora Gifting Portal'**
  String get custDiasporaSub;

  /// No description provided for @custPersonalNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Habibti Mom, wishing you a beautiful week — some food and groceries with love!'**
  String get custPersonalNoteHint;

  /// No description provided for @custWhatToSend.
  ///
  /// In en, this message translates to:
  /// **'What would you like to send?'**
  String get custWhatToSend;

  /// No description provided for @custRecentDeliveriesTo.
  ///
  /// In en, this message translates to:
  /// **'Recent deliveries to {name}'**
  String custRecentDeliveriesTo(String name);

  /// No description provided for @custStartOrder.
  ///
  /// In en, this message translates to:
  /// **'Select Items & Start Order'**
  String get custStartOrder;

  /// No description provided for @custPickRecipient.
  ///
  /// In en, this message translates to:
  /// **'Choose who receives it'**
  String get custPickRecipient;

  /// No description provided for @custNoRecipientYet.
  ///
  /// In en, this message translates to:
  /// **'Save their address first — add it from the address book with their name as the label.'**
  String get custNoRecipientYet;

  /// No description provided for @custGiftNoteRides.
  ///
  /// In en, this message translates to:
  /// **'Your note travels with the order and is read out at the door.'**
  String get custGiftNoteRides;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @custSoloOrder.
  ///
  /// In en, this message translates to:
  /// **'Solo Order'**
  String get custSoloOrder;

  /// No description provided for @custSplitOrder.
  ///
  /// In en, this message translates to:
  /// **'Split Order'**
  String get custSplitOrder;

  /// No description provided for @custOrderParticipants.
  ///
  /// In en, this message translates to:
  /// **'Order Participants'**
  String get custOrderParticipants;

  /// No description provided for @custAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get custAddFriend;

  /// No description provided for @custAssignedTo.
  ///
  /// In en, this message translates to:
  /// **'Assigned: {name}'**
  String custAssignedTo(String name);

  /// No description provided for @custPaymentSplitSummary.
  ///
  /// In en, this message translates to:
  /// **'Payment Split Summary'**
  String get custPaymentSplitSummary;

  /// No description provided for @custTotalOrderAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Order Amount'**
  String get custTotalOrderAmount;

  /// No description provided for @custSendPaymentRequests.
  ///
  /// In en, this message translates to:
  /// **'Send Payment Requests'**
  String get custSendPaymentRequests;

  /// No description provided for @custSplitWithGroup.
  ///
  /// In en, this message translates to:
  /// **'Split with Group'**
  String get custSplitWithGroup;

  /// No description provided for @custHowManyPeople.
  ///
  /// In en, this message translates to:
  /// **'How many people?'**
  String get custHowManyPeople;

  /// No description provided for @custIncludingYourself.
  ///
  /// In en, this message translates to:
  /// **'Including yourself'**
  String get custIncludingYourself;

  /// No description provided for @custEvenBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Even split breakdown'**
  String get custEvenBreakdown;

  /// No description provided for @custEachPays.
  ///
  /// In en, this message translates to:
  /// **'Each pays'**
  String get custEachPays;

  /// No description provided for @custHostAbsorbs.
  ///
  /// In en, this message translates to:
  /// **'Host absorbs {amount} remainder'**
  String custHostAbsorbs(String amount);

  /// No description provided for @custAddFriendsHdr.
  ///
  /// In en, this message translates to:
  /// **'Add friends'**
  String get custAddFriendsHdr;

  /// No description provided for @custEnterUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter username'**
  String get custEnterUsername;

  /// No description provided for @custYourShareYou.
  ///
  /// In en, this message translates to:
  /// **'Your share (You)'**
  String get custYourShareYou;

  /// No description provided for @cust15MinNote.
  ///
  /// In en, this message translates to:
  /// **'Friends have 15 min to pay after the invite'**
  String get cust15MinNote;

  /// No description provided for @custSendInvites.
  ///
  /// In en, this message translates to:
  /// **'Send Invites'**
  String get custSendInvites;

  /// No description provided for @custWaitingGroupPayments.
  ///
  /// In en, this message translates to:
  /// **'Waiting for group payments'**
  String get custWaitingGroupPayments;

  /// No description provided for @custTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'Time remaining'**
  String get custTimeRemaining;

  /// No description provided for @custSplitNWays.
  ///
  /// In en, this message translates to:
  /// **'{amount} split {n} ways'**
  String custSplitNWays(String amount, int n);

  /// No description provided for @custPaymentProgress.
  ///
  /// In en, this message translates to:
  /// **'Payment progress'**
  String get custPaymentProgress;

  /// No description provided for @custNPaid.
  ///
  /// In en, this message translates to:
  /// **'{paid} / {total} Paid'**
  String custNPaid(int paid, int total);

  /// No description provided for @custCollectedOf.
  ///
  /// In en, this message translates to:
  /// **'{collected} of {total} collected'**
  String custCollectedOf(String collected, String total);

  /// No description provided for @custPaidVia.
  ///
  /// In en, this message translates to:
  /// **'Paid via {method}'**
  String custPaidVia(String method);

  /// No description provided for @custPaidChip.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get custPaidChip;

  /// No description provided for @custPendingChip.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get custPendingChip;

  /// No description provided for @custDeclinedChip.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get custDeclinedChip;

  /// No description provided for @custCoveredChip.
  ///
  /// In en, this message translates to:
  /// **'Covered'**
  String get custCoveredChip;

  /// No description provided for @custCoverRest.
  ///
  /// In en, this message translates to:
  /// **'Cover the Rest ({amount})'**
  String custCoverRest(String amount);

  /// No description provided for @custReadyToPlace.
  ///
  /// In en, this message translates to:
  /// **'All shares are in — place the order'**
  String get custReadyToPlace;

  /// No description provided for @custContinueToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Continue to Checkout'**
  String get custContinueToCheckout;

  /// No description provided for @custRemindBtn.
  ///
  /// In en, this message translates to:
  /// **'Remind'**
  String get custRemindBtn;

  /// No description provided for @custCancelSplit.
  ///
  /// In en, this message translates to:
  /// **'Cancel Split Order'**
  String get custCancelSplit;

  /// No description provided for @custInvitedYouToSplit.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to split'**
  String custInvitedYouToSplit(String name);

  /// No description provided for @custYourShareToPay.
  ///
  /// In en, this message translates to:
  /// **'Your share to pay'**
  String get custYourShareToPay;

  /// No description provided for @custSelectPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get custSelectPaymentMethod;

  /// No description provided for @custWhishShort.
  ///
  /// In en, this message translates to:
  /// **'Whish Money'**
  String get custWhishShort;

  /// No description provided for @custOmtShort.
  ///
  /// In en, this message translates to:
  /// **'OMT'**
  String get custOmtShort;

  /// No description provided for @custBobShort.
  ///
  /// In en, this message translates to:
  /// **'BOB Finance'**
  String get custBobShort;

  /// No description provided for @custCashAtDoor.
  ///
  /// In en, this message translates to:
  /// **'Cash at Door'**
  String get custCashAtDoor;

  /// No description provided for @custRiderCollectsFromYou.
  ///
  /// In en, this message translates to:
  /// **'Rider will collect from you'**
  String get custRiderCollectsFromYou;

  /// No description provided for @custRecommendedChip.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get custRecommendedChip;

  /// No description provided for @custPayMyShare.
  ///
  /// In en, this message translates to:
  /// **'Pay My Share ({amount})'**
  String custPayMyShare(String amount);

  /// No description provided for @custDeclineInvitation.
  ///
  /// In en, this message translates to:
  /// **'Decline invitation'**
  String get custDeclineInvitation;

  /// No description provided for @custAllSharesPaid.
  ///
  /// In en, this message translates to:
  /// **'All Shares Paid!'**
  String get custAllSharesPaid;

  /// No description provided for @custGroupSplitSummary.
  ///
  /// In en, this message translates to:
  /// **'Group Split Summary'**
  String get custGroupSplitSummary;

  /// No description provided for @custRiderCollectNote.
  ///
  /// In en, this message translates to:
  /// **'Rider will collect {amount} from {name} at delivery'**
  String custRiderCollectNote(String amount, String name);

  /// No description provided for @custAddToOrder.
  ///
  /// In en, this message translates to:
  /// **'Add to Order'**
  String get custAddToOrder;

  /// No description provided for @custSearchByUsername.
  ///
  /// In en, this message translates to:
  /// **'Search by username...'**
  String get custSearchByUsername;

  /// No description provided for @custRecentlySplitWith.
  ///
  /// In en, this message translates to:
  /// **'Recently split with'**
  String get custRecentlySplitWith;

  /// No description provided for @custQuickAdd.
  ///
  /// In en, this message translates to:
  /// **'Quick Add'**
  String get custQuickAdd;

  /// No description provided for @custAddAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Add {name} as guest — pays cash at the door'**
  String custAddAsGuest(String name);

  /// No description provided for @custSplitRequestBanner.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to split an order'**
  String custSplitRequestBanner(String name);

  /// No description provided for @custPayYourShare.
  ///
  /// In en, this message translates to:
  /// **'Pay your share'**
  String get custPayYourShare;

  /// No description provided for @riderCashChecklist.
  ///
  /// In en, this message translates to:
  /// **'Cash Collection Checklist'**
  String get riderCashChecklist;

  /// No description provided for @riderAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'Already paid digitally'**
  String get riderAlreadyPaid;

  /// No description provided for @riderTotalCashCollect.
  ///
  /// In en, this message translates to:
  /// **'Total Cash to Collect'**
  String get riderTotalCashCollect;

  /// No description provided for @riderSplitOrderTag.
  ///
  /// In en, this message translates to:
  /// **'Split Order'**
  String get riderSplitOrderTag;

  /// No description provided for @custMinOrderLine.
  ///
  /// In en, this message translates to:
  /// **'Min. Order: {amount}'**
  String custMinOrderLine(String amount);

  /// No description provided for @custYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String custYesterdayAt(String time);

  /// No description provided for @custDualPriceMode.
  ///
  /// In en, this message translates to:
  /// **'Dual price mode'**
  String get custDualPriceMode;

  /// No description provided for @custDeliveryTime.
  ///
  /// In en, this message translates to:
  /// **'Delivery Time'**
  String get custDeliveryTime;

  /// No description provided for @custMinOrderStat.
  ///
  /// In en, this message translates to:
  /// **'Min. Order'**
  String get custMinOrderStat;

  /// No description provided for @custRatingsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No ratings} =1{1 Rating} other{{count} Ratings}}'**
  String custRatingsCount(int count);

  /// No description provided for @custShopsInCategory.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No shops} =1{1 Shop} other{{count} Shops}}'**
  String custShopsInCategory(int count);

  /// No description provided for @custPeopleAlsoOrdered.
  ///
  /// In en, this message translates to:
  /// **'People Also Ordered'**
  String get custPeopleAlsoOrdered;

  /// No description provided for @custSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get custSoon;

  /// No description provided for @custIncreaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get custIncreaseQuantity;

  /// No description provided for @custDecreaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get custDecreaseQuantity;

  /// No description provided for @custSearchInShop.
  ///
  /// In en, this message translates to:
  /// **'Search this shop'**
  String get custSearchInShop;

  /// No description provided for @custShopSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search the menu'**
  String get custShopSearchHint;

  /// No description provided for @custButlerTitle.
  ///
  /// In en, this message translates to:
  /// **'YouDrop Butler'**
  String get custButlerTitle;

  /// No description provided for @custChooseWhatYouNeed.
  ///
  /// In en, this message translates to:
  /// **'Choose what you need help with'**
  String get custChooseWhatYouNeed;

  /// No description provided for @custBuyAnything.
  ///
  /// In en, this message translates to:
  /// **'Buy Anything'**
  String get custBuyAnything;

  /// No description provided for @custBuyAnythingBlurb.
  ///
  /// In en, this message translates to:
  /// **'We buy & deliver from anywhere'**
  String get custBuyAnythingBlurb;

  /// No description provided for @custSendAnything.
  ///
  /// In en, this message translates to:
  /// **'Send Anything'**
  String get custSendAnything;

  /// No description provided for @custSendAnythingBlurb.
  ///
  /// In en, this message translates to:
  /// **'Courier, pick up, or send items'**
  String get custSendAnythingBlurb;

  /// No description provided for @custRecentTasks.
  ///
  /// In en, this message translates to:
  /// **'Recent tasks'**
  String get custRecentTasks;

  /// No description provided for @custSearchTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Search your errands'**
  String get custSearchTasksHint;

  /// No description provided for @custNoTasksMatch.
  ///
  /// In en, this message translates to:
  /// **'No errands match that search'**
  String get custNoTasksMatch;

  /// No description provided for @custStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get custStatusPending;

  /// No description provided for @custWaitingOnYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting on you'**
  String get custWaitingOnYou;

  /// No description provided for @custApplePay.
  ///
  /// In en, this message translates to:
  /// **'Apple Pay'**
  String get custApplePay;

  /// No description provided for @custOrderNotes.
  ///
  /// In en, this message translates to:
  /// **'Order Notes'**
  String get custOrderNotes;

  /// No description provided for @custOrderNotesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Leave package at the door, bell is not working...'**
  String get custOrderNotesHint;

  /// No description provided for @custTotalPrice.
  ///
  /// In en, this message translates to:
  /// **'Total Price'**
  String get custTotalPrice;

  /// No description provided for @custPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get custPlaceOrder;

  /// No description provided for @custOrderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get custOrderStatus;

  /// No description provided for @custOrderRef.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get custOrderRef;

  /// No description provided for @custItemsOrdered.
  ///
  /// In en, this message translates to:
  /// **'Items Ordered'**
  String get custItemsOrdered;

  /// No description provided for @custLiveMap.
  ///
  /// In en, this message translates to:
  /// **'Live map'**
  String get custLiveMap;

  /// No description provided for @custAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get custAccountSettings;

  /// No description provided for @custHiName.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String custHiName(String name);

  /// No description provided for @custRewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards & Points'**
  String get custRewardsTitle;

  /// No description provided for @custTotalPoints.
  ///
  /// In en, this message translates to:
  /// **'Total points'**
  String get custTotalPoints;

  /// No description provided for @custPtsThisMonth.
  ///
  /// In en, this message translates to:
  /// **'+{points} pts this month'**
  String custPtsThisMonth(int points);

  /// No description provided for @custNextTierLabel.
  ///
  /// In en, this message translates to:
  /// **'Next tier: {tier}'**
  String custNextTierLabel(String tier);

  /// No description provided for @custPtsToGo.
  ///
  /// In en, this message translates to:
  /// **'{points} pts to go'**
  String custPtsToGo(int points);

  /// No description provided for @custRewardsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Earn points on every delivered order. Redeem for vouchers and cashback.'**
  String get custRewardsBlurb;

  /// No description provided for @custCurrentTierHeading.
  ///
  /// In en, this message translates to:
  /// **'Current tier'**
  String get custCurrentTierHeading;

  /// No description provided for @custCurrentTierLine.
  ///
  /// In en, this message translates to:
  /// **'Current Tier: {tier}'**
  String custCurrentTierLine(String tier);

  /// No description provided for @custTierEarnedLine.
  ///
  /// In en, this message translates to:
  /// **'Earned {points} points · {orders} orders completed'**
  String custTierEarnedLine(int points, int orders);

  /// No description provided for @custNextTierLine.
  ///
  /// In en, this message translates to:
  /// **'Next Tier: {tier}'**
  String custNextTierLine(String tier);

  /// No description provided for @custNextTierBlurb.
  ///
  /// In en, this message translates to:
  /// **'Reach {points} points to unlock better rewards.'**
  String custNextTierBlurb(int points);

  /// No description provided for @custTopTier.
  ///
  /// In en, this message translates to:
  /// **'You are at the top tier.'**
  String get custTopTier;

  /// No description provided for @custRewardCategories.
  ///
  /// In en, this message translates to:
  /// **'Reward categories'**
  String get custRewardCategories;

  /// No description provided for @custFreeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free Delivery'**
  String get custFreeDelivery;

  /// No description provided for @custVouchersAvailable.
  ///
  /// In en, this message translates to:
  /// **'Vouchers available'**
  String get custVouchersAvailable;

  /// No description provided for @custCashback.
  ///
  /// In en, this message translates to:
  /// **'Cashback'**
  String get custCashback;

  /// No description provided for @custEarnedLabel.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get custEarnedLabel;

  /// No description provided for @custReferralBonus.
  ///
  /// In en, this message translates to:
  /// **'Referral Bonus'**
  String get custReferralBonus;

  /// No description provided for @custRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get custRecentActivity;

  /// No description provided for @custNoActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No points yet — they arrive with your first delivered order.'**
  String get custNoActivityYet;

  /// No description provided for @custPointsOrderEntry.
  ///
  /// In en, this message translates to:
  /// **'{points} pts · Order #{shortId}'**
  String custPointsOrderEntry(String points, String shortId);

  /// No description provided for @custPointsEntry.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String custPointsEntry(String points);

  /// No description provided for @tierBronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get tierBronze;

  /// No description provided for @tierSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get tierSilver;

  /// No description provided for @tierGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get tierGold;

  /// No description provided for @tierPlatinum.
  ///
  /// In en, this message translates to:
  /// **'Platinum'**
  String get tierPlatinum;

  /// No description provided for @custMyAccount.
  ///
  /// In en, this message translates to:
  /// **'My account'**
  String get custMyAccount;

  /// No description provided for @custMyOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get custMyOrders;

  /// No description provided for @custMyAddresses.
  ///
  /// In en, this message translates to:
  /// **'My Addresses'**
  String get custMyAddresses;

  /// No description provided for @custPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment Methods'**
  String get custPaymentMethods;

  /// No description provided for @custVouchersPromos.
  ///
  /// In en, this message translates to:
  /// **'Vouchers & Promos'**
  String get custVouchersPromos;

  /// No description provided for @custPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get custPreferences;

  /// No description provided for @custSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get custSupport;

  /// No description provided for @custTermsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Terms & Privacy'**
  String get custTermsPrivacy;

  /// No description provided for @custAboutYoudrop.
  ///
  /// In en, this message translates to:
  /// **'About YouDrop'**
  String get custAboutYoudrop;

  /// No description provided for @custEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get custEditProfile;

  /// No description provided for @custLogOutAccount.
  ///
  /// In en, this message translates to:
  /// **'Log Out Account'**
  String get custLogOutAccount;

  /// No description provided for @custAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get custAppLanguage;

  /// No description provided for @custOrderHistory.
  ///
  /// In en, this message translates to:
  /// **'Order History'**
  String get custOrderHistory;

  /// No description provided for @custHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get custHelpSupport;

  /// No description provided for @custLabelAddressAs.
  ///
  /// In en, this message translates to:
  /// **'Label Address As:'**
  String get custLabelAddressAs;

  /// No description provided for @custLabelHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get custLabelHome;

  /// No description provided for @custLabelWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get custLabelWork;

  /// No description provided for @custLabelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get custLabelOther;

  /// No description provided for @merchTodaySummary.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Summary'**
  String get merchTodaySummary;

  /// No description provided for @merchPendingOrders.
  ///
  /// In en, this message translates to:
  /// **'Pending Orders'**
  String get merchPendingOrders;

  /// No description provided for @merchNewOrders.
  ///
  /// In en, this message translates to:
  /// **'New Orders'**
  String get merchNewOrders;

  /// No description provided for @merchView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get merchView;

  /// No description provided for @merchRecentOrders.
  ///
  /// In en, this message translates to:
  /// **'Recent Orders'**
  String get merchRecentOrders;

  /// No description provided for @merchViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get merchViewAll;

  /// No description provided for @merchActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get merchActive;

  /// No description provided for @merchInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get merchInactive;

  /// No description provided for @merchPublishShop.
  ///
  /// In en, this message translates to:
  /// **'Publish your shop'**
  String get merchPublishShop;

  /// No description provided for @merchShopHidden.
  ///
  /// In en, this message translates to:
  /// **'Your shop is hidden from the market.'**
  String get merchShopHidden;

  /// No description provided for @merchbHideShop.
  ///
  /// In en, this message translates to:
  /// **'Hide shop'**
  String get merchbHideShop;

  /// No description provided for @merchOrderFlow.
  ///
  /// In en, this message translates to:
  /// **'Order Flow'**
  String get merchOrderFlow;

  /// No description provided for @merchManagerView.
  ///
  /// In en, this message translates to:
  /// **'Manager View'**
  String get merchManagerView;

  /// No description provided for @merchTabNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get merchTabNew;

  /// No description provided for @merchTabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get merchTabCompleted;

  /// No description provided for @merchReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get merchReject;

  /// No description provided for @merchFlowStatus.
  ///
  /// In en, this message translates to:
  /// **'Flow Status'**
  String get merchFlowStatus;

  /// No description provided for @merchCustomerDetails.
  ///
  /// In en, this message translates to:
  /// **'Customer Details'**
  String get merchCustomerDetails;

  /// No description provided for @merchItemsBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Items Breakdown'**
  String get merchItemsBreakdown;

  /// No description provided for @merchSpecialInstructions.
  ///
  /// In en, this message translates to:
  /// **'Special Instructions'**
  String get merchSpecialInstructions;

  /// No description provided for @merchGrandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get merchGrandTotal;

  /// No description provided for @merchStepPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked Up'**
  String get merchStepPickedUp;

  /// No description provided for @merchNothingInThisList.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this list.'**
  String get merchNothingInThisList;

  /// No description provided for @merchOpenOrder.
  ///
  /// In en, this message translates to:
  /// **'Open order'**
  String get merchOpenOrder;

  /// No description provided for @merchbMenuItems.
  ///
  /// In en, this message translates to:
  /// **'Menu Items'**
  String get merchbMenuItems;

  /// No description provided for @merchbManageAvailability.
  ///
  /// In en, this message translates to:
  /// **'Manage availability'**
  String get merchbManageAvailability;

  /// No description provided for @merchbSearchMenuItems.
  ///
  /// In en, this message translates to:
  /// **'Search products...'**
  String get merchbSearchMenuItems;

  /// No description provided for @merchbAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get merchbAvailable;

  /// No description provided for @merchbOffShelf.
  ///
  /// In en, this message translates to:
  /// **'Off-shelf'**
  String get merchbOffShelf;

  /// No description provided for @merchbAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get merchbAddProduct;

  /// No description provided for @merchbAvailability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get merchbAvailability;

  /// No description provided for @merchbNoMatchingItems.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get merchbNoMatchingItems;

  /// No description provided for @merchbAddNewProduct.
  ///
  /// In en, this message translates to:
  /// **'Add New Product'**
  String get merchbAddNewProduct;

  /// No description provided for @merchbProductImage.
  ///
  /// In en, this message translates to:
  /// **'Product Image'**
  String get merchbProductImage;

  /// No description provided for @merchbUploadImageCta.
  ///
  /// In en, this message translates to:
  /// **'Upload a product photo'**
  String get merchbUploadImageCta;

  /// No description provided for @merchbUploadHint.
  ///
  /// In en, this message translates to:
  /// **'PNG, JPG up to 5MB'**
  String get merchbUploadHint;

  /// No description provided for @merchbVariantsOptions.
  ///
  /// In en, this message translates to:
  /// **'Variants & Options'**
  String get merchbVariantsOptions;

  /// No description provided for @merchbAddOption.
  ///
  /// In en, this message translates to:
  /// **'+ Add option'**
  String get merchbAddOption;

  /// No description provided for @merchbChoicesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 choice} other{{count} choices}}'**
  String merchbChoicesCount(int count);

  /// No description provided for @merchbNoOptionsYet.
  ///
  /// In en, this message translates to:
  /// **'No options on this item yet'**
  String get merchbNoOptionsYet;

  /// No description provided for @merchbOptionsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Shown as customers see them. Editing options arrives soon.'**
  String get merchbOptionsReadOnly;

  /// No description provided for @merchbOptionsNeedSave.
  ///
  /// In en, this message translates to:
  /// **'Save the item first, then add its options.'**
  String get merchbOptionsNeedSave;

  /// No description provided for @merchbOptionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the current options. Nothing was changed.'**
  String get merchbOptionsLoadFailed;

  /// No description provided for @merchbOptionsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the options.'**
  String get merchbOptionsSaveFailed;

  /// No description provided for @merchbAddGroup.
  ///
  /// In en, this message translates to:
  /// **'+ Add group'**
  String get merchbAddGroup;

  /// No description provided for @merchbGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get merchbGroupName;

  /// No description provided for @merchbRemoveGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove group'**
  String get merchbRemoveGroup;

  /// No description provided for @merchbOptionName.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get merchbOptionName;

  /// No description provided for @merchbRemoveOption.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get merchbRemoveOption;

  /// No description provided for @merchbPriceDelta.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get merchbPriceDelta;

  /// No description provided for @merchbMinSelect.
  ///
  /// In en, this message translates to:
  /// **'Choose at least'**
  String get merchbMinSelect;

  /// No description provided for @merchbMaxSelect.
  ///
  /// In en, this message translates to:
  /// **'Choose at most'**
  String get merchbMaxSelect;

  /// No description provided for @merchbRuleRequired.
  ///
  /// In en, this message translates to:
  /// **'Required — the customer must choose.'**
  String get merchbRuleRequired;

  /// No description provided for @merchbRuleOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional — the customer may skip this.'**
  String get merchbRuleOptional;

  /// No description provided for @merchbUntitledGroup.
  ///
  /// In en, this message translates to:
  /// **'this group'**
  String get merchbUntitledGroup;

  /// No description provided for @merchbGroupNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Every group needs a name.'**
  String get merchbGroupNeedsName;

  /// No description provided for @merchbGroupNeedsOption.
  ///
  /// In en, this message translates to:
  /// **'{name} needs at least one option.'**
  String merchbGroupNeedsOption(String name);

  /// No description provided for @merchbOptionNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Every option in {name} needs a name.'**
  String merchbOptionNeedsName(String name);

  /// No description provided for @merchbMinAboveMax.
  ///
  /// In en, this message translates to:
  /// **'In {name}, the minimum is above the maximum.'**
  String merchbMinAboveMax(String name);

  /// No description provided for @merchbMinAboveCount.
  ///
  /// In en, this message translates to:
  /// **'In {name}, the minimum is more than the number of options.'**
  String merchbMinAboveCount(String name);

  /// No description provided for @merchbGroupOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'In {name}, the numbers must be between 0 and 50.'**
  String merchbGroupOutOfRange(String name);

  /// No description provided for @merchbSaveMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get merchbSaveMenuItem;

  /// No description provided for @merchbSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get merchbSoon;

  /// No description provided for @merchbShopConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Shop Configuration'**
  String get merchbShopConfiguration;

  /// No description provided for @merchbShopStatus.
  ///
  /// In en, this message translates to:
  /// **'Shop status'**
  String get merchbShopStatus;

  /// No description provided for @merchbBannerAndLogo.
  ///
  /// In en, this message translates to:
  /// **'Shop Banner & Logo'**
  String get merchbBannerAndLogo;

  /// No description provided for @merchbChangeCover.
  ///
  /// In en, this message translates to:
  /// **'Change Cover'**
  String get merchbChangeCover;

  /// No description provided for @merchbChangeLogo.
  ///
  /// In en, this message translates to:
  /// **'Change Logo'**
  String get merchbChangeLogo;

  /// No description provided for @merchbShopAddress.
  ///
  /// In en, this message translates to:
  /// **'Shop Address'**
  String get merchbShopAddress;

  /// No description provided for @merchbMapPreviewSoon.
  ///
  /// In en, this message translates to:
  /// **'Map preview'**
  String get merchbMapPreviewSoon;

  /// No description provided for @merchbOperatingDetails.
  ///
  /// In en, this message translates to:
  /// **'Operating Details'**
  String get merchbOperatingDetails;

  /// No description provided for @merchbSaveShopSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Shop Settings'**
  String get merchbSaveShopSettings;

  /// No description provided for @merchbHoursDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily: {from} - {to}'**
  String merchbHoursDaily(String from, String to);

  /// No description provided for @merchbHoursCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom schedule'**
  String get merchbHoursCustom;

  /// No description provided for @merchbHoursNone.
  ///
  /// In en, this message translates to:
  /// **'No hours set'**
  String get merchbHoursNone;

  /// No description provided for @merchbEditHours.
  ///
  /// In en, this message translates to:
  /// **'Edit opening hours'**
  String get merchbEditHours;

  /// No description provided for @merchbDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get merchbDay;

  /// No description provided for @merchbTimeHint.
  ///
  /// In en, this message translates to:
  /// **'HH:mm'**
  String get merchbTimeHint;

  /// No description provided for @merchbDayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get merchbDayMonday;

  /// No description provided for @merchbDayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get merchbDayTuesday;

  /// No description provided for @merchbDayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get merchbDayWednesday;

  /// No description provided for @merchbDayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get merchbDayThursday;

  /// No description provided for @merchbDayFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get merchbDayFriday;

  /// No description provided for @merchbDaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get merchbDaySaturday;

  /// No description provided for @merchbDaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get merchbDaySunday;

  /// No description provided for @merchbAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get merchbAccountSettings;

  /// No description provided for @merchbRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get merchbRoleOwner;

  /// No description provided for @merchbAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get merchbAppLanguage;

  /// No description provided for @merchbLangShortEn.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get merchbLangShortEn;

  /// No description provided for @merchbLangShortAr.
  ///
  /// In en, this message translates to:
  /// **'AR'**
  String get merchbLangShortAr;

  /// No description provided for @merchbShopProfile.
  ///
  /// In en, this message translates to:
  /// **'Shop Profile'**
  String get merchbShopProfile;

  /// No description provided for @merchbPaymentBankDetails.
  ///
  /// In en, this message translates to:
  /// **'Payment & Bank details'**
  String get merchbPaymentBankDetails;

  /// No description provided for @merchbBankReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This is the account on file. It was set with your application, and the platform team is who changes it now — not this screen.'**
  String get merchbBankReadOnly;

  /// No description provided for @merchbBankNoneFiled.
  ///
  /// In en, this message translates to:
  /// **'No bank details were filed with your application. The bank step closes once an application is decided, so the platform team is who adds them now.'**
  String get merchbBankNoneFiled;

  /// No description provided for @merchbNotificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get merchbNotificationSettings;

  /// No description provided for @merchbShopAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Shop Analytics'**
  String get merchbShopAnalytics;

  /// No description provided for @merchbLogOutAccount.
  ///
  /// In en, this message translates to:
  /// **'Log Out Account'**
  String get merchbLogOutAccount;

  /// No description provided for @riderComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get riderComingSoon;

  /// No description provided for @riderTabAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get riderTabAvailable;

  /// No description provided for @riderTabActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get riderTabActive;

  /// No description provided for @riderTabEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get riderTabEarnings;

  /// No description provided for @riderSegmentDeliveries.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get riderSegmentDeliveries;

  /// No description provided for @riderRegionZone.
  ///
  /// In en, this message translates to:
  /// **'Region zone'**
  String get riderRegionZone;

  /// No description provided for @riderDeliveriesNearby.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No deliveries nearby} =1{1 delivery nearby} other{{count} deliveries nearby}}'**
  String riderDeliveriesNearby(int count);

  /// No description provided for @riderOffersNearYou.
  ///
  /// In en, this message translates to:
  /// **'Offers near you'**
  String get riderOffersNearYou;

  /// No description provided for @riderAcceptDelivery.
  ///
  /// In en, this message translates to:
  /// **'Accept delivery'**
  String get riderAcceptDelivery;

  /// No description provided for @riderMyActiveTasks.
  ///
  /// In en, this message translates to:
  /// **'My active tasks'**
  String get riderMyActiveTasks;

  /// No description provided for @riderActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None active} =1{1 active} other{{count} active}}'**
  String riderActiveCount(int count);

  /// No description provided for @riderOrderRef.
  ///
  /// In en, this message translates to:
  /// **'Order #{ref}'**
  String riderOrderRef(String ref);

  /// No description provided for @riderMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{Just now} =1{1 min ago} other{{minutes} min ago}}'**
  String riderMinutesAgo(int minutes);

  /// No description provided for @riderHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hr ago} other{{hours} hrs ago}}'**
  String riderHoursAgo(int hours);

  /// No description provided for @riderNavigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get riderNavigate;

  /// No description provided for @riderViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get riderViewDetails;

  /// No description provided for @riderStartNavigation.
  ///
  /// In en, this message translates to:
  /// **'Start navigation'**
  String get riderStartNavigation;

  /// No description provided for @riderYourPayout.
  ///
  /// In en, this message translates to:
  /// **'Your payout'**
  String get riderYourPayout;

  /// No description provided for @riderRouteTimeline.
  ///
  /// In en, this message translates to:
  /// **'Route timeline'**
  String get riderRouteTimeline;

  /// No description provided for @riderPickupAddress.
  ///
  /// In en, this message translates to:
  /// **'Pickup address'**
  String get riderPickupAddress;

  /// No description provided for @riderDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get riderDeliveryAddress;

  /// No description provided for @riderItemsToCollect.
  ///
  /// In en, this message translates to:
  /// **'Items to collect'**
  String get riderItemsToCollect;

  /// No description provided for @riderItemLine.
  ///
  /// In en, this message translates to:
  /// **'{qty}x {name}'**
  String riderItemLine(int qty, String name);

  /// No description provided for @riderNoItemsListed.
  ///
  /// In en, this message translates to:
  /// **'This order has no itemised list.'**
  String get riderNoItemsListed;

  /// No description provided for @riderDeliveryInstructions.
  ///
  /// In en, this message translates to:
  /// **'Delivery instructions'**
  String get riderDeliveryInstructions;

  /// No description provided for @riderMyEarnings.
  ///
  /// In en, this message translates to:
  /// **'My earnings'**
  String get riderMyEarnings;

  /// No description provided for @riderPayout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get riderPayout;

  /// No description provided for @riderPeriodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get riderPeriodToday;

  /// No description provided for @riderPeriodWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get riderPeriodWeekly;

  /// No description provided for @riderTotalEarnings.
  ///
  /// In en, this message translates to:
  /// **'Total earnings'**
  String get riderTotalEarnings;

  /// No description provided for @riderEarningsDerived.
  ///
  /// In en, this message translates to:
  /// **'Added up from the delivery fees on your own completed deliveries.'**
  String get riderEarningsDerived;

  /// No description provided for @riderHoursOnline.
  ///
  /// In en, this message translates to:
  /// **'Hours online'**
  String get riderHoursOnline;

  /// No description provided for @riderAcceptRate.
  ///
  /// In en, this message translates to:
  /// **'Accept rate'**
  String get riderAcceptRate;

  /// No description provided for @riderRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get riderRating;

  /// No description provided for @riderWeeklyOverview.
  ///
  /// In en, this message translates to:
  /// **'Weekly overview'**
  String get riderWeeklyOverview;

  /// No description provided for @riderTodaysDeliveries.
  ///
  /// In en, this message translates to:
  /// **'Today\'s deliveries'**
  String get riderTodaysDeliveries;

  /// No description provided for @riderThisWeeksDeliveries.
  ///
  /// In en, this message translates to:
  /// **'This week\'s deliveries'**
  String get riderThisWeeksDeliveries;

  /// No description provided for @riderNothingDeliveredYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing delivered in this period yet.'**
  String get riderNothingDeliveredYet;

  /// No description provided for @riderCouldNotLoadEarnings.
  ///
  /// In en, this message translates to:
  /// **'Could not load your earnings'**
  String get riderCouldNotLoadEarnings;

  /// No description provided for @riderDriverSettings.
  ///
  /// In en, this message translates to:
  /// **'Driver settings'**
  String get riderDriverSettings;

  /// No description provided for @riderVehicleProfile.
  ///
  /// In en, this message translates to:
  /// **'Vehicle profile'**
  String get riderVehicleProfile;

  /// No description provided for @riderActiveDuty.
  ///
  /// In en, this message translates to:
  /// **'Active duty (online)'**
  String get riderActiveDuty;

  /// No description provided for @riderAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get riderAppLanguage;

  /// No description provided for @riderDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents & licences'**
  String get riderDocuments;

  /// No description provided for @riderBankDetails.
  ///
  /// In en, this message translates to:
  /// **'Bank account details'**
  String get riderBankDetails;

  /// No description provided for @riderNotificationPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get riderNotificationPreferences;

  /// No description provided for @riderHelpAndSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & live chat support'**
  String get riderHelpAndSupport;

  /// No description provided for @riderErrandTry.
  ///
  /// In en, this message translates to:
  /// **'Try'**
  String get riderErrandTry;

  /// No description provided for @riderErrandTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get riderErrandTo;

  /// No description provided for @riderErrandCap.
  ///
  /// In en, this message translates to:
  /// **'Cap'**
  String get riderErrandCap;

  /// No description provided for @etaWaitingFirstFix.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the rider\'s first GPS fix'**
  String get etaWaitingFirstFix;

  /// No description provided for @etaPositionOutOfDate.
  ///
  /// In en, this message translates to:
  /// **'The rider\'s position is out of date'**
  String get etaPositionOutOfDate;

  /// No description provided for @etaNoMapPoint.
  ///
  /// In en, this message translates to:
  /// **'No map point to measure to'**
  String get etaNoMapPoint;

  /// No description provided for @etaRouteServiceDown.
  ///
  /// In en, this message translates to:
  /// **'The route service did not answer'**
  String get etaRouteServiceDown;

  /// No description provided for @etaNothingOnItsWay.
  ///
  /// In en, this message translates to:
  /// **'Nothing is on its way'**
  String get etaNothingOnItsWay;

  /// No description provided for @etaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No estimate available'**
  String get etaUnavailable;

  /// No description provided for @etaHeadingToShop.
  ///
  /// In en, this message translates to:
  /// **'Heading to the shop'**
  String get etaHeadingToShop;

  /// No description provided for @etaOnTheWayToYou.
  ///
  /// In en, this message translates to:
  /// **'On the way to you'**
  String get etaOnTheWayToYou;

  /// No description provided for @etaStraightLineNote.
  ///
  /// In en, this message translates to:
  /// **'Rough estimate — measured in a straight line, not by road'**
  String get etaStraightLineNote;

  /// No description provided for @dutyOnDuty.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get dutyOnDuty;

  /// No description provided for @dutyOffDuty.
  ///
  /// In en, this message translates to:
  /// **'Off duty'**
  String get dutyOffDuty;

  /// No description provided for @presenceSignalLost.
  ///
  /// In en, this message translates to:
  /// **'Signal lost'**
  String get presenceSignalLost;

  /// No description provided for @promoApplied.
  ///
  /// In en, this message translates to:
  /// **'The code was applied'**
  String get promoApplied;

  /// No description provided for @promoUnknownCode.
  ///
  /// In en, this message translates to:
  /// **'That code was not recognised'**
  String get promoUnknownCode;

  /// No description provided for @promoNotActive.
  ///
  /// In en, this message translates to:
  /// **'That code is no longer available'**
  String get promoNotActive;

  /// No description provided for @promoNotStarted.
  ///
  /// In en, this message translates to:
  /// **'That code cannot be used yet'**
  String get promoNotStarted;

  /// No description provided for @promoExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired'**
  String get promoExpired;

  /// No description provided for @promoBelowMinimum.
  ///
  /// In en, this message translates to:
  /// **'Your basket is below the minimum for that code'**
  String get promoBelowMinimum;

  /// No description provided for @promoFullyRedeemed.
  ///
  /// In en, this message translates to:
  /// **'That code has been fully redeemed'**
  String get promoFullyRedeemed;

  /// No description provided for @promoAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'You have already used that code'**
  String get promoAlreadyUsed;

  /// No description provided for @promoWorthNothing.
  ///
  /// In en, this message translates to:
  /// **'That code is worth nothing on this order'**
  String get promoWorthNothing;

  /// No description provided for @promoDidNotApply.
  ///
  /// In en, this message translates to:
  /// **'That code did not apply'**
  String get promoDidNotApply;

  /// No description provided for @paymentWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get paymentWallet;

  /// No description provided for @paymentTestModeNote.
  ///
  /// In en, this message translates to:
  /// **'Test payment — no real money moves in this build'**
  String get paymentTestModeNote;

  /// No description provided for @cashOutRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get cashOutRequested;

  /// No description provided for @cashOutPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get cashOutPaid;

  /// No description provided for @cashOutRefused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get cashOutRefused;

  /// No description provided for @paidByPlatform.
  ///
  /// In en, this message translates to:
  /// **'Paid by the platform'**
  String get paidByPlatform;

  /// No description provided for @paidByYourCompany.
  ///
  /// In en, this message translates to:
  /// **'Paid by your company'**
  String get paidByYourCompany;

  /// No description provided for @paidElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Paid elsewhere'**
  String get paidElsewhere;

  /// No description provided for @tipCashAtDoor.
  ///
  /// In en, this message translates to:
  /// **'Cash at the door'**
  String get tipCashAtDoor;

  /// No description provided for @tipOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get tipOnline;

  /// No description provided for @docNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get docNationalId;

  /// No description provided for @docDrivingLicence.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get docDrivingLicence;

  /// No description provided for @docVehicleRegistration.
  ///
  /// In en, this message translates to:
  /// **'Vehicle registration'**
  String get docVehicleRegistration;

  /// No description provided for @docCommercialRegistration.
  ///
  /// In en, this message translates to:
  /// **'Commercial registration'**
  String get docCommercialRegistration;

  /// No description provided for @docTradeLicence.
  ///
  /// In en, this message translates to:
  /// **'Trade License (Certified)'**
  String get docTradeLicence;

  /// No description provided for @docFleetInsurance.
  ///
  /// In en, this message translates to:
  /// **'Fleet Insurance Certificate'**
  String get docFleetInsurance;

  /// No description provided for @docFleetRegistration.
  ///
  /// In en, this message translates to:
  /// **'Rider & Fleet Registrations'**
  String get docFleetRegistration;

  /// No description provided for @docWaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Waiting for review'**
  String get docWaitingReview;

  /// No description provided for @docApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get docApproved;

  /// No description provided for @docRefused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get docRefused;

  /// No description provided for @payoutFormatChecked.
  ///
  /// In en, this message translates to:
  /// **'Format checked'**
  String get payoutFormatChecked;

  /// No description provided for @payoutVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get payoutVerified;

  /// No description provided for @payoutFailedVerification.
  ///
  /// In en, this message translates to:
  /// **'Failed verification'**
  String get payoutFailedVerification;

  /// No description provided for @notifCatOrderUpdates.
  ///
  /// In en, this message translates to:
  /// **'Order updates'**
  String get notifCatOrderUpdates;

  /// No description provided for @notifCatChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get notifCatChat;

  /// No description provided for @notifCatPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get notifCatPromotions;

  /// No description provided for @notifCatAccount.
  ///
  /// In en, this message translates to:
  /// **'Account and security'**
  String get notifCatAccount;

  /// No description provided for @notifChannelPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get notifChannelPush;

  /// No description provided for @notifChannelInApp.
  ///
  /// In en, this message translates to:
  /// **'In-app'**
  String get notifChannelInApp;

  /// No description provided for @notifChannelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get notifChannelEmail;

  /// No description provided for @notifChannelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get notifChannelSms;

  /// No description provided for @chatRoleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get chatRoleCustomer;

  /// No description provided for @chatRoleRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get chatRoleRider;

  /// No description provided for @crossSellBoughtTogether.
  ///
  /// In en, this message translates to:
  /// **'Often bought together'**
  String get crossSellBoughtTogether;

  /// No description provided for @crossSellSameShelf.
  ///
  /// In en, this message translates to:
  /// **'From the same shelf'**
  String get crossSellSameShelf;

  /// No description provided for @crossSellYouMightAlsoLike.
  ///
  /// In en, this message translates to:
  /// **'You might also like'**
  String get crossSellYouMightAlsoLike;

  /// No description provided for @ratingNewRider.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get ratingNewRider;

  /// No description provided for @custTestPayment.
  ///
  /// In en, this message translates to:
  /// **'Test payment'**
  String get custTestPayment;

  /// No description provided for @custPaymentDeclined.
  ///
  /// In en, this message translates to:
  /// **'The payment was declined and your order was not placed.'**
  String get custPaymentDeclined;

  /// No description provided for @custPromoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the code'**
  String get custPromoRemove;

  /// No description provided for @custPromoChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the code…'**
  String get custPromoChecking;

  /// No description provided for @promoCouldNotCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not check the code'**
  String get promoCouldNotCheck;

  /// No description provided for @etaMinShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get etaMinShort;

  /// No description provided for @etaArriving.
  ///
  /// In en, this message translates to:
  /// **'Expected arrival'**
  String get etaArriving;

  /// No description provided for @etaRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get etaRemaining;

  /// No description provided for @custChatWithRider.
  ///
  /// In en, this message translates to:
  /// **'Message the rider'**
  String get custChatWithRider;

  /// No description provided for @chatTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get chatTypeMessage;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatClosed.
  ///
  /// In en, this message translates to:
  /// **'This conversation is closed'**
  String get chatClosed;

  /// No description provided for @chatNoMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatNoMessagesYet;

  /// No description provided for @chatCouldNotSend.
  ///
  /// In en, this message translates to:
  /// **'Could not send your message'**
  String get chatCouldNotSend;

  /// No description provided for @couldNotLoadChat.
  ///
  /// In en, this message translates to:
  /// **'Could not load the conversation'**
  String get couldNotLoadChat;

  /// No description provided for @custRateYourRider.
  ///
  /// In en, this message translates to:
  /// **'Rate your rider'**
  String get custRateYourRider;

  /// No description provided for @custHowWasDelivery.
  ///
  /// In en, this message translates to:
  /// **'How was your delivery?'**
  String get custHowWasDelivery;

  /// No description provided for @custAddCommentOptional.
  ///
  /// In en, this message translates to:
  /// **'Add a comment (optional)'**
  String get custAddCommentOptional;

  /// No description provided for @custSubmitRating.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get custSubmitRating;

  /// No description provided for @custThanksForRating.
  ///
  /// In en, this message translates to:
  /// **'Thanks for rating your rider'**
  String get custThanksForRating;

  /// No description provided for @custAlreadyRatedDelivery.
  ///
  /// In en, this message translates to:
  /// **'You rated this delivery'**
  String get custAlreadyRatedDelivery;

  /// No description provided for @custCouldNotSendRating.
  ///
  /// In en, this message translates to:
  /// **'Could not send your rating'**
  String get custCouldNotSendRating;

  /// No description provided for @ratingStars.
  ///
  /// In en, this message translates to:
  /// **'{n} stars'**
  String ratingStars(Object n);

  /// No description provided for @searchForAPlace.
  ///
  /// In en, this message translates to:
  /// **'Search for a place…'**
  String get searchForAPlace;

  /// No description provided for @noPlacesFound.
  ///
  /// In en, this message translates to:
  /// **'No places found'**
  String get noPlacesFound;

  /// No description provided for @couldNotSearchPlaces.
  ///
  /// In en, this message translates to:
  /// **'Could not search just now'**
  String get couldNotSearchPlaces;

  /// No description provided for @addressPinnedOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pinned on the map'**
  String get addressPinnedOnMap;

  /// No description provided for @notifPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get notifPreferences;

  /// No description provided for @notifPrefsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Choose how we reach you, topic by topic'**
  String get notifPrefsBlurb;

  /// No description provided for @notifAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on — account and security messages cannot be switched off'**
  String get notifAlwaysOn;

  /// No description provided for @couldNotLoadPreferences.
  ///
  /// In en, this message translates to:
  /// **'Could not load your preferences'**
  String get couldNotLoadPreferences;

  /// No description provided for @couldNotSaveThatChange.
  ///
  /// In en, this message translates to:
  /// **'Could not save that change'**
  String get couldNotSaveThatChange;

  /// No description provided for @crossSellTogetherCount.
  ///
  /// In en, this message translates to:
  /// **'{count}× together'**
  String crossSellTogetherCount(Object count);

  /// No description provided for @riderBalanceLine.
  ///
  /// In en, this message translates to:
  /// **'Balance {balance} · available for cash-out {available}'**
  String riderBalanceLine(Object balance, Object available);

  /// No description provided for @riderEarningsBreakdown.
  ///
  /// In en, this message translates to:
  /// **'{earnings} delivery pay · {tips} tips'**
  String riderEarningsBreakdown(Object earnings, Object tips);

  /// No description provided for @riderCashOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash out'**
  String get riderCashOutTitle;

  /// No description provided for @riderCashOutAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available to cash out'**
  String get riderCashOutAvailable;

  /// No description provided for @riderCashOutHeldNote.
  ///
  /// In en, this message translates to:
  /// **'{amount} of it is cash you are still carrying — hand it in to free it up'**
  String riderCashOutHeldNote(Object amount);

  /// No description provided for @riderCashOutMinimum.
  ///
  /// In en, this message translates to:
  /// **'Minimum {amount}'**
  String riderCashOutMinimum(Object amount);

  /// No description provided for @riderCashOutManualNote.
  ///
  /// In en, this message translates to:
  /// **'Payouts are handed over by the platform team — nothing transfers automatically.'**
  String get riderCashOutManualNote;

  /// No description provided for @riderCashOutRequest.
  ///
  /// In en, this message translates to:
  /// **'Request cash-out'**
  String get riderCashOutRequest;

  /// No description provided for @riderCashOutAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get riderCashOutAmountLabel;

  /// No description provided for @riderCashOutAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'A cash-out request is already on its way.'**
  String get riderCashOutAlreadyOpen;

  /// No description provided for @riderCashOutFailed.
  ///
  /// In en, this message translates to:
  /// **'The cash-out could not be requested.'**
  String get riderCashOutFailed;

  /// No description provided for @riderCashOutOpenLine.
  ///
  /// In en, this message translates to:
  /// **'{amount} requested — waiting on the payout'**
  String riderCashOutOpenLine(Object amount);

  /// No description provided for @riderCashOutLastRefused.
  ///
  /// In en, this message translates to:
  /// **'Your last cash-out was refused.'**
  String get riderCashOutLastRefused;

  /// No description provided for @riderCashOutHistory.
  ///
  /// In en, this message translates to:
  /// **'Recent requests'**
  String get riderCashOutHistory;

  /// No description provided for @riderTipLine.
  ///
  /// In en, this message translates to:
  /// **'+{tip} tip'**
  String riderTipLine(Object tip);

  /// No description provided for @riderReimbursedLine.
  ///
  /// In en, this message translates to:
  /// **'+{amount} reimbursed'**
  String riderReimbursedLine(Object amount);

  /// No description provided for @riderLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {when}'**
  String riderLastSeen(Object when);

  /// No description provided for @riderDutyChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update your duty state.'**
  String get riderDutyChangeFailed;

  /// No description provided for @riderDutyNotYetDeclared.
  ///
  /// In en, this message translates to:
  /// **'You have not gone on duty yet.'**
  String get riderDutyNotYetDeclared;

  /// No description provided for @riderEtaCaption.
  ///
  /// In en, this message translates to:
  /// **'Live ETA'**
  String get riderEtaCaption;

  /// No description provided for @riderEtaAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String riderEtaAway(Object distance);

  /// No description provided for @riderEtaArrivingAt.
  ///
  /// In en, this message translates to:
  /// **'arriving about {time}'**
  String riderEtaArrivingAt(Object time);

  /// No description provided for @riderKmUnit.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String riderKmUnit(Object km);

  /// No description provided for @riderMetreUnit.
  ///
  /// In en, this message translates to:
  /// **'{m} m'**
  String riderMetreUnit(Object m);

  /// No description provided for @riderEtaComputedBy.
  ///
  /// In en, this message translates to:
  /// **'Estimated by {provider}'**
  String riderEtaComputedBy(Object provider);

  /// No description provided for @riderChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer chat'**
  String get riderChatTitle;

  /// No description provided for @riderChatHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get riderChatHint;

  /// No description provided for @riderChatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get riderChatSend;

  /// No description provided for @riderChatClosed.
  ///
  /// In en, this message translates to:
  /// **'This conversation has closed.'**
  String get riderChatClosed;

  /// No description provided for @riderChatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get riderChatEmpty;

  /// No description provided for @riderChatCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load the conversation'**
  String get riderChatCouldNotLoad;

  /// No description provided for @riderChatSendFailed.
  ///
  /// In en, this message translates to:
  /// **'The message was not sent.'**
  String get riderChatSendFailed;

  /// No description provided for @riderChatReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get riderChatReconnecting;

  /// No description provided for @wizDocsIntro.
  ///
  /// In en, this message translates to:
  /// **'Clear photos or PDFs. You can replace any document until a decision is made.'**
  String get wizDocsIntro;

  /// No description provided for @wizDocFileTypes.
  ///
  /// In en, this message translates to:
  /// **'Photos and PDFs'**
  String get wizDocFileTypes;

  /// No description provided for @wizDocAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get wizDocAdd;

  /// No description provided for @wizDocReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get wizDocReplace;

  /// No description provided for @wizDocRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get wizDocRemove;

  /// No description provided for @wizDocReadyToSend.
  ///
  /// In en, this message translates to:
  /// **'Ready to send'**
  String get wizDocReadyToSend;

  /// No description provided for @wizDocNotAddedYet.
  ///
  /// In en, this message translates to:
  /// **'Not added yet'**
  String get wizDocNotAddedYet;

  /// No description provided for @wizDocSentOnSubmit.
  ///
  /// In en, this message translates to:
  /// **'Your documents are sent when you submit the application.'**
  String get wizDocSentOnSubmit;

  /// No description provided for @wizDocTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large'**
  String get wizDocTooLarge;

  /// No description provided for @wizDocUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'The upload did not go through'**
  String get wizDocUploadFailed;

  /// No description provided for @wizDocUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get wizDocUploading;

  /// No description provided for @wizDocCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your documents'**
  String get wizDocCouldNotLoad;

  /// No description provided for @wizDocsPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your documents'**
  String get wizDocsPendingTitle;

  /// No description provided for @wizDocsPendingBlurb.
  ///
  /// In en, this message translates to:
  /// **'A refused document can be replaced and will be reviewed again.'**
  String get wizDocsPendingBlurb;

  /// No description provided for @wizDocsNoneYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing uploaded yet'**
  String get wizDocsNoneYet;

  /// No description provided for @wizCouldNotSendDocuments.
  ///
  /// In en, this message translates to:
  /// **'Your application is in, but a document did not go through.'**
  String get wizCouldNotSendDocuments;

  /// No description provided for @wizPayoutAccountHolder.
  ///
  /// In en, this message translates to:
  /// **'Account holder'**
  String get wizPayoutAccountHolder;

  /// No description provided for @wizPayoutAccountHolderHint.
  ///
  /// In en, this message translates to:
  /// **'The name exactly as the bank has it'**
  String get wizPayoutAccountHolderHint;

  /// No description provided for @wizPayoutIban.
  ///
  /// In en, this message translates to:
  /// **'IBAN'**
  String get wizPayoutIban;

  /// No description provided for @wizPayoutIbanHint.
  ///
  /// In en, this message translates to:
  /// **'Starts with the country code, e.g. SA…'**
  String get wizPayoutIbanHint;

  /// No description provided for @wizPayoutIbanInvalid.
  ///
  /// In en, this message translates to:
  /// **'That IBAN does not check out — a digit is probably wrong or two are swapped'**
  String get wizPayoutIbanInvalid;

  /// No description provided for @wizPayoutIbanFormat.
  ///
  /// In en, this message translates to:
  /// **'An IBAN starts with two letters for the country and two check digits'**
  String get wizPayoutIbanFormat;

  /// No description provided for @wizPayoutIbanBounds.
  ///
  /// In en, this message translates to:
  /// **'An IBAN is between 15 and 34 characters'**
  String get wizPayoutIbanBounds;

  /// No description provided for @wizPayoutIbanLength.
  ///
  /// In en, this message translates to:
  /// **'An IBAN for {country} is {expected} characters'**
  String wizPayoutIbanLength(Object country, Object expected);

  /// No description provided for @wizPayoutCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'The bank details could not be saved'**
  String get wizPayoutCouldNotSave;

  /// No description provided for @wizPayoutCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your bank details'**
  String get wizPayoutCouldNotLoad;

  /// No description provided for @wizPayoutSave.
  ///
  /// In en, this message translates to:
  /// **'Save bank details'**
  String get wizPayoutSave;

  /// No description provided for @wizPayoutChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get wizPayoutChange;

  /// No description provided for @wizPayoutSentOnSubmit.
  ///
  /// In en, this message translates to:
  /// **'Your bank details are sent when you submit the application.'**
  String get wizPayoutSentOnSubmit;

  /// No description provided for @wizCouldNotSendPayout.
  ///
  /// In en, this message translates to:
  /// **'Your application is in, but the bank details did not go through.'**
  String get wizCouldNotSendPayout;

  /// No description provided for @merchPinShopLocation.
  ///
  /// In en, this message translates to:
  /// **'Shop location'**
  String get merchPinShopLocation;

  /// No description provided for @merchPinDropHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to put the pin on your shop, then save.'**
  String get merchPinDropHint;

  /// No description provided for @merchPinWhyItMatters.
  ///
  /// In en, this message translates to:
  /// **'Customers see this pin, and delivery distance is measured from it.'**
  String get merchPinWhyItMatters;

  /// No description provided for @merchPinNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No location pinned yet'**
  String get merchPinNoneYet;

  /// No description provided for @merchPinSetIt.
  ///
  /// In en, this message translates to:
  /// **'Set location'**
  String get merchPinSetIt;

  /// No description provided for @merchPinSaved.
  ///
  /// In en, this message translates to:
  /// **'Shop location saved'**
  String get merchPinSaved;

  /// No description provided for @merchPinCleared.
  ///
  /// In en, this message translates to:
  /// **'Shop location removed'**
  String get merchPinCleared;

  /// No description provided for @merchMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Map could not load'**
  String get merchMapUnavailable;

  /// No description provided for @merchUpOnPrevious.
  ///
  /// In en, this message translates to:
  /// **'{percent}% up on the {days} days before'**
  String merchUpOnPrevious(Object percent, Object days);

  /// No description provided for @merchDownOnPrevious.
  ///
  /// In en, this message translates to:
  /// **'{percent}% down on the {days} days before'**
  String merchDownOnPrevious(Object percent, Object days);

  /// No description provided for @merchSameAsPrevious.
  ///
  /// In en, this message translates to:
  /// **'Same as the {days} days before'**
  String merchSameAsPrevious(Object days);

  /// No description provided for @merchNonePrevious.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the {days} days before'**
  String merchNonePrevious(Object days);

  /// No description provided for @merchNothingEitherPeriod.
  ///
  /// In en, this message translates to:
  /// **'Nothing in either period'**
  String get merchNothingEitherPeriod;

  /// No description provided for @merchAnalyticsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Every day in the window, split by how fast the customer asked for the delivery.'**
  String get merchAnalyticsBlurb;

  /// No description provided for @merchTierSplit.
  ///
  /// In en, this message translates to:
  /// **'By delivery speed'**
  String get merchTierSplit;

  /// No description provided for @merchOrderValue.
  ///
  /// In en, this message translates to:
  /// **'Order value'**
  String get merchOrderValue;

  /// No description provided for @merchOrderValueNote.
  ///
  /// In en, this message translates to:
  /// **'What customers paid in total, delivery and any express premium included — not your payout.'**
  String get merchOrderValueNote;

  /// No description provided for @deliveryTierStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get deliveryTierStandard;

  /// No description provided for @deliveryTierExpress.
  ///
  /// In en, this message translates to:
  /// **'Express'**
  String get deliveryTierExpress;

  /// No description provided for @custPinYourDoor.
  ///
  /// In en, this message translates to:
  /// **'Pin your door'**
  String get custPinYourDoor;

  /// No description provided for @custSetHere.
  ///
  /// In en, this message translates to:
  /// **'Set here'**
  String get custSetHere;

  /// No description provided for @locMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get locMyLocation;

  /// No description provided for @locServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off on this phone.'**
  String get locServicesOff;

  /// No description provided for @locTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get locTurnOn;

  /// No description provided for @locPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Allow location access to point the map at you.'**
  String get locPermissionNeeded;

  /// No description provided for @locOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get locOpenSettings;

  /// No description provided for @locNoFix.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Try again in the open.'**
  String get locNoFix;

  /// No description provided for @custNamingThisPlace.
  ///
  /// In en, this message translates to:
  /// **'Looking up this place…'**
  String get custNamingThisPlace;

  /// No description provided for @custMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The map could not load. The address you type is what we will use.'**
  String get custMapUnavailable;

  /// No description provided for @custYourAddress.
  ///
  /// In en, this message translates to:
  /// **'Your address'**
  String get custYourAddress;

  /// No description provided for @custTheRider.
  ///
  /// In en, this message translates to:
  /// **'The rider'**
  String get custTheRider;

  /// No description provided for @custDeliverySpeed.
  ///
  /// In en, this message translates to:
  /// **'Delivery speed'**
  String get custDeliverySpeed;

  /// No description provided for @custExpressSurchargeApplies.
  ///
  /// In en, this message translates to:
  /// **'Surcharge applies'**
  String get custExpressSurchargeApplies;

  /// No description provided for @custExpressNote.
  ///
  /// In en, this message translates to:
  /// **'Express costs extra. The platform sets the amount and your receipt shows it as its own line. A free-delivery offer does not cover it.'**
  String get custExpressNote;

  /// No description provided for @authResetYourPasscode.
  ///
  /// In en, this message translates to:
  /// **'Reset your passcode'**
  String get authResetYourPasscode;

  /// No description provided for @authChangeYourPasscode.
  ///
  /// In en, this message translates to:
  /// **'Change your passcode'**
  String get authChangeYourPasscode;

  /// No description provided for @authResetAskForAddress.
  ///
  /// In en, this message translates to:
  /// **'Tell us the email on your account. If it has one, a six-digit code goes to it.'**
  String get authResetAskForAddress;

  /// No description provided for @authResetToYourAddress.
  ///
  /// In en, this message translates to:
  /// **'A six-digit code goes to the email on your account.'**
  String get authResetToYourAddress;

  /// No description provided for @authResetCodeMaybeSent.
  ///
  /// In en, this message translates to:
  /// **'If {destination} has an account, a 6-digit code is on its way. It expires in 10 minutes and can be used once.'**
  String authResetCodeMaybeSent(Object destination);

  /// No description provided for @authSetNewPasscode.
  ///
  /// In en, this message translates to:
  /// **'Set new passcode'**
  String get authSetNewPasscode;

  /// No description provided for @authPasscodeChanged.
  ///
  /// In en, this message translates to:
  /// **'Passcode changed'**
  String get authPasscodeChanged;

  /// No description provided for @authPasscodeChangedSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your new six-digit passcode.'**
  String get authPasscodeChangedSignIn;

  /// No description provided for @authPasscodeChangedSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Use your new six-digit passcode the next time you sign in.'**
  String get authPasscodeChangedSignedIn;

  /// No description provided for @custProfileFieldsFixed.
  ///
  /// In en, this message translates to:
  /// **'Your name and email were set when the account was created and cannot be changed from the app yet.'**
  String get custProfileFieldsFixed;

  /// No description provided for @custNoEmailOnAccount.
  ///
  /// In en, this message translates to:
  /// **'This account has no email address on it, so there is nowhere to send a code.'**
  String get custNoEmailOnAccount;

  /// No description provided for @custCouldNotOpenThat.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this phone could open that.'**
  String get custCouldNotOpenThat;

  /// No description provided for @custHelpIntro.
  ///
  /// In en, this message translates to:
  /// **'Answers to the things people ask most, and the ways to reach a person when the answer is not here.'**
  String get custHelpIntro;

  /// No description provided for @custHelpTalkToUs.
  ///
  /// In en, this message translates to:
  /// **'Talk to us'**
  String get custHelpTalkToUs;

  /// No description provided for @custChatOnWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Chat on WhatsApp'**
  String get custChatOnWhatsApp;

  /// No description provided for @custEmailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email support'**
  String get custEmailSupport;

  /// No description provided for @custHelpNoChannelsYet.
  ///
  /// In en, this message translates to:
  /// **'No support channel is set up in this build yet. Your orders still carry a chat with the rider once one is assigned.'**
  String get custHelpNoChannelsYet;

  /// No description provided for @custHelpOrdering.
  ///
  /// In en, this message translates to:
  /// **'Ordering'**
  String get custHelpOrdering;

  /// No description provided for @custHelpDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get custHelpDelivery;

  /// No description provided for @custHelpPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get custHelpPayments;

  /// No description provided for @custHelpAccount.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get custHelpAccount;

  /// No description provided for @custHelpApplying.
  ///
  /// In en, this message translates to:
  /// **'Selling and riding'**
  String get custHelpApplying;

  /// No description provided for @custFaqOneShopQ.
  ///
  /// In en, this message translates to:
  /// **'Why can my basket only hold one shop?'**
  String get custFaqOneShopQ;

  /// No description provided for @custFaqOneShopA.
  ///
  /// In en, this message translates to:
  /// **'One order goes to one shop and is carried by one rider. Two shops means two collections, two fees and two journeys, so the basket asks you to finish one before starting the other.'**
  String get custFaqOneShopA;

  /// No description provided for @custFaqMinimumQ.
  ///
  /// In en, this message translates to:
  /// **'What is a minimum order?'**
  String get custFaqMinimumQ;

  /// No description provided for @custFaqMinimumA.
  ///
  /// In en, this message translates to:
  /// **'Some shops will not send a rider out below a certain amount. The basket shows the shop\'s minimum and exactly how much is still missing, and checkout stays closed until it is met.'**
  String get custFaqMinimumA;

  /// No description provided for @custFaqChangeOrderQ.
  ///
  /// In en, this message translates to:
  /// **'Can I change or cancel an order?'**
  String get custFaqChangeOrderQ;

  /// No description provided for @custFaqChangeOrderA.
  ///
  /// In en, this message translates to:
  /// **'An order cannot be edited after it is placed. The order page lists what you can still do with it, and cancelling leaves that list once the shop has started preparing. Once a rider is assigned you can message them from the order page.'**
  String get custFaqChangeOrderA;

  /// No description provided for @custFaqTiersQ.
  ///
  /// In en, this message translates to:
  /// **'What is the difference between Standard and Express?'**
  String get custFaqTiersQ;

  /// No description provided for @custFaqTiersA.
  ///
  /// In en, this message translates to:
  /// **'Express asks for the order to be treated as urgent and adds a surcharge on top of the delivery fee. The platform sets that amount, not the shop, and your receipt shows it as its own line. A free-delivery offer covers the delivery fee only — the express surcharge stays payable.'**
  String get custFaqTiersA;

  /// No description provided for @custFaqWhereIsRiderQ.
  ///
  /// In en, this message translates to:
  /// **'Where is my rider?'**
  String get custFaqWhereIsRiderQ;

  /// No description provided for @custFaqWhereIsRiderA.
  ///
  /// In en, this message translates to:
  /// **'The order page draws the rider\'s recorded positions on a map from the moment they collect your order. The arrival time comes from the tracking service; when it has no recent position to measure from, it says so instead of showing a guess.'**
  String get custFaqWhereIsRiderA;

  /// No description provided for @custFaqDeliveryFeeQ.
  ///
  /// In en, this message translates to:
  /// **'How is the delivery fee worked out?'**
  String get custFaqDeliveryFeeQ;

  /// No description provided for @custFaqDeliveryFeeA.
  ///
  /// In en, this message translates to:
  /// **'By the area you are delivering to, which is why a saved address carries an area. A promotion can waive it, and when it does the basket names the promotion rather than only showing a zero.'**
  String get custFaqDeliveryFeeA;

  /// No description provided for @custFaqAddressPinQ.
  ///
  /// In en, this message translates to:
  /// **'Why should I drop a pin on the map?'**
  String get custFaqAddressPinQ;

  /// No description provided for @custFaqAddressPinA.
  ///
  /// In en, this message translates to:
  /// **'A typed line gets the rider to the street; the pin gets them to the door, and it is the point the arrival time is measured against. Without one your order still arrives, but there is nothing on the map to estimate from.'**
  String get custFaqAddressPinA;

  /// No description provided for @custFaqPayMethodsQ.
  ///
  /// In en, this message translates to:
  /// **'Which payment methods really work?'**
  String get custFaqPayMethodsQ;

  /// No description provided for @custFaqPayMethodsA.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery is the only method in this build that moves real money. Card and wallet are wired to a test payment provider and are labelled \"Test payment\" at checkout: choosing one authorises against that provider and nothing is charged.'**
  String get custFaqPayMethodsA;

  /// No description provided for @custFaqPromoQ.
  ///
  /// In en, this message translates to:
  /// **'How do promo codes work?'**
  String get custFaqPromoQ;

  /// No description provided for @custFaqPromoA.
  ///
  /// In en, this message translates to:
  /// **'Type one in the basket and it is checked against what is in the basket right then, so a code can start applying the moment you cross its minimum. What is actually billed is recomputed by the server when the order is placed, and the confirmation shows that figure.'**
  String get custFaqPromoA;

  /// No description provided for @custFaqRefundQ.
  ///
  /// In en, this message translates to:
  /// **'How do I get a refund?'**
  String get custFaqRefundQ;

  /// No description provided for @custFaqRefundA.
  ///
  /// In en, this message translates to:
  /// **'There is no refund button in the app. Cash orders are settled at the door, so a problem with one is sorted with us directly — message or email support with your order number and what went wrong.'**
  String get custFaqRefundA;

  /// No description provided for @custFaqPasscodeQ.
  ///
  /// In en, this message translates to:
  /// **'I forgot my passcode.'**
  String get custFaqPasscodeQ;

  /// No description provided for @custFaqPasscodeA.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Forgot password?\" on the sign-in screen. A six-digit code goes to the email on the account, lasts ten minutes and works once. From inside the app the same steps are under Edit on this screen.'**
  String get custFaqPasscodeA;

  /// No description provided for @custFaqProfileQ.
  ///
  /// In en, this message translates to:
  /// **'Can I change my name or email?'**
  String get custFaqProfileQ;

  /// No description provided for @custFaqProfileA.
  ///
  /// In en, this message translates to:
  /// **'Not from the app yet. They were set when the account was created; the passcode is the one thing on the account you can change yourself.'**
  String get custFaqProfileA;

  /// No description provided for @custFaqApplyQ.
  ///
  /// In en, this message translates to:
  /// **'How do I sell on YouDrop, or deliver for it?'**
  String get custFaqApplyQ;

  /// No description provided for @custFaqApplyA.
  ///
  /// In en, this message translates to:
  /// **'From the welcome screen, before signing in: choose shop or rider and fill in the application. You will be asked for contact details, documents and payout details, and you get an account at the end so you can sign in and follow it.'**
  String get custFaqApplyA;

  /// No description provided for @custFaqApplyWaitQ.
  ///
  /// In en, this message translates to:
  /// **'How long does an application take?'**
  String get custFaqApplyWaitQ;

  /// No description provided for @custFaqApplyWaitA.
  ///
  /// In en, this message translates to:
  /// **'A person reads it, so there is no fixed time. Your application screen shows the stage it is at and whether any document was sent back for a correction — that screen is the status, and nothing is decided automatically.'**
  String get custFaqApplyWaitA;

  /// No description provided for @deliveryTierExpressSurcharge.
  ///
  /// In en, this message translates to:
  /// **'Express +{amount}'**
  String deliveryTierExpressSurcharge(Object amount);

  /// No description provided for @riderTierExpress.
  ///
  /// In en, this message translates to:
  /// **'Express'**
  String get riderTierExpress;

  /// No description provided for @riderCompletionRate.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get riderCompletionRate;

  /// No description provided for @riderHoursValue.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String riderHoursValue(Object hours);

  /// No description provided for @riderPerformanceLine.
  ///
  /// In en, this message translates to:
  /// **'{delivered} of {claimed} claimed jobs delivered in {days} days'**
  String riderPerformanceLine(Object delivered, Object claimed, Object days);

  /// No description provided for @riderPerformanceDropped.
  ///
  /// In en, this message translates to:
  /// **' · {count} dropped after claiming'**
  String riderPerformanceDropped(Object count);

  /// No description provided for @ratingWithCount.
  ///
  /// In en, this message translates to:
  /// **'{average} · {ratings} ratings'**
  String ratingWithCount(Object average, Object ratings);

  /// No description provided for @riderMapYouAreHere.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get riderMapYouAreHere;

  /// No description provided for @riderMapNoFixYet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your first GPS fix'**
  String get riderMapNoFixYet;

  /// No description provided for @riderMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Map unavailable'**
  String get riderMapUnavailable;

  /// No description provided for @riderNavigateFailed.
  ///
  /// In en, this message translates to:
  /// **'No map app could be opened.'**
  String get riderNavigateFailed;

  /// No description provided for @riderRegionAllAreas.
  ///
  /// In en, this message translates to:
  /// **'Every area'**
  String get riderRegionAllAreas;

  /// No description provided for @riderHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get riderHelpTitle;

  /// No description provided for @riderHelpConversations.
  ///
  /// In en, this message translates to:
  /// **'Your conversations'**
  String get riderHelpConversations;

  /// No description provided for @riderHelpNoConversations.
  ///
  /// In en, this message translates to:
  /// **'A chat opens with the customer on every job you are assigned.'**
  String get riderHelpNoConversations;

  /// No description provided for @riderHelpCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your conversations'**
  String get riderHelpCouldNotLoad;

  /// No description provided for @riderHelpOrderThread.
  ///
  /// In en, this message translates to:
  /// **'Order {ref}'**
  String riderHelpOrderThread(Object ref);

  /// No description provided for @riderHelpThreadClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get riderHelpThreadClosed;

  /// No description provided for @riderHelpHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How this works'**
  String get riderHelpHowItWorks;

  /// No description provided for @riderHelpDuty.
  ///
  /// In en, this message translates to:
  /// **'You only receive work while you are on duty and your phone is reporting its position.'**
  String get riderHelpDuty;

  /// No description provided for @riderHelpClaim.
  ///
  /// In en, this message translates to:
  /// **'A job is yours the moment you accept it. If someone accepted it first, the board says so.'**
  String get riderHelpClaim;

  /// No description provided for @riderHelpCashOut.
  ///
  /// In en, this message translates to:
  /// **'Cash-out is requested from the Earnings tab and handed over by the platform team.'**
  String get riderHelpCashOut;

  /// No description provided for @riderHelpExpress.
  ///
  /// In en, this message translates to:
  /// **'An Express job is a customer who paid for speed. The premium is the platform\'s, not part of your fee.'**
  String get riderHelpExpress;

  /// No description provided for @riderDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents & licences'**
  String get riderDocumentsTitle;

  /// No description provided for @riderDocumentsCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your documents'**
  String get riderDocumentsCouldNotLoad;

  /// No description provided for @riderPayoutCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your bank details'**
  String get riderPayoutCouldNotLoad;

  /// No description provided for @authPinYourArea.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to mark where you will be working'**
  String get authPinYourArea;

  /// No description provided for @authPinnedAt.
  ///
  /// In en, this message translates to:
  /// **'Pinned at {lat}, {lng}'**
  String authPinnedAt(Object lat, Object lng);

  /// No description provided for @authPinClear.
  ///
  /// In en, this message translates to:
  /// **'Remove pin'**
  String get authPinClear;

  /// No description provided for @authMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Map unavailable'**
  String get authMapUnavailable;

  /// No description provided for @riderStatementTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation'**
  String get riderStatementTitle;

  /// No description provided for @riderStatementRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cash you are holding, against what you have earned'**
  String get riderStatementRowSubtitle;

  /// No description provided for @riderStatementPeriodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get riderStatementPeriodThisMonth;

  /// No description provided for @riderStatementPeriodLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get riderStatementPeriodLastMonth;

  /// No description provided for @riderStatementRangeLine.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to}'**
  String riderStatementRangeLine(Object from, Object to);

  /// No description provided for @riderStatementGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Worked out {when}'**
  String riderStatementGeneratedAt(Object when);

  /// No description provided for @riderStatementCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your statement'**
  String get riderStatementCouldNotLoad;

  /// No description provided for @riderStatementNothingYet.
  ///
  /// In en, this message translates to:
  /// **'No money moved in this period.'**
  String get riderStatementNothingYet;

  /// No description provided for @riderStatementSummary.
  ///
  /// In en, this message translates to:
  /// **'How it adds up'**
  String get riderStatementSummary;

  /// No description provided for @riderStatementOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders in this period'**
  String get riderStatementOrders;

  /// No description provided for @riderStatementCollectedLine.
  ///
  /// In en, this message translates to:
  /// **'You collected {amount} at the door'**
  String riderStatementCollectedLine(Object amount);

  /// No description provided for @riderStatementYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe the platform'**
  String get riderStatementYouOwe;

  /// No description provided for @riderStatementOwedToYou.
  ///
  /// In en, this message translates to:
  /// **'The platform owes you'**
  String get riderStatementOwedToYou;

  /// No description provided for @riderStatementSettled.
  ///
  /// In en, this message translates to:
  /// **'Nothing outstanding either way'**
  String get riderStatementSettled;

  /// No description provided for @riderStatementDirectionUnclear.
  ///
  /// In en, this message translates to:
  /// **'This balance could not be read'**
  String get riderStatementDirectionUnclear;

  /// No description provided for @riderStatementDebtNote.
  ///
  /// In en, this message translates to:
  /// **'This is normal. Cash you take at the door belongs to the platform until you hand it over — it is not a deduction from your pay.'**
  String get riderStatementDebtNote;

  /// No description provided for @riderStatementCreditNote.
  ///
  /// In en, this message translates to:
  /// **'This is your money, still to reach you.'**
  String get riderStatementCreditNote;

  /// No description provided for @riderStatementSettledNote.
  ///
  /// In en, this message translates to:
  /// **'Everything you have collected has been accounted for.'**
  String get riderStatementSettledNote;

  /// No description provided for @riderStatementUnclearNote.
  ///
  /// In en, this message translates to:
  /// **'This app could not tell which way this balance points. Ask the platform before acting on it.'**
  String get riderStatementUnclearNote;

  /// No description provided for @navPos.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get navPos;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get navStaff;

  /// No description provided for @dashSwitchToPos.
  ///
  /// In en, this message translates to:
  /// **'Switch to POS mode'**
  String get dashSwitchToPos;

  /// No description provided for @dashWalkInSalesToday.
  ///
  /// In en, this message translates to:
  /// **'Walk-in sales today'**
  String get dashWalkInSalesToday;

  /// No description provided for @dashCashPayouts.
  ///
  /// In en, this message translates to:
  /// **'Cash taken'**
  String get dashCashPayouts;

  /// No description provided for @dashCardPayouts.
  ///
  /// In en, this message translates to:
  /// **'Card taken'**
  String get dashCardPayouts;

  /// No description provided for @dashLowStockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Low stock alerts'**
  String get dashLowStockAlerts;

  /// No description provided for @dashQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get dashQuickActions;

  /// No description provided for @dashNewSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get dashNewSale;

  /// No description provided for @dashAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get dashAddProduct;

  /// No description provided for @dashStockCount.
  ///
  /// In en, this message translates to:
  /// **'Stock count'**
  String get dashStockCount;

  /// No description provided for @dashViewReports.
  ///
  /// In en, this message translates to:
  /// **'View reports'**
  String get dashViewReports;

  /// No description provided for @posTitle.
  ///
  /// In en, this message translates to:
  /// **'Point of sale'**
  String get posTitle;

  /// No description provided for @posSearchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products, SKU or barcode'**
  String get posSearchProducts;

  /// No description provided for @posScanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get posScanBarcode;

  /// No description provided for @posNoProducts.
  ///
  /// In en, this message translates to:
  /// **'No products to sell yet'**
  String get posNoProducts;

  /// No description provided for @posNoProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Add a product to your catalogue and it appears here.'**
  String get posNoProductsHint;

  /// No description provided for @posCouldNotLoadCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Could not load the catalogue'**
  String get posCouldNotLoadCatalogue;

  /// No description provided for @posCart.
  ///
  /// In en, this message translates to:
  /// **'Current sale'**
  String get posCart;

  /// No description provided for @posCartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing rung up yet'**
  String get posCartEmpty;

  /// No description provided for @posCartEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a product to start the sale.'**
  String get posCartEmptyHint;

  /// No description provided for @posLinesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String posLinesCount(int count);

  /// No description provided for @posSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posSubtotal;

  /// No description provided for @posDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posDiscount;

  /// No description provided for @posTax.
  ///
  /// In en, this message translates to:
  /// **'VAT'**
  String get posTax;

  /// No description provided for @posTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posTotal;

  /// No description provided for @posPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get posPaid;

  /// No description provided for @posOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Still due'**
  String get posOutstanding;

  /// No description provided for @posRefundedAmount.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get posRefundedAmount;

  /// No description provided for @posUsd.
  ///
  /// In en, this message translates to:
  /// **'\${amount}'**
  String posUsd(String amount);

  /// No description provided for @posLbp.
  ///
  /// In en, this message translates to:
  /// **'{amount} LBP'**
  String posLbp(String amount);

  /// No description provided for @posRate.
  ///
  /// In en, this message translates to:
  /// **'1 USD = {rate} LBP'**
  String posRate(String rate);

  /// No description provided for @posCharge.
  ///
  /// In en, this message translates to:
  /// **'Charge'**
  String get posCharge;

  /// No description provided for @posClearSale.
  ///
  /// In en, this message translates to:
  /// **'Clear sale'**
  String get posClearSale;

  /// No description provided for @posQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get posQuantity;

  /// No description provided for @posRemoveLine.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get posRemoveLine;

  /// No description provided for @posAddOpenItem.
  ///
  /// In en, this message translates to:
  /// **'Add open item'**
  String get posAddOpenItem;

  /// No description provided for @posOpenItem.
  ///
  /// In en, this message translates to:
  /// **'Open item'**
  String get posOpenItem;

  /// No description provided for @posOpenItemName.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get posOpenItemName;

  /// No description provided for @posOpenItemPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get posOpenItemPrice;

  /// No description provided for @posDiscountTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply a discount'**
  String get posDiscountTitle;

  /// No description provided for @posDiscountAmount.
  ///
  /// In en, this message translates to:
  /// **'Discount amount'**
  String get posDiscountAmount;

  /// No description provided for @posDiscountNote.
  ///
  /// In en, this message translates to:
  /// **'Why? (optional)'**
  String get posDiscountNote;

  /// No description provided for @posApplyDiscount.
  ///
  /// In en, this message translates to:
  /// **'Apply discount'**
  String get posApplyDiscount;

  /// No description provided for @posDiscountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That is more than you may discount. Ask a manager.'**
  String get posDiscountTooLarge;

  /// No description provided for @posCouldNotLoadSale.
  ///
  /// In en, this message translates to:
  /// **'Could not load this sale'**
  String get posCouldNotLoadSale;

  /// No description provided for @posTerminalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The register is not available yet.'**
  String get posTerminalUnavailable;

  /// No description provided for @posCheckout.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get posCheckout;

  /// No description provided for @posTenderMethod.
  ///
  /// In en, this message translates to:
  /// **'How are they paying?'**
  String get posTenderMethod;

  /// No description provided for @posCashUsd.
  ///
  /// In en, this message translates to:
  /// **'Cash (USD)'**
  String get posCashUsd;

  /// No description provided for @posCashLbp.
  ///
  /// In en, this message translates to:
  /// **'Cash (LBP)'**
  String get posCashLbp;

  /// No description provided for @posCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get posCard;

  /// No description provided for @posWallet.
  ///
  /// In en, this message translates to:
  /// **'YouDrop wallet'**
  String get posWallet;

  /// No description provided for @posWalletComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get posWalletComingSoon;

  /// No description provided for @posAmountTendered.
  ///
  /// In en, this message translates to:
  /// **'Amount given'**
  String get posAmountTendered;

  /// No description provided for @posCardReference.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get posCardReference;

  /// No description provided for @posChangeIn.
  ///
  /// In en, this message translates to:
  /// **'Change in'**
  String get posChangeIn;

  /// No description provided for @posChangeDue.
  ///
  /// In en, this message translates to:
  /// **'Change due'**
  String get posChangeDue;

  /// No description provided for @posChangePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview — the till confirms the final figure.'**
  String get posChangePreview;

  /// No description provided for @posRoundingLbp.
  ///
  /// In en, this message translates to:
  /// **'Rounded to the nearest note'**
  String get posRoundingLbp;

  /// No description provided for @posSplitPayment.
  ///
  /// In en, this message translates to:
  /// **'Split payment'**
  String get posSplitPayment;

  /// No description provided for @posAddTender.
  ///
  /// In en, this message translates to:
  /// **'Add another payment'**
  String get posAddTender;

  /// No description provided for @posRemainingAmount.
  ///
  /// In en, this message translates to:
  /// **'Remaining {amount}'**
  String posRemainingAmount(String amount);

  /// No description provided for @posCompleteSale.
  ///
  /// In en, this message translates to:
  /// **'Complete sale'**
  String get posCompleteSale;

  /// No description provided for @posSaleCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sale completed'**
  String get posSaleCompleted;

  /// No description provided for @posTendersShort.
  ///
  /// In en, this message translates to:
  /// **'The payments do not cover the total yet.'**
  String get posTendersShort;

  /// No description provided for @posReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get posReceipt;

  /// No description provided for @posReceiptChannel.
  ///
  /// In en, this message translates to:
  /// **'Send the receipt'**
  String get posReceiptChannel;

  /// No description provided for @posReceiptPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get posReceiptPrint;

  /// No description provided for @posReceiptSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get posReceiptSms;

  /// No description provided for @posReceiptWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get posReceiptWhatsapp;

  /// No description provided for @posReceiptEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get posReceiptEmail;

  /// No description provided for @posReceiptNone.
  ///
  /// In en, this message translates to:
  /// **'No receipt'**
  String get posReceiptNone;

  /// No description provided for @posReceiptContact.
  ///
  /// In en, this message translates to:
  /// **'Where to send it'**
  String get posReceiptContact;

  /// No description provided for @posReceiptSent.
  ///
  /// In en, this message translates to:
  /// **'Receipt sent'**
  String get posReceiptSent;

  /// No description provided for @posReceiptNo.
  ///
  /// In en, this message translates to:
  /// **'Receipt {label}'**
  String posReceiptNo(String label);

  /// No description provided for @posPrintReceipt.
  ///
  /// In en, this message translates to:
  /// **'Print receipt'**
  String get posPrintReceipt;

  /// No description provided for @posShareReceipt.
  ///
  /// In en, this message translates to:
  /// **'Share receipt'**
  String get posShareReceipt;

  /// No description provided for @posNewSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get posNewSale;

  /// No description provided for @posCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get posCashier;

  /// No description provided for @posThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you'**
  String get posThankYou;

  /// No description provided for @posShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get posShift;

  /// No description provided for @posShiftActive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Shift open} =1{Shift open · 1 sale} other{Shift open · {count} sales}}'**
  String posShiftActive(int count);

  /// No description provided for @posOpenShift.
  ///
  /// In en, this message translates to:
  /// **'Open shift'**
  String get posOpenShift;

  /// No description provided for @posCloseShift.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get posCloseShift;

  /// No description provided for @posOpeningFloat.
  ///
  /// In en, this message translates to:
  /// **'Cash in the drawer (USD)'**
  String get posOpeningFloat;

  /// No description provided for @posOpeningFloatLbp.
  ///
  /// In en, this message translates to:
  /// **'Cash in the drawer (LBP)'**
  String get posOpeningFloatLbp;

  /// No description provided for @posCountedCash.
  ///
  /// In en, this message translates to:
  /// **'Counted (USD)'**
  String get posCountedCash;

  /// No description provided for @posCountedCashLbp.
  ///
  /// In en, this message translates to:
  /// **'Counted (LBP)'**
  String get posCountedCashLbp;

  /// No description provided for @posExpected.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get posExpected;

  /// No description provided for @posCounted.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get posCounted;

  /// No description provided for @posVariance.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get posVariance;

  /// No description provided for @posShiftClosed.
  ///
  /// In en, this message translates to:
  /// **'Shift closed'**
  String get posShiftClosed;

  /// No description provided for @posShiftSummary.
  ///
  /// In en, this message translates to:
  /// **'Shift summary'**
  String get posShiftSummary;

  /// No description provided for @posNoShift.
  ///
  /// In en, this message translates to:
  /// **'No shift open'**
  String get posNoShift;

  /// No description provided for @posNoShiftHint.
  ///
  /// In en, this message translates to:
  /// **'Open a shift before ringing up sales.'**
  String get posNoShiftHint;

  /// No description provided for @posRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get posRegister;

  /// No description provided for @posRegisters.
  ///
  /// In en, this message translates to:
  /// **'Registers'**
  String get posRegisters;

  /// No description provided for @posAddRegister.
  ///
  /// In en, this message translates to:
  /// **'Add register'**
  String get posAddRegister;

  /// No description provided for @posRegisterName.
  ///
  /// In en, this message translates to:
  /// **'Register name'**
  String get posRegisterName;

  /// No description provided for @posSelectRegister.
  ///
  /// In en, this message translates to:
  /// **'Choose a register'**
  String get posSelectRegister;

  /// No description provided for @posSalesCount.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get posSalesCount;

  /// No description provided for @posByMethod.
  ///
  /// In en, this message translates to:
  /// **'By payment method'**
  String get posByMethod;

  /// No description provided for @posStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get posStatusOpen;

  /// No description provided for @posStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get posStatusCompleted;

  /// No description provided for @posStatusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get posStatusVoided;

  /// No description provided for @posStatusPartiallyRefunded.
  ///
  /// In en, this message translates to:
  /// **'Partly refunded'**
  String get posStatusPartiallyRefunded;

  /// No description provided for @posStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get posStatusRefunded;

  /// No description provided for @posActionComplete.
  ///
  /// In en, this message translates to:
  /// **'Charge'**
  String get posActionComplete;

  /// No description provided for @posActionVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get posActionVoid;

  /// No description provided for @posActionRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get posActionRefund;

  /// No description provided for @posActionReprint.
  ///
  /// In en, this message translates to:
  /// **'Reprint receipt'**
  String get posActionReprint;

  /// No description provided for @posVoidSale.
  ///
  /// In en, this message translates to:
  /// **'Void this sale'**
  String get posVoidSale;

  /// No description provided for @posVoidReason.
  ///
  /// In en, this message translates to:
  /// **'Why is it being voided?'**
  String get posVoidReason;

  /// No description provided for @posVoidConfirm.
  ///
  /// In en, this message translates to:
  /// **'Void sale'**
  String get posVoidConfirm;

  /// No description provided for @posVoided.
  ///
  /// In en, this message translates to:
  /// **'Sale voided'**
  String get posVoided;

  /// No description provided for @posRefundTitle.
  ///
  /// In en, this message translates to:
  /// **'Refund items'**
  String get posRefundTitle;

  /// No description provided for @posRefundQty.
  ///
  /// In en, this message translates to:
  /// **'How many back?'**
  String get posRefundQty;

  /// No description provided for @posRefundMethod.
  ///
  /// In en, this message translates to:
  /// **'Refund as'**
  String get posRefundMethod;

  /// No description provided for @posRefundRestock.
  ///
  /// In en, this message translates to:
  /// **'Put the items back on the shelf'**
  String get posRefundRestock;

  /// No description provided for @posRefundReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get posRefundReason;

  /// No description provided for @posRefundConfirm.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get posRefundConfirm;

  /// No description provided for @posRefundDone.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get posRefundDone;

  /// No description provided for @invTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get invTitle;

  /// No description provided for @invSearch.
  ///
  /// In en, this message translates to:
  /// **'Search by name, SKU or barcode'**
  String get invSearch;

  /// No description provided for @invFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get invFilterAll;

  /// No description provided for @invFilterLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get invFilterLowStock;

  /// No description provided for @invFilterOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get invFilterOutOfStock;

  /// No description provided for @invFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get invFilterActive;

  /// No description provided for @invFilterHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get invFilterHidden;

  /// No description provided for @invOnHand.
  ///
  /// In en, this message translates to:
  /// **'On hand'**
  String get invOnHand;

  /// No description provided for @invReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get invReserved;

  /// No description provided for @invAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get invAvailable;

  /// No description provided for @invThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low-stock level'**
  String get invThreshold;

  /// No description provided for @invSku.
  ///
  /// In en, this message translates to:
  /// **'SKU {sku}'**
  String invSku(String sku);

  /// No description provided for @invBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get invBarcode;

  /// No description provided for @invNotTracked.
  ///
  /// In en, this message translates to:
  /// **'Not tracked'**
  String get invNotTracked;

  /// No description provided for @invTrackStock.
  ///
  /// In en, this message translates to:
  /// **'Track stock'**
  String get invTrackStock;

  /// No description provided for @invTrackStockHint.
  ///
  /// In en, this message translates to:
  /// **'YouDrop hides the item when it runs out.'**
  String get invTrackStockHint;

  /// No description provided for @invInitialStock.
  ///
  /// In en, this message translates to:
  /// **'Stock on hand now'**
  String get invInitialStock;

  /// No description provided for @invStatusOk.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get invStatusOk;

  /// No description provided for @invStatusWarning.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get invStatusWarning;

  /// No description provided for @invStatusCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get invStatusCritical;

  /// No description provided for @invStatusOut.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get invStatusOut;

  /// No description provided for @invEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in inventory yet'**
  String get invEmpty;

  /// No description provided for @invEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add products to your catalogue and they appear here.'**
  String get invEmptyHint;

  /// No description provided for @invCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load inventory'**
  String get invCouldNotLoad;

  /// No description provided for @invSyncing.
  ///
  /// In en, this message translates to:
  /// **'Bringing your catalogue in…'**
  String get invSyncing;

  /// No description provided for @invSynced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing to bring in} =1{1 product added} other{{count} products added}}'**
  String invSynced(int count);

  /// No description provided for @invProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get invProducts;

  /// No description provided for @invCategories.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get invCategories;

  /// No description provided for @invAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get invAlerts;

  /// No description provided for @invAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get invAdjust;

  /// No description provided for @invAdjustAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get invAdjustAdd;

  /// No description provided for @invAdjustRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get invAdjustRemove;

  /// No description provided for @invAdjustSetTo.
  ///
  /// In en, this message translates to:
  /// **'Set to'**
  String get invAdjustSetTo;

  /// No description provided for @invAdjustQuantity.
  ///
  /// In en, this message translates to:
  /// **'How many?'**
  String get invAdjustQuantity;

  /// No description provided for @invAdjustReason.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get invAdjustReason;

  /// No description provided for @invAdjustNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get invAdjustNote;

  /// No description provided for @invAdjustSave.
  ///
  /// In en, this message translates to:
  /// **'Save adjustment'**
  String get invAdjustSave;

  /// No description provided for @invAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Stock updated'**
  String get invAdjusted;

  /// No description provided for @invReasonReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get invReasonReceived;

  /// No description provided for @invReasonDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get invReasonDamaged;

  /// No description provided for @invReasonExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get invReasonExpired;

  /// No description provided for @invReasonTheft.
  ///
  /// In en, this message translates to:
  /// **'Theft or loss'**
  String get invReasonTheft;

  /// No description provided for @invReasonCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get invReasonCorrection;

  /// No description provided for @invReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get invReasonOther;

  /// No description provided for @invMovements.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get invMovements;

  /// No description provided for @invNoMovements.
  ///
  /// In en, this message translates to:
  /// **'Nothing has moved yet'**
  String get invNoMovements;

  /// No description provided for @invKindReceipt.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get invKindReceipt;

  /// No description provided for @invKindAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjusted'**
  String get invKindAdjustment;

  /// No description provided for @invKindCount.
  ///
  /// In en, this message translates to:
  /// **'Stock count'**
  String get invKindCount;

  /// No description provided for @invKindSale.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get invKindSale;

  /// No description provided for @invKindReturn.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get invKindReturn;

  /// No description provided for @invKindOrderReserve.
  ///
  /// In en, this message translates to:
  /// **'Held for an order'**
  String get invKindOrderReserve;

  /// No description provided for @invKindOrderRelease.
  ///
  /// In en, this message translates to:
  /// **'Released'**
  String get invKindOrderRelease;

  /// No description provided for @invKindOrderFulfil.
  ///
  /// In en, this message translates to:
  /// **'Order handed over'**
  String get invKindOrderFulfil;

  /// No description provided for @invSettings.
  ///
  /// In en, this message translates to:
  /// **'Stock settings'**
  String get invSettings;

  /// No description provided for @invAlertsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alerts'**
  String get invAlertsEnabled;

  /// No description provided for @invWhatsappAlerts.
  ///
  /// In en, this message translates to:
  /// **'Send alerts on WhatsApp'**
  String get invWhatsappAlerts;

  /// No description provided for @invAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock alerts'**
  String get invAlertsTitle;

  /// No description provided for @invAlertsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing needs restocking} =1{1 item needs restocking} other{{count} items need restocking}}'**
  String invAlertsCount(int count);

  /// No description provided for @invAlertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Every shelf is stocked'**
  String get invAlertsEmpty;

  /// No description provided for @invAlertsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'We will tell you here when something runs low.'**
  String get invAlertsEmptyHint;

  /// No description provided for @invAlertsCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load stock alerts'**
  String get invAlertsCouldNotLoad;

  /// No description provided for @invVelocity.
  ///
  /// In en, this message translates to:
  /// **'Sells about {perDay} a day'**
  String invVelocity(String perDay);

  /// No description provided for @invHoursOfCover.
  ///
  /// In en, this message translates to:
  /// **'About {hours} hours left'**
  String invHoursOfCover(String hours);

  /// No description provided for @invLastSold.
  ///
  /// In en, this message translates to:
  /// **'Last sold {when}'**
  String invLastSold(Object when);

  /// No description provided for @invNoVelocityYet.
  ///
  /// In en, this message translates to:
  /// **'Not enough sales yet to say'**
  String get invNoVelocityYet;

  /// No description provided for @invRestock.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get invRestock;

  /// No description provided for @invCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock count'**
  String get invCountTitle;

  /// No description provided for @invCountNew.
  ///
  /// In en, this message translates to:
  /// **'Start a count'**
  String get invCountNew;

  /// No description provided for @invCountName.
  ///
  /// In en, this message translates to:
  /// **'Name this count'**
  String get invCountName;

  /// No description provided for @invCountNameHint.
  ///
  /// In en, this message translates to:
  /// **'Friday shelf check'**
  String get invCountNameHint;

  /// No description provided for @invCountScope.
  ///
  /// In en, this message translates to:
  /// **'What are you counting?'**
  String get invCountScope;

  /// No description provided for @invCountAllProducts.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get invCountAllProducts;

  /// No description provided for @invCountByCategory.
  ///
  /// In en, this message translates to:
  /// **'One section'**
  String get invCountByCategory;

  /// No description provided for @invCountStart.
  ///
  /// In en, this message translates to:
  /// **'Start counting'**
  String get invCountStart;

  /// No description provided for @invCountProgress.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing counted of {total}} =1{1 of {total} counted} other{{count} of {total} counted}}'**
  String invCountProgress(int count, int total);

  /// No description provided for @invCountSystem.
  ///
  /// In en, this message translates to:
  /// **'System says'**
  String get invCountSystem;

  /// No description provided for @invCountCounted.
  ///
  /// In en, this message translates to:
  /// **'You counted'**
  String get invCountCounted;

  /// No description provided for @invCountVariance.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get invCountVariance;

  /// No description provided for @invCountSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit count'**
  String get invCountSubmit;

  /// No description provided for @invCountCancelCount.
  ///
  /// In en, this message translates to:
  /// **'Cancel count'**
  String get invCountCancelCount;

  /// No description provided for @invCountSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Count applied to stock'**
  String get invCountSubmitted;

  /// No description provided for @invCountCancelled.
  ///
  /// In en, this message translates to:
  /// **'Count cancelled'**
  String get invCountCancelled;

  /// No description provided for @invCountDiscrepancies.
  ///
  /// In en, this message translates to:
  /// **'Differences found'**
  String get invCountDiscrepancies;

  /// No description provided for @invCountNoDiscrepancies.
  ///
  /// In en, this message translates to:
  /// **'Everything matches'**
  String get invCountNoDiscrepancies;

  /// No description provided for @invCountLeaveWarning.
  ///
  /// In en, this message translates to:
  /// **'Leave this count?'**
  String get invCountLeaveWarning;

  /// No description provided for @invCountLeaveWarningBody.
  ///
  /// In en, this message translates to:
  /// **'What you have counted is saved, and the count stays open.'**
  String get invCountLeaveWarningBody;

  /// No description provided for @invCountKeepCounting.
  ///
  /// In en, this message translates to:
  /// **'Keep counting'**
  String get invCountKeepCounting;

  /// No description provided for @invCountDiscard.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get invCountDiscard;

  /// No description provided for @invCountEmpty.
  ///
  /// In en, this message translates to:
  /// **'No counts yet'**
  String get invCountEmpty;

  /// No description provided for @invCountOpenExists.
  ///
  /// In en, this message translates to:
  /// **'A count is already open. Finish it first.'**
  String get invCountOpenExists;

  /// No description provided for @invCountStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get invCountStatusOpen;

  /// No description provided for @invCountStatusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get invCountStatusSubmitted;

  /// No description provided for @invCountStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get invCountStatusCancelled;

  /// No description provided for @catTitle.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get catTitle;

  /// No description provided for @catSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How your shop is arranged for customers'**
  String get catSubtitle;

  /// No description provided for @catAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a section'**
  String get catAdd;

  /// No description provided for @catName.
  ///
  /// In en, this message translates to:
  /// **'Section name'**
  String get catName;

  /// No description provided for @catNameHint.
  ///
  /// In en, this message translates to:
  /// **'Drinks'**
  String get catNameHint;

  /// No description provided for @catParent.
  ///
  /// In en, this message translates to:
  /// **'Sits under'**
  String get catParent;

  /// No description provided for @catNoParent.
  ///
  /// In en, this message translates to:
  /// **'Top level'**
  String get catNoParent;

  /// No description provided for @catDragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag rows to change display order on the YouDrop app.'**
  String get catDragToReorder;

  /// No description provided for @catProductsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No products} =1{1 product} other{{count} products}}'**
  String catProductsCount(int count);

  /// No description provided for @catRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get catRename;

  /// No description provided for @catDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete section'**
  String get catDelete;

  /// No description provided for @catDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this section? Its products stay in your catalogue.'**
  String get catDeleteConfirm;

  /// No description provided for @catCannotDeleteNonEmpty.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This section still holds 1 product} other{This section still holds {count} products}}'**
  String catCannotDeleteNonEmpty(int count);

  /// No description provided for @catEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sections yet'**
  String get catEmpty;

  /// No description provided for @catEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Sections group your products on the shop page.'**
  String get catEmptyHint;

  /// No description provided for @catCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load sections'**
  String get catCouldNotLoad;

  /// No description provided for @catOrderSaved.
  ///
  /// In en, this message translates to:
  /// **'Order saved'**
  String get catOrderSaved;

  /// No description provided for @catOrderFailed.
  ///
  /// In en, this message translates to:
  /// **'The order could not be saved'**
  String get catOrderFailed;

  /// No description provided for @catImage.
  ///
  /// In en, this message translates to:
  /// **'Section picture'**
  String get catImage;

  /// No description provided for @catChangeImage.
  ///
  /// In en, this message translates to:
  /// **'Change picture'**
  String get catChangeImage;

  /// No description provided for @catYourSections.
  ///
  /// In en, this message translates to:
  /// **'Your sections'**
  String get catYourSections;

  /// No description provided for @catPlatformCategories.
  ///
  /// In en, this message translates to:
  /// **'YouDrop categories'**
  String get catPlatformCategories;

  /// No description provided for @staffTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffTitle;

  /// No description provided for @staffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who works here and what they can do'**
  String get staffSubtitle;

  /// No description provided for @staffRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get staffRoleOwner;

  /// No description provided for @staffRoleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get staffRoleManager;

  /// No description provided for @staffRoleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get staffRoleCashier;

  /// No description provided for @staffRoleStockkeeper.
  ///
  /// In en, this message translates to:
  /// **'Stockkeeper'**
  String get staffRoleStockkeeper;

  /// No description provided for @staffPermPosSales.
  ///
  /// In en, this message translates to:
  /// **'Sell at the register'**
  String get staffPermPosSales;

  /// No description provided for @staffPermPosSalesDesc.
  ///
  /// In en, this message translates to:
  /// **'Ring up walk-in sales and take payment.'**
  String get staffPermPosSalesDesc;

  /// No description provided for @staffPermPosRefundsVoids.
  ///
  /// In en, this message translates to:
  /// **'Refunds and voids'**
  String get staffPermPosRefundsVoids;

  /// No description provided for @staffPermPosRefundsVoidsDesc.
  ///
  /// In en, this message translates to:
  /// **'Give money back, cancel a sale, discount past the limit.'**
  String get staffPermPosRefundsVoidsDesc;

  /// No description provided for @staffPermModifyInventoryPricing.
  ///
  /// In en, this message translates to:
  /// **'Products and stock'**
  String get staffPermModifyInventoryPricing;

  /// No description provided for @staffPermModifyInventoryPricingDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit products, prices and stock levels.'**
  String get staffPermModifyInventoryPricingDesc;

  /// No description provided for @staffPermManageOrders.
  ///
  /// In en, this message translates to:
  /// **'Delivery orders'**
  String get staffPermManageOrders;

  /// No description provided for @staffPermManageOrdersDesc.
  ///
  /// In en, this message translates to:
  /// **'Accept, reject and move YouDrop orders along.'**
  String get staffPermManageOrdersDesc;

  /// No description provided for @staffPermViewReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get staffPermViewReports;

  /// No description provided for @staffPermViewReportsDesc.
  ///
  /// In en, this message translates to:
  /// **'See sales figures and the dashboard money.'**
  String get staffPermViewReportsDesc;

  /// No description provided for @staffPermAccessSettings.
  ///
  /// In en, this message translates to:
  /// **'Store settings'**
  String get staffPermAccessSettings;

  /// No description provided for @staffPermAccessSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Change hours, delivery areas and the shop profile.'**
  String get staffPermAccessSettingsDesc;

  /// No description provided for @staffPermManageStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffPermManageStaff;

  /// No description provided for @staffPermManageStaffDesc.
  ///
  /// In en, this message translates to:
  /// **'Add and remove members, and set what each may do.'**
  String get staffPermManageStaffDesc;

  /// No description provided for @staffStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get staffStatusActive;

  /// No description provided for @staffStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get staffStatusInactive;

  /// No description provided for @staffOnShift.
  ///
  /// In en, this message translates to:
  /// **'On shift'**
  String get staffOnShift;

  /// No description provided for @staffOffShift.
  ///
  /// In en, this message translates to:
  /// **'Off shift'**
  String get staffOffShift;

  /// No description provided for @staffLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {when}'**
  String staffLastSeen(Object when);

  /// No description provided for @staffShiftMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Just clocked in} =1{On shift 1 minute} other{On shift {count} minutes}}'**
  String staffShiftMinutes(int count);

  /// No description provided for @staffInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite someone'**
  String get staffInvite;

  /// No description provided for @staffInviteRole.
  ///
  /// In en, this message translates to:
  /// **'Their role'**
  String get staffInviteRole;

  /// No description provided for @staffInviteName.
  ///
  /// In en, this message translates to:
  /// **'Their name'**
  String get staffInviteName;

  /// No description provided for @staffInviteEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get staffInviteEmail;

  /// No description provided for @staffInvitePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get staffInvitePhone;

  /// No description provided for @staffInviteCreate.
  ///
  /// In en, this message translates to:
  /// **'Create invite code'**
  String get staffInviteCreate;

  /// No description provided for @staffInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get staffInviteCode;

  /// No description provided for @staffInviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'They sign in to YouDrop and enter this code. You never set their password.'**
  String get staffInviteCodeHint;

  /// No description provided for @staffInviteShare.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get staffInviteShare;

  /// No description provided for @staffInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get staffInviteCopied;

  /// No description provided for @staffInviteExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {when}'**
  String staffInviteExpires(Object when);

  /// No description provided for @staffPendingInvites.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be redeemed'**
  String get staffPendingInvites;

  /// No description provided for @staffNoPendingInvites.
  ///
  /// In en, this message translates to:
  /// **'No codes outstanding'**
  String get staffNoPendingInvites;

  /// No description provided for @staffAcceptTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a shop'**
  String get staffAcceptTitle;

  /// No description provided for @staffAcceptCode.
  ///
  /// In en, this message translates to:
  /// **'Enter your invite code'**
  String get staffAcceptCode;

  /// No description provided for @staffAcceptJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get staffAcceptJoin;

  /// No description provided for @staffAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'That code did not work'**
  String get staffAcceptFailed;

  /// No description provided for @staffJoined.
  ///
  /// In en, this message translates to:
  /// **'You now work at {store}'**
  String staffJoined(String store);

  /// No description provided for @staffEditPermissions.
  ///
  /// In en, this message translates to:
  /// **'What they can do'**
  String get staffEditPermissions;

  /// No description provided for @staffRoleDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults for this role'**
  String get staffRoleDefaults;

  /// No description provided for @staffCustomised.
  ///
  /// In en, this message translates to:
  /// **'Changed for this person'**
  String get staffCustomised;

  /// No description provided for @staffResetToRole.
  ///
  /// In en, this message translates to:
  /// **'Back to the role default'**
  String get staffResetToRole;

  /// No description provided for @staffChangeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get staffChangeRole;

  /// No description provided for @staffDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get staffDeactivate;

  /// No description provided for @staffActivate.
  ///
  /// In en, this message translates to:
  /// **'Reinstate'**
  String get staffActivate;

  /// No description provided for @staffRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from shop'**
  String get staffRemove;

  /// No description provided for @staffRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this person? Their past shifts and sales stay on the record.'**
  String get staffRemoveConfirm;

  /// No description provided for @staffRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get staffRemoved;

  /// No description provided for @staffClockIn.
  ///
  /// In en, this message translates to:
  /// **'Clock in'**
  String get staffClockIn;

  /// No description provided for @staffClockOut.
  ///
  /// In en, this message translates to:
  /// **'Clock out'**
  String get staffClockOut;

  /// No description provided for @staffClockedIn.
  ///
  /// In en, this message translates to:
  /// **'You are on shift'**
  String get staffClockedIn;

  /// No description provided for @staffClockedOut.
  ///
  /// In en, this message translates to:
  /// **'Shift ended'**
  String get staffClockedOut;

  /// No description provided for @staffSalesToday.
  ///
  /// In en, this message translates to:
  /// **'Sales today'**
  String get staffSalesToday;

  /// No description provided for @staffNoPosSalesYet.
  ///
  /// In en, this message translates to:
  /// **'Sales appear here once the register is live.'**
  String get staffNoPosSalesYet;

  /// No description provided for @staffEmpty.
  ///
  /// In en, this message translates to:
  /// **'You work alone so far'**
  String get staffEmpty;

  /// No description provided for @staffEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Invite a manager or a cashier and they show up here.'**
  String get staffEmptyHint;

  /// No description provided for @staffCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load the team'**
  String get staffCouldNotLoad;

  /// No description provided for @staffNoShopYet.
  ///
  /// In en, this message translates to:
  /// **'You are not on a shop\'s team yet'**
  String get staffNoShopYet;

  /// No description provided for @staffYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get staffYou;

  /// No description provided for @staffOwnerBadge.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get staffOwnerBadge;

  /// No description provided for @staffCannotEditOwner.
  ///
  /// In en, this message translates to:
  /// **'The owner always has every permission.'**
  String get staffCannotEditOwner;

  /// No description provided for @staffNoPermission.
  ///
  /// In en, this message translates to:
  /// **'You cannot change this'**
  String get staffNoPermission;

  /// No description provided for @repTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales reports'**
  String get repTitle;

  /// No description provided for @repRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get repRangeToday;

  /// No description provided for @repRangeWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get repRangeWeek;

  /// No description provided for @repRangeMonth.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get repRangeMonth;

  /// No description provided for @repRangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Pick dates'**
  String get repRangeCustom;

  /// No description provided for @repCompareToPrevious.
  ///
  /// In en, this message translates to:
  /// **'Compare with the period before'**
  String get repCompareToPrevious;

  /// No description provided for @repRangeTooLong.
  ///
  /// In en, this message translates to:
  /// **'Reports cover at most {days} days at a time'**
  String repRangeTooLong(int days);

  /// No description provided for @repRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get repRevenue;

  /// No description provided for @repNetRevenue.
  ///
  /// In en, this message translates to:
  /// **'Net revenue'**
  String get repNetRevenue;

  /// No description provided for @repGrossValue.
  ///
  /// In en, this message translates to:
  /// **'Gross sales'**
  String get repGrossValue;

  /// No description provided for @repRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get repRefunded;

  /// No description provided for @repOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get repOrders;

  /// No description provided for @repItemsSold.
  ///
  /// In en, this message translates to:
  /// **'Items sold'**
  String get repItemsSold;

  /// No description provided for @repAverageOrder.
  ///
  /// In en, this message translates to:
  /// **'Average sale'**
  String get repAverageOrder;

  /// No description provided for @repDailyRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue by day'**
  String get repDailyRevenue;

  /// No description provided for @repByCategory.
  ///
  /// In en, this message translates to:
  /// **'Sales by section'**
  String get repByCategory;

  /// No description provided for @repTopProducts.
  ///
  /// In en, this message translates to:
  /// **'Best sellers'**
  String get repTopProducts;

  /// No description provided for @repUncategorised.
  ///
  /// In en, this message translates to:
  /// **'No section'**
  String get repUncategorised;

  /// No description provided for @repBySource.
  ///
  /// In en, this message translates to:
  /// **'Where the sales came from'**
  String get repBySource;

  /// No description provided for @repByPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'How customers paid'**
  String get repByPaymentMethod;

  /// No description provided for @repSourceDelivery.
  ///
  /// In en, this message translates to:
  /// **'YouDrop'**
  String get repSourceDelivery;

  /// No description provided for @repSourceWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get repSourceWalkIn;

  /// No description provided for @repSoldCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None sold} =1{1 sold} other{{count} sold}}'**
  String repSoldCount(int count);

  /// No description provided for @repOrdersTotal.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sales} =1{1 sale} other{{count} sales}}'**
  String repOrdersTotal(int count);

  /// No description provided for @repEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing sold in this period'**
  String get repEmpty;

  /// No description provided for @repEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a wider range, or bring in the history from before reports existed.'**
  String get repEmptyHint;

  /// No description provided for @repSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'Bring in past sales'**
  String get repSyncHistory;

  /// No description provided for @repSyncStarted.
  ///
  /// In en, this message translates to:
  /// **'Working through your history…'**
  String get repSyncStarted;

  /// No description provided for @repCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load the report'**
  String get repCouldNotLoad;

  /// No description provided for @repExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get repExportCsv;

  /// No description provided for @repExported.
  ///
  /// In en, this message translates to:
  /// **'Report exported'**
  String get repExported;

  /// No description provided for @repGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Worked out {when}'**
  String repGeneratedAt(Object when);

  /// No description provided for @repNoChange.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get repNoChange;

  /// No description provided for @repHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales history'**
  String get repHistoryTitle;

  /// No description provided for @repHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage sales receipts'**
  String get repHistorySubtitle;

  /// No description provided for @repHistorySearch.
  ///
  /// In en, this message translates to:
  /// **'Search by receipt number or item'**
  String get repHistorySearch;

  /// No description provided for @repHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No receipts in this period'**
  String get repHistoryEmpty;

  /// No description provided for @repHistoryCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load sales history'**
  String get repHistoryCouldNotLoad;

  /// No description provided for @repStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get repStatusCompleted;

  /// No description provided for @repStatusPartiallyRefunded.
  ///
  /// In en, this message translates to:
  /// **'Partly refunded'**
  String get repStatusPartiallyRefunded;

  /// No description provided for @repStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get repStatusRefunded;

  /// No description provided for @repStatusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get repStatusVoided;

  /// No description provided for @repViewReceipt.
  ///
  /// In en, this message translates to:
  /// **'View receipt'**
  String get repViewReceipt;

  /// No description provided for @repFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get repFilterAll;

  /// What the signed-in person is, on the portal sidebar's footer card. Their access, not their job title.
  ///
  /// In en, this message translates to:
  /// **'Merchant partner'**
  String get merchantPartner;

  /// No description provided for @carrierPartner.
  ///
  /// In en, this message translates to:
  /// **'Carrier partner'**
  String get carrierPartner;

  /// No description provided for @backofficeOperator.
  ///
  /// In en, this message translates to:
  /// **'Backoffice operator'**
  String get backofficeOperator;

  /// Shown in place of a product photo whose link has expired or whose file has gone.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get imageUnavailable;

  /// No description provided for @openFullSizePhoto.
  ///
  /// In en, this message translates to:
  /// **'Open full-size photo'**
  String get openFullSizePhoto;

  /// Which photo of a product's set is showing in the full-size preview.
  ///
  /// In en, this message translates to:
  /// **'{index} of {count}'**
  String photoPosition(int index, int count);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @accountIntentSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'How will you use YouDrop?'**
  String get accountIntentSheetTitle;

  /// No description provided for @accountIntentSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick one, then continue with Google. Riding and selling are reviewed before you start, and an account can apply for only one of them.'**
  String get accountIntentSheetSubtitle;

  /// No description provided for @accountIntentCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get accountIntentCustomer;

  /// No description provided for @accountIntentCustomerBlurb.
  ///
  /// In en, this message translates to:
  /// **'I want to order'**
  String get accountIntentCustomerBlurb;

  /// No description provided for @accountIntentRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get accountIntentRider;

  /// No description provided for @accountIntentRiderBlurb.
  ///
  /// In en, this message translates to:
  /// **'I want to deliver'**
  String get accountIntentRiderBlurb;

  /// No description provided for @accountIntentSeller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get accountIntentSeller;

  /// No description provided for @accountIntentSellerBlurb.
  ///
  /// In en, this message translates to:
  /// **'I want to sell'**
  String get accountIntentSellerBlurb;

  /// No description provided for @googleSignInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in was cancelled. Nothing was changed.'**
  String get googleSignInCancelled;

  /// No description provided for @googleSignInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in isn\'t available yet. Please use your email or phone for now.'**
  String get googleSignInUnavailable;

  /// No description provided for @googleRoleNotAdded.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in, but we couldn\'t finish setting up your account. Please choose again.'**
  String get googleRoleNotAdded;

  /// No description provided for @googleExistingApplication.
  ///
  /// In en, this message translates to:
  /// **'This account already has an application, so we\'ve opened that instead of starting another.'**
  String get googleExistingApplication;

  /// No description provided for @accountSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'One more step'**
  String get accountSetupTitle;

  /// No description provided for @accountSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us how you\'ll use YouDrop to finish setting up your account.'**
  String get accountSetupSubtitle;

  /// No description provided for @wizAccountEmailNote.
  ///
  /// In en, this message translates to:
  /// **'We\'ll use the email on the account you signed in with.'**
  String get wizAccountEmailNote;

  /// No description provided for @wizAccountRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Your application is in, but we couldn\'t refresh your sign-in. Try again.'**
  String get wizAccountRefreshFailed;

  /// No description provided for @accountApplicationClosed.
  ///
  /// In en, this message translates to:
  /// **'The partner application on this account has already been decided, so it can\'t be reopened here. Please contact support.'**
  String get accountApplicationClosed;

  /// No description provided for @accountAlreadyPartner.
  ///
  /// In en, this message translates to:
  /// **'This account is already a YouDrop partner, and an account can hold only one partner role.'**
  String get accountAlreadyPartner;

  /// No description provided for @accountOtherApplication.
  ///
  /// In en, this message translates to:
  /// **'This account already has an application for another role, and an account can apply for only one.'**
  String get accountOtherApplication;

  /// No description provided for @accountEmailUnverified.
  ///
  /// In en, this message translates to:
  /// **'Your account\'s email address hasn\'t been verified, so we can\'t take an application on it yet.'**
  String get accountEmailUnverified;

  /// No description provided for @wizAccountRolesRetry.
  ///
  /// In en, this message translates to:
  /// **'Your application is in, but we couldn\'t finish setting up your account. Please try again.'**
  String get wizAccountRolesRetry;

  /// No description provided for @offlinePill.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get offlinePill;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Orders you queue will be sent when you\'re back online.'**
  String get offlineBanner;

  /// No description provided for @offlineBackOnline.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get offlineBackOnline;

  /// No description provided for @offlineSavedItems.
  ///
  /// In en, this message translates to:
  /// **'Saved items'**
  String get offlineSavedItems;

  /// No description provided for @offlineModeBadge.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode'**
  String get offlineModeBadge;

  /// No description provided for @offlineCachedCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Cached Catalog'**
  String get offlineCachedCatalogTitle;

  /// No description provided for @offlineLastPurchases.
  ///
  /// In en, this message translates to:
  /// **'Your Last Cached Purchases'**
  String get offlineLastPurchases;

  /// No description provided for @offlinePricesAsOf.
  ///
  /// In en, this message translates to:
  /// **'Prices as of {when}. They may have changed since.'**
  String offlinePricesAsOf(String when);

  /// No description provided for @offlineQuickAdd.
  ///
  /// In en, this message translates to:
  /// **'Quick Add'**
  String get offlineQuickAdd;

  /// No description provided for @offlineNeedsOptions.
  ///
  /// In en, this message translates to:
  /// **'Choose options when you\'re online'**
  String get offlineNeedsOptions;

  /// No description provided for @offlineNothingSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved for offline yet'**
  String get offlineNothingSaved;

  /// No description provided for @offlineNothingSavedHint.
  ///
  /// In en, this message translates to:
  /// **'What you order while online is saved here, so you can order it again when the connection drops.'**
  String get offlineNothingSavedHint;

  /// No description provided for @offlineOutboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get offlineOutboxTitle;

  /// No description provided for @offlineQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'{store} — Queued'**
  String offlineQueuedTitle(String store);

  /// No description provided for @offlineWillSend.
  ///
  /// In en, this message translates to:
  /// **'Will send as soon as you\'re back online'**
  String get offlineWillSend;

  /// No description provided for @offlineSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get offlineSending;

  /// No description provided for @offlinePriceChanged.
  ///
  /// In en, this message translates to:
  /// **'The total is now {total}. Confirm to send it at this price.'**
  String offlinePriceChanged(String total);

  /// No description provided for @offlineSendAt.
  ///
  /// In en, this message translates to:
  /// **'Send at {total}'**
  String offlineSendAt(String total);

  /// No description provided for @offlineStale.
  ///
  /// In en, this message translates to:
  /// **'This has been waiting a while. Do you still want it?'**
  String get offlineStale;

  /// No description provided for @offlineSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get offlineSendNow;

  /// No description provided for @offlineFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t place this order: {reason}'**
  String offlineFailed(String reason);

  /// No description provided for @offlineDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get offlineDiscard;

  /// No description provided for @offlineDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this order?'**
  String get offlineDiscardTitle;

  /// No description provided for @offlineDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'It hasn\'t been placed, and it won\'t be sent.'**
  String get offlineDiscardBody;

  /// No description provided for @offlineQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach YouDrop'**
  String get offlineQueueTitle;

  /// No description provided for @offlineQueueBody.
  ///
  /// In en, this message translates to:
  /// **'Your order hasn\'t gone through. We can keep it on this phone and send it automatically when you\'re back online — and if the price changes, we\'ll ask you first.'**
  String get offlineQueueBody;

  /// No description provided for @offlineQueueAction.
  ///
  /// In en, this message translates to:
  /// **'Place when back online'**
  String get offlineQueueAction;

  /// No description provided for @offlineQueueCashOnly.
  ///
  /// In en, this message translates to:
  /// **'Only cash orders can wait for the connection. Choose cash, or try again when you\'re back online.'**
  String get offlineQueueCashOnly;

  /// No description provided for @offlineQueued.
  ///
  /// In en, this message translates to:
  /// **'Order saved on this phone. It will be sent when you\'re back online.'**
  String get offlineQueued;

  /// No description provided for @offlineQueueSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the order on this phone, so nothing was queued.'**
  String get offlineQueueSaveFailed;

  /// No description provided for @offlineAlreadyPlaced.
  ///
  /// In en, this message translates to:
  /// **'Your earlier try already went through, so that\'s the order we placed.'**
  String get offlineAlreadyPlaced;

  /// No description provided for @offlineSent.
  ///
  /// In en, this message translates to:
  /// **'Your queued order from {store} was placed.'**
  String offlineSent(String store);

  /// No description provided for @offlineQueueUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Orders split with friends can\'t wait for the connection: each friend\'s share is linked to the order the moment it\'s placed. Try again when you\'re back online.'**
  String get offlineQueueUnavailable;

  /// No description provided for @offlineQueuedWhenAmount.
  ///
  /// In en, this message translates to:
  /// **'Queued {when} • {amount}'**
  String offlineQueuedWhenAmount(String when, String amount);

  /// No description provided for @offlineMaybePlaced.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm this went through. We\'ll check again automatically — it won\'t be placed twice.'**
  String get offlineMaybePlaced;

  /// No description provided for @offlineStaleMaybePlaced.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm this went through, and it has been waiting a while. Send it again to find out: if it already went through, you\'ll get that order, not a second one.'**
  String get offlineStaleMaybePlaced;

  /// No description provided for @offlineSendAgain.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get offlineSendAgain;

  /// No description provided for @offlineDiscardMaybePlacedBody.
  ///
  /// In en, this message translates to:
  /// **'It may already have been placed — we couldn\'t confirm it. Discarding only removes it from this phone, so check Orders to see whether it went through.'**
  String get offlineDiscardMaybePlacedBody;

  /// No description provided for @offlineUnconfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your order'**
  String get offlineUnconfirmedTitle;

  /// No description provided for @offlineUnconfirmedLead.
  ///
  /// In en, this message translates to:
  /// **'It may have gone through before the connection dropped — check Orders once you\'re back online.'**
  String get offlineUnconfirmedLead;

  /// No description provided for @offlineQueueResendBody.
  ///
  /// In en, this message translates to:
  /// **'We can keep it on this phone and send it again when you\'re back online. If it already went through, you\'ll get that order, not a second one — and if the price changes, we\'ll ask you first.'**
  String get offlineQueueResendBody;

  /// No description provided for @offlineUnconfirmedRetry.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your order — it may have gone through. Trying again is safe: it won\'t be placed twice.'**
  String get offlineUnconfirmedRetry;

  /// No description provided for @offlineQueueStandardOnly.
  ///
  /// In en, this message translates to:
  /// **'Express orders can\'t wait for the connection: the express price is only set when the order is placed. Choose Standard, or try again when you\'re back online.'**
  String get offlineQueueStandardOnly;

  /// No description provided for @offlineQueueTotalUnknown.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm this order\'s total for this address, so it can\'t wait for the connection. Try again when you\'re back online.'**
  String get offlineQueueTotalUnknown;

  /// No description provided for @carrCashNavLabel.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation'**
  String get carrCashNavLabel;

  /// No description provided for @carrCashTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider Cash Reconciliation'**
  String get carrCashTitle;

  /// No description provided for @carrCashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match the cash your riders collected against what they hand over'**
  String get carrCashSubtitle;

  /// No description provided for @carrCashTodayChip.
  ///
  /// In en, this message translates to:
  /// **'Today: {date}'**
  String carrCashTodayChip(String date);

  /// No description provided for @carrCashDayChip.
  ///
  /// In en, this message translates to:
  /// **'Day: {date}'**
  String carrCashDayChip(String date);

  /// No description provided for @carrCashPickDay.
  ///
  /// In en, this message translates to:
  /// **'Which day?'**
  String get carrCashPickDay;

  /// No description provided for @carrCashKpiWithRiders.
  ///
  /// In en, this message translates to:
  /// **'With your riders'**
  String get carrCashKpiWithRiders;

  /// No description provided for @carrCashKpiWithRidersNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nobody is holding cash} =1{Held by 1 rider} other{Held by {count} riders}}'**
  String carrCashKpiWithRidersNote(int count);

  /// No description provided for @carrCashKpiHandedOver.
  ///
  /// In en, this message translates to:
  /// **'Handed over'**
  String get carrCashKpiHandedOver;

  /// No description provided for @carrCashKpiHandedOverNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No hand-overs on this day} =1{1 hand-over on this day} other{{count} hand-overs on this day}}'**
  String carrCashKpiHandedOverNote(int count);

  /// No description provided for @carrCashKpiOwed.
  ///
  /// In en, this message translates to:
  /// **'Owed to YouDrop'**
  String get carrCashKpiOwed;

  /// No description provided for @carrCashKpiOwedNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Your company holds no cash} =1{Held by your company · 1 order} other{Held by your company · {count} orders}}'**
  String carrCashKpiOwedNote(int count);

  /// No description provided for @carrCashKpiOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get carrCashKpiOverdue;

  /// No description provided for @carrCashKpiOverdueNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nobody past the {hours}h limit} =1{1 rider past the {hours}h limit} other{{count} riders past the {hours}h limit}}'**
  String carrCashKpiOverdueNote(int count, int hours);

  /// No description provided for @carrCashOverdueSoftNote.
  ///
  /// In en, this message translates to:
  /// **'Some cash has been held for longer than {hours} hours. Ask those riders to hand it over.'**
  String carrCashOverdueSoftNote(int hours);

  /// No description provided for @carrCashBalancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider balances'**
  String get carrCashBalancesTitle;

  /// No description provided for @carrCashColRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get carrCashColRider;

  /// No description provided for @carrCashColCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get carrCashColCollected;

  /// No description provided for @carrCashColEarned.
  ///
  /// In en, this message translates to:
  /// **'Fees earned for you'**
  String get carrCashColEarned;

  /// No description provided for @carrCashColHolding.
  ///
  /// In en, this message translates to:
  /// **'Cash to hand over'**
  String get carrCashColHolding;

  /// No description provided for @carrCashColLastHandover.
  ///
  /// In en, this message translates to:
  /// **'Last hand-over'**
  String get carrCashColLastHandover;

  /// No description provided for @carrCashColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get carrCashColStatus;

  /// No description provided for @carrCashColActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get carrCashColActions;

  /// No description provided for @carrCashStatusHolding.
  ///
  /// In en, this message translates to:
  /// **'Holding cash'**
  String get carrCashStatusHolding;

  /// No description provided for @carrCashStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue {hours}h'**
  String carrCashStatusOverdue(int hours);

  /// No description provided for @carrCashStatusSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get carrCashStatusSettled;

  /// No description provided for @carrCashActionSettle.
  ///
  /// In en, this message translates to:
  /// **'Settle'**
  String get carrCashActionSettle;

  /// No description provided for @carrCashActionView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get carrCashActionView;

  /// No description provided for @carrCashNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get carrCashNever;

  /// No description provided for @carrCashToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get carrCashToday;

  /// No description provided for @carrCashYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get carrCashYesterday;

  /// No description provided for @carrCashDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String carrCashDaysAgo(int count);

  /// No description provided for @carrCashNobodyYet.
  ///
  /// In en, this message translates to:
  /// **'None of your riders has carried cash for your company yet.'**
  String get carrCashNobodyYet;

  /// No description provided for @carrCashTableNote.
  ///
  /// In en, this message translates to:
  /// **'Collected and fees are for the day chosen. Cash to hand over is everything still held, whenever it was collected. What your company pays its riders is agreed between you and is not shown here.'**
  String get carrCashTableNote;

  /// No description provided for @carrCashSelectRider.
  ///
  /// In en, this message translates to:
  /// **'Select {name}'**
  String carrCashSelectRider(String name);

  /// No description provided for @carrCashSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select every rider holding cash'**
  String get carrCashSelectAll;

  /// No description provided for @carrCashSettleSelected.
  ///
  /// In en, this message translates to:
  /// **'Settle selected'**
  String get carrCashSettleSelected;

  /// No description provided for @carrCashSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None selected} =1{1 selected} other{{count} selected}}'**
  String carrCashSelectedCount(int count);

  /// No description provided for @carrCashExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get carrCashExportCsv;

  /// No description provided for @carrCashExported.
  ///
  /// In en, this message translates to:
  /// **'Saved {file}'**
  String carrCashExported(String file);

  /// No description provided for @carrCashCsvRiderId.
  ///
  /// In en, this message translates to:
  /// **'Rider ID'**
  String get carrCashCsvRiderId;

  /// No description provided for @carrCashCsvOrdersHeld.
  ///
  /// In en, this message translates to:
  /// **'Orders held'**
  String get carrCashCsvOrdersHeld;

  /// No description provided for @carrCashCsvOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest collection'**
  String get carrCashCsvOldest;

  /// No description provided for @carrCashOrderCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order} other{{count} orders}}'**
  String carrCashOrderCount(int count);

  /// No description provided for @carrCashConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a hand-over'**
  String get carrCashConfirmTitle;

  /// No description provided for @carrCashConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm {name} has handed your company {amount} in cash, for {orders}. This clears their whole balance with you and cannot be undone.'**
  String carrCashConfirmBody(String name, String amount, String orders);

  /// No description provided for @carrCashConfirmBulkTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Record 1 hand-over} other{Record {count} hand-overs}}'**
  String carrCashConfirmBulkTitle(int count);

  /// No description provided for @carrCashConfirmBulkBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm each of these riders has handed your company the cash shown. Every balance is cleared in full and none of it can be undone.'**
  String get carrCashConfirmBulkBody;

  /// No description provided for @carrCashConfirmBulkTotal.
  ///
  /// In en, this message translates to:
  /// **'Total {amount}'**
  String carrCashConfirmBulkTotal(String amount);

  /// No description provided for @carrCashConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, record it'**
  String get carrCashConfirmYes;

  /// No description provided for @carrCashMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'How it was handed over'**
  String get carrCashMethodLabel;

  /// No description provided for @carrCashMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash hand-over'**
  String get carrCashMethodCash;

  /// No description provided for @carrCashMethodBank.
  ///
  /// In en, this message translates to:
  /// **'Bank deposit'**
  String get carrCashMethodBank;

  /// No description provided for @carrCashMethodWallet.
  ///
  /// In en, this message translates to:
  /// **'Money transfer app'**
  String get carrCashMethodWallet;

  /// No description provided for @carrCashNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get carrCashNoteLabel;

  /// No description provided for @carrCashNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Anything the hub should remember, like a bag number'**
  String get carrCashNoteHint;

  /// No description provided for @carrCashRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded {amount} from {name}.'**
  String carrCashRecorded(String amount, String name);

  /// No description provided for @carrCashReplayed.
  ///
  /// In en, this message translates to:
  /// **'That hand-over was already recorded, so nothing was recorded twice.'**
  String get carrCashReplayed;

  /// No description provided for @carrCashAmountChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} is now holding {amount}, not the amount you confirmed. Nothing was recorded; count it again.'**
  String carrCashAmountChanged(String name, String amount);

  /// No description provided for @carrCashAmountChangedUnknown.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s balance changed since you opened the page. Nothing was recorded; reload and count it again.'**
  String carrCashAmountChangedUnknown(String name);

  /// No description provided for @carrCashRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not record it. Nothing was changed; try again.'**
  String get carrCashRecordFailed;

  /// No description provided for @carrCashBulkDone.
  ///
  /// In en, this message translates to:
  /// **'Recorded {done} of {total}.'**
  String carrCashBulkDone(int done, int total);

  /// No description provided for @carrCashLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Your company\'s cash could not be loaded just now. Nothing is wrong with your records; try again.'**
  String get carrCashLoadFailed;

  /// No description provided for @carrCashTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get carrCashTryAgain;

  /// No description provided for @carrCashRiderTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider Settlement Detail'**
  String get carrCashRiderTitle;

  /// No description provided for @carrCashRiderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reconcile the cash bag with {name}'**
  String carrCashRiderSubtitle(String name);

  /// No description provided for @carrCashBack.
  ///
  /// In en, this message translates to:
  /// **'Back to reconciliation'**
  String get carrCashBack;

  /// No description provided for @carrCashBadgeUnsettled.
  ///
  /// In en, this message translates to:
  /// **'Unsettled balance'**
  String get carrCashBadgeUnsettled;

  /// No description provided for @carrCashRiderSince.
  ///
  /// In en, this message translates to:
  /// **'Carrying cash for you since {date}'**
  String carrCashRiderSince(String date);

  /// No description provided for @carrCashRatings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{(1 rating)} other{({count} ratings)}}'**
  String carrCashRatings(int count);

  /// No description provided for @carrCashRatingNew.
  ///
  /// In en, this message translates to:
  /// **'New rider'**
  String get carrCashRatingNew;

  /// No description provided for @carrCashHeldTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsettled deliveries'**
  String get carrCashHeldTitle;

  /// No description provided for @carrCashColOrder.
  ///
  /// In en, this message translates to:
  /// **'Order #'**
  String get carrCashColOrder;

  /// No description provided for @carrCashColCash.
  ///
  /// In en, this message translates to:
  /// **'Total cash'**
  String get carrCashColCash;

  /// No description provided for @carrCashColFee.
  ///
  /// In en, this message translates to:
  /// **'Fee earned for you'**
  String get carrCashColFee;

  /// No description provided for @carrCashHeldEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to settle: this rider is holding none of your company\'s cash.'**
  String get carrCashHeldEmpty;

  /// No description provided for @carrCashSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation summary'**
  String get carrCashSummaryTitle;

  /// No description provided for @carrCashSummaryCollected.
  ///
  /// In en, this message translates to:
  /// **'Cash collected, not yet handed over'**
  String get carrCashSummaryCollected;

  /// No description provided for @carrCashSummaryFees.
  ///
  /// In en, this message translates to:
  /// **'Fees earned for your company'**
  String get carrCashSummaryFees;

  /// No description provided for @carrCashSummaryDue.
  ///
  /// In en, this message translates to:
  /// **'Cash due to your company'**
  String get carrCashSummaryDue;

  /// No description provided for @carrCashSummaryKeeps.
  ///
  /// In en, this message translates to:
  /// **'The rider keeps none of this cash. What your company pays them is agreed between you, and the fees above are paid to your company by YouDrop, not taken from the cash.'**
  String get carrCashSummaryKeeps;

  /// No description provided for @carrCashConfirmSettlement.
  ///
  /// In en, this message translates to:
  /// **'Confirm settlement'**
  String get carrCashConfirmSettlement;

  /// No description provided for @carrCashNothingToSettle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to settle'**
  String get carrCashNothingToSettle;

  /// No description provided for @carrCashHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Hand-over history'**
  String get carrCashHistoryTitle;

  /// No description provided for @carrCashHistoryItem.
  ///
  /// In en, this message translates to:
  /// **'Hand-over · {date}'**
  String carrCashHistoryItem(String date);

  /// No description provided for @carrCashHistoryDetail.
  ///
  /// In en, this message translates to:
  /// **'{amount} for {orders}, recorded by {name}'**
  String carrCashHistoryDetail(String amount, String orders, String name);

  /// No description provided for @carrCashHistoryDetailAnon.
  ///
  /// In en, this message translates to:
  /// **'{amount} for {orders}'**
  String carrCashHistoryDetailAnon(String amount, String orders);

  /// No description provided for @carrCashHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No hand-overs recorded yet.'**
  String get carrCashHistoryEmpty;

  /// No description provided for @carrCashRiderNotFound.
  ///
  /// In en, this message translates to:
  /// **'This rider has never worked for your company.'**
  String get carrCashRiderNotFound;

  /// No description provided for @carrCashBoTitle.
  ///
  /// In en, this message translates to:
  /// **'Held by delivery companies'**
  String get carrCashBoTitle;

  /// No description provided for @carrCashBoOwes.
  ///
  /// In en, this message translates to:
  /// **'Owes the platform'**
  String get carrCashBoOwes;

  /// No description provided for @carrCashBoWithRiders.
  ///
  /// In en, this message translates to:
  /// **'With its riders: {amount}'**
  String carrCashBoWithRiders(String amount);

  /// No description provided for @carrCashBoLastPaid.
  ///
  /// In en, this message translates to:
  /// **'Last paid {when}'**
  String carrCashBoLastPaid(String when);

  /// No description provided for @carrCashBoNeverPaid.
  ///
  /// In en, this message translates to:
  /// **'Never paid'**
  String get carrCashBoNeverPaid;

  /// No description provided for @carrCashBoHoldsNothing.
  ///
  /// In en, this message translates to:
  /// **'Holds nothing itself yet'**
  String get carrCashBoHoldsNothing;

  /// No description provided for @carrCashBoRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get carrCashBoRecordPayment;

  /// No description provided for @carrCashBoConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a payment'**
  String get carrCashBoConfirmTitle;

  /// No description provided for @carrCashBoConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm {company} has paid the platform {amount}, covering {orders}. This clears everything the company holds and cannot be undone.'**
  String carrCashBoConfirmBody(String company, String amount, String orders);

  /// No description provided for @carrCashBoConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, they paid'**
  String get carrCashBoConfirmYes;

  /// No description provided for @carrCashBoRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded {amount} from {company}.'**
  String carrCashBoRecorded(String amount, String company);

  /// No description provided for @carrCashBoNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing was outstanding; somebody may have recorded this already.'**
  String get carrCashBoNothing;

  /// No description provided for @carrCashBoAmountChanged.
  ///
  /// In en, this message translates to:
  /// **'{company} now holds {amount}, not the amount you confirmed. Nothing was recorded.'**
  String carrCashBoAmountChanged(String company, String amount);

  /// No description provided for @carrCashBoFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not record it: {error}'**
  String carrCashBoFailed(String error);

  /// No description provided for @carrCashBoOverdueNote.
  ///
  /// In en, this message translates to:
  /// **'Some cash has been out longer than the platform\'s limit. Nothing is wrong with the ledger: this is money the bank has not seen yet.'**
  String get carrCashBoOverdueNote;

  /// No description provided for @carrCashBoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'What delivery companies hold could not be loaded just now. The rest of this page is unaffected.'**
  String get carrCashBoLoadFailed;

  /// No description provided for @carrCashBoMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'How it was paid (optional)'**
  String get carrCashBoMethodLabel;

  /// No description provided for @dekkaneBrowseTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Neighborhood'**
  String get dekkaneBrowseTitle;

  /// No description provided for @dekkaneBrowseSubRegion.
  ///
  /// In en, this message translates to:
  /// **'Local {region} dekkanes'**
  String dekkaneBrowseSubRegion(String region);

  /// No description provided for @dekkaneAreaInRegion.
  ///
  /// In en, this message translates to:
  /// **'{area}, {region}'**
  String dekkaneAreaInRegion(String area, String region);

  /// No description provided for @dekkaneEntrySub.
  ///
  /// In en, this message translates to:
  /// **'The dekkanes and small shops around your address'**
  String get dekkaneEntrySub;

  /// No description provided for @dekkaneFilterOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get dekkaneFilterOpenNow;

  /// No description provided for @dekkaneFilterOnGenerator.
  ///
  /// In en, this message translates to:
  /// **'On generator now'**
  String get dekkaneFilterOnGenerator;

  /// No description provided for @dekkaneFilterNew.
  ///
  /// In en, this message translates to:
  /// **'New on YouDrop'**
  String get dekkaneFilterNew;

  /// No description provided for @dekkaneExpandMap.
  ///
  /// In en, this message translates to:
  /// **'Expand interactive map'**
  String get dekkaneExpandMap;

  /// No description provided for @dekkaneNearbyShops.
  ///
  /// In en, this message translates to:
  /// **'Shops near you'**
  String get dekkaneNearbyShops;

  /// No description provided for @dekkaneLocalShops.
  ///
  /// In en, this message translates to:
  /// **'Local shops'**
  String get dekkaneLocalShops;

  /// No description provided for @dekkaneDistanceMetres.
  ///
  /// In en, this message translates to:
  /// **'{metres} m away'**
  String dekkaneDistanceMetres(int metres);

  /// No description provided for @dekkaneDistanceKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km away'**
  String dekkaneDistanceKm(double km);

  /// No description provided for @dekkaneGeneratorActive.
  ///
  /// In en, this message translates to:
  /// **'Generator active'**
  String get dekkaneGeneratorActive;

  /// No description provided for @dekkaneTrustedLocal.
  ///
  /// In en, this message translates to:
  /// **'Trusted local'**
  String get dekkaneTrustedLocal;

  /// No description provided for @dekkaneCouldNotLoadShops.
  ///
  /// In en, this message translates to:
  /// **'Could not load the shops around you'**
  String get dekkaneCouldNotLoadShops;

  /// No description provided for @dekkanePinAddressPrompt.
  ///
  /// In en, this message translates to:
  /// **'Pin your address on the map to see the shops nearest you, and how far each one is.'**
  String get dekkanePinAddressPrompt;

  /// No description provided for @dekkaneNoShopsNearby.
  ///
  /// In en, this message translates to:
  /// **'No shops near this address yet'**
  String get dekkaneNoShopsNearby;

  /// No description provided for @dekkaneMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Shops on the map'**
  String get dekkaneMapTitle;

  /// No description provided for @dekkaneOpenClosesAt.
  ///
  /// In en, this message translates to:
  /// **'Open · Closes {time}'**
  String dekkaneOpenClosesAt(String time);

  /// No description provided for @dekkaneShopInventory.
  ///
  /// In en, this message translates to:
  /// **'Shop inventory'**
  String get dekkaneShopInventory;

  /// No description provided for @dekkaneLbpAmount.
  ///
  /// In en, this message translates to:
  /// **'LBP {amount}'**
  String dekkaneLbpAmount(int amount);

  /// No description provided for @dekkaneAddOneMore.
  ///
  /// In en, this message translates to:
  /// **'Add one more'**
  String get dekkaneAddOneMore;

  /// No description provided for @dekkaneMerchNeighborhood.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood'**
  String get dekkaneMerchNeighborhood;

  /// No description provided for @dekkaneMerchNeighborhoodHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Mar Mikhael'**
  String get dekkaneMerchNeighborhoodHint;

  /// No description provided for @dekkaneMerchNeighborhoodHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown under your shop\'s name when customers open your shop from their neighborhood list.'**
  String get dekkaneMerchNeighborhoodHelp;

  /// No description provided for @dekkaneMerchNeighborhoodTooLong.
  ///
  /// In en, this message translates to:
  /// **'Keep it to 80 characters or fewer'**
  String get dekkaneMerchNeighborhoodTooLong;

  /// No description provided for @dekkaneCouldNotLoadShelf.
  ///
  /// In en, this message translates to:
  /// **'Could not load this shop\'s shelves'**
  String get dekkaneCouldNotLoadShelf;

  /// No description provided for @dekkaneBrowseTitleAll.
  ///
  /// In en, this message translates to:
  /// **'Shops on YouDrop'**
  String get dekkaneBrowseTitleAll;

  /// No description provided for @dekkaneBrowseSubAll.
  ///
  /// In en, this message translates to:
  /// **'Every shop, best rated first'**
  String get dekkaneBrowseSubAll;

  /// No description provided for @dekkaneAllShops.
  ///
  /// In en, this message translates to:
  /// **'All shops'**
  String get dekkaneAllShops;

  /// No description provided for @dekkanePowerUpdatedMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{Updated just now} =1{Updated 1 min ago} other{Updated {minutes} min ago}}'**
  String dekkanePowerUpdatedMinutes(int minutes);

  /// No description provided for @dekkanePowerUpdatedHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{Updated 1 hr ago} other{Updated {hours} hrs ago}}'**
  String dekkanePowerUpdatedHours(int hours);

  /// No description provided for @dekkaneSearchedNearest.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Only the nearest shop was searched} other{Only the nearest {count} shops were searched}}'**
  String dekkaneSearchedNearest(int count);

  /// No description provided for @attendanceNavShifts.
  ///
  /// In en, this message translates to:
  /// **'Shifts & attendance'**
  String get attendanceNavShifts;

  /// No description provided for @attendanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider Attendance & Shift Logs'**
  String get attendanceTitle;

  /// No description provided for @attendanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track daily check-ins, lates, absences, and shift overrides'**
  String get attendanceSubtitle;

  /// No description provided for @attendanceForMonth.
  ///
  /// In en, this message translates to:
  /// **'Attendance & clock logs for {month}'**
  String attendanceForMonth(String month);

  /// No description provided for @attendanceBackToRiders.
  ///
  /// In en, this message translates to:
  /// **'Back to riders'**
  String get attendanceBackToRiders;

  /// No description provided for @attendanceManualLog.
  ///
  /// In en, this message translates to:
  /// **'Manual Attendance Log'**
  String get attendanceManualLog;

  /// No description provided for @attendancePrevMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get attendancePrevMonth;

  /// No description provided for @attendanceNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get attendanceNextMonth;

  /// No description provided for @attendanceLegendPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get attendanceLegendPresent;

  /// No description provided for @attendanceLegendLate.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get attendanceLegendLate;

  /// No description provided for @attendanceLegendAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get attendanceLegendAbsent;

  /// No description provided for @attendanceLegendOff.
  ///
  /// In en, this message translates to:
  /// **'Day off'**
  String get attendanceLegendOff;

  /// No description provided for @attendanceLegendOnDuty.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get attendanceLegendOnDuty;

  /// No description provided for @attendanceWeekMon.
  ///
  /// In en, this message translates to:
  /// **'MON'**
  String get attendanceWeekMon;

  /// No description provided for @attendanceWeekTue.
  ///
  /// In en, this message translates to:
  /// **'TUE'**
  String get attendanceWeekTue;

  /// No description provided for @attendanceWeekWed.
  ///
  /// In en, this message translates to:
  /// **'WED'**
  String get attendanceWeekWed;

  /// No description provided for @attendanceWeekThu.
  ///
  /// In en, this message translates to:
  /// **'THU'**
  String get attendanceWeekThu;

  /// No description provided for @attendanceWeekFri.
  ///
  /// In en, this message translates to:
  /// **'FRI'**
  String get attendanceWeekFri;

  /// No description provided for @attendanceWeekSat.
  ///
  /// In en, this message translates to:
  /// **'SAT'**
  String get attendanceWeekSat;

  /// No description provided for @attendanceWeekSun.
  ///
  /// In en, this message translates to:
  /// **'SUN'**
  String get attendanceWeekSun;

  /// No description provided for @attendanceAggregatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Attendance Aggregates'**
  String get attendanceAggregatesTitle;

  /// No description provided for @attendanceDaysWorked.
  ///
  /// In en, this message translates to:
  /// **'Days worked'**
  String get attendanceDaysWorked;

  /// No description provided for @attendanceAbsences.
  ///
  /// In en, this message translates to:
  /// **'Absences'**
  String get attendanceAbsences;

  /// No description provided for @attendanceTimesLate.
  ///
  /// In en, this message translates to:
  /// **'Times late'**
  String get attendanceTimesLate;

  /// No description provided for @attendanceOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime accumulated'**
  String get attendanceOvertime;

  /// No description provided for @attendanceHoursOnDuty.
  ///
  /// In en, this message translates to:
  /// **'Hours on duty'**
  String get attendanceHoursOnDuty;

  /// No description provided for @attendanceManualHours.
  ///
  /// In en, this message translates to:
  /// **'Hours logged by hand'**
  String get attendanceManualHours;

  /// No description provided for @attendanceExcusedDays.
  ///
  /// In en, this message translates to:
  /// **'Excused, sick or on leave'**
  String get attendanceExcusedDays;

  /// No description provided for @attendanceDaysCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String attendanceDaysCount(int count);

  /// No description provided for @attendanceHoursValue.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours'**
  String attendanceHoursValue(String hours);

  /// No description provided for @attendanceHoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours} hrs'**
  String attendanceHoursShort(String hours);

  /// No description provided for @attendanceLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Clock-In / Clock-Out Logs'**
  String get attendanceLogsTitle;

  /// No description provided for @attendanceColDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get attendanceColDate;

  /// No description provided for @attendanceColShift.
  ///
  /// In en, this message translates to:
  /// **'Scheduled shift'**
  String get attendanceColShift;

  /// No description provided for @attendanceColClockIn.
  ///
  /// In en, this message translates to:
  /// **'Clock in'**
  String get attendanceColClockIn;

  /// No description provided for @attendanceColClockOut.
  ///
  /// In en, this message translates to:
  /// **'Clock out'**
  String get attendanceColClockOut;

  /// No description provided for @attendanceColHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get attendanceColHours;

  /// No description provided for @attendanceColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get attendanceColStatus;

  /// No description provided for @attendanceColNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get attendanceColNotes;

  /// No description provided for @attendanceShiftLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} ({start} - {end})'**
  String attendanceShiftLabel(String name, String start, String end);

  /// No description provided for @attendanceStatusOnTime.
  ///
  /// In en, this message translates to:
  /// **'On time'**
  String get attendanceStatusOnTime;

  /// No description provided for @attendanceStatusLate.
  ///
  /// In en, this message translates to:
  /// **'Late check-in'**
  String get attendanceStatusLate;

  /// No description provided for @attendanceStatusAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get attendanceStatusAbsent;

  /// No description provided for @attendanceStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Not in yet'**
  String get attendanceStatusPending;

  /// No description provided for @attendanceStatusDayOff.
  ///
  /// In en, this message translates to:
  /// **'Day off'**
  String get attendanceStatusDayOff;

  /// No description provided for @attendanceStatusExtra.
  ///
  /// In en, this message translates to:
  /// **'Worked a day off'**
  String get attendanceStatusExtra;

  /// No description provided for @attendanceStatusWorked.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get attendanceStatusWorked;

  /// No description provided for @attendanceStatusLateExcused.
  ///
  /// In en, this message translates to:
  /// **'Late (excused)'**
  String get attendanceStatusLateExcused;

  /// No description provided for @attendanceStatusExcused.
  ///
  /// In en, this message translates to:
  /// **'Excused'**
  String get attendanceStatusExcused;

  /// No description provided for @attendanceStatusSick.
  ///
  /// In en, this message translates to:
  /// **'Sick leave'**
  String get attendanceStatusSick;

  /// No description provided for @attendanceStatusLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get attendanceStatusLeave;

  /// No description provided for @attendanceOnShiftNow.
  ///
  /// In en, this message translates to:
  /// **'On shift now'**
  String get attendanceOnShiftNow;

  /// No description provided for @attendanceAutoClosed.
  ///
  /// In en, this message translates to:
  /// **'Auto-closed: signal lost'**
  String get attendanceAutoClosed;

  /// No description provided for @attendanceLateBy.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min late'**
  String attendanceLateBy(int minutes);

  /// No description provided for @attendanceOvertimeNote.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min overtime'**
  String attendanceOvertimeNote(int minutes);

  /// No description provided for @attendanceLoggedByHand.
  ///
  /// In en, this message translates to:
  /// **'Logged by hand'**
  String get attendanceLoggedByHand;

  /// No description provided for @attendanceNoSchedule.
  ///
  /// In en, this message translates to:
  /// **'No shift schedule is set for this rider, so only time on duty is shown.'**
  String get attendanceNoSchedule;

  /// No description provided for @attendanceEmptyMonth.
  ///
  /// In en, this message translates to:
  /// **'No duty recorded for this month. History starts when duty tracking began; nothing is backfilled.'**
  String get attendanceEmptyMonth;

  /// No description provided for @attendanceZoneNote.
  ///
  /// In en, this message translates to:
  /// **'Days are split in the {zone} time zone.'**
  String attendanceZoneNote(String zone);

  /// No description provided for @attendanceNotOnFleet.
  ///
  /// In en, this message translates to:
  /// **'This rider is not linked to your fleet in tracking yet, so their attendance cannot be read. That happens when tracking hears of the hire, or when they carry an order for your company.'**
  String get attendanceNotOnFleet;

  /// No description provided for @attendanceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Attendance could not be loaded just now.'**
  String get attendanceLoadFailed;

  /// No description provided for @attendanceLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Log attendance for {name}'**
  String attendanceLogTitle(String name);

  /// No description provided for @attendanceLogStatus.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get attendanceLogStatus;

  /// No description provided for @attendanceLogChooseStatus.
  ///
  /// In en, this message translates to:
  /// **'Choose a status'**
  String get attendanceLogChooseStatus;

  /// No description provided for @attendanceKindPresent.
  ///
  /// In en, this message translates to:
  /// **'Present (not shown by the app)'**
  String get attendanceKindPresent;

  /// No description provided for @attendanceKindLateExcused.
  ///
  /// In en, this message translates to:
  /// **'Late, excused'**
  String get attendanceKindLateExcused;

  /// No description provided for @attendanceKindAbsentExcused.
  ///
  /// In en, this message translates to:
  /// **'Absent, excused'**
  String get attendanceKindAbsentExcused;

  /// No description provided for @attendanceKindSick.
  ///
  /// In en, this message translates to:
  /// **'Sick'**
  String get attendanceKindSick;

  /// No description provided for @attendanceKindLeave.
  ///
  /// In en, this message translates to:
  /// **'On leave'**
  String get attendanceKindLeave;

  /// No description provided for @attendanceLogClockIn.
  ///
  /// In en, this message translates to:
  /// **'Clock in (optional)'**
  String get attendanceLogClockIn;

  /// No description provided for @attendanceLogClockOut.
  ///
  /// In en, this message translates to:
  /// **'Clock out (optional)'**
  String get attendanceLogClockOut;

  /// No description provided for @attendanceLogNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get attendanceLogNote;

  /// No description provided for @attendanceLogSave.
  ///
  /// In en, this message translates to:
  /// **'Save entry'**
  String get attendanceLogSave;

  /// No description provided for @attendanceLogWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Remove entry'**
  String get attendanceLogWithdraw;

  /// No description provided for @attendanceLogSaved.
  ///
  /// In en, this message translates to:
  /// **'Attendance entry saved.'**
  String get attendanceLogSaved;

  /// No description provided for @attendanceLogRemoved.
  ///
  /// In en, this message translates to:
  /// **'Entry removed. The day shows what the app recorded.'**
  String get attendanceLogRemoved;

  /// No description provided for @attendanceLogTimesRule.
  ///
  /// In en, this message translates to:
  /// **'Times go only on a present day, and need both a clock-in and a clock-out.'**
  String get attendanceLogTimesRule;

  /// No description provided for @attendanceLogManualNote.
  ///
  /// In en, this message translates to:
  /// **'Hours typed here are reported as manual, never as app evidence, and are ignored on a day the app already shows.'**
  String get attendanceLogManualNote;

  /// No description provided for @attendanceLogFutureRule.
  ///
  /// In en, this message translates to:
  /// **'A day that has not happened yet can only be marked as leave, sick or excused.'**
  String get attendanceLogFutureRule;

  /// No description provided for @attendanceTimeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a 24-hour time such as 08:00.'**
  String get attendanceTimeInvalid;

  /// No description provided for @attendanceShiftsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift schedules'**
  String get attendanceShiftsTitle;

  /// No description provided for @attendanceShiftsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set the shifts your riders work, then open anyone’s monthly attendance.'**
  String get attendanceShiftsSubtitle;

  /// No description provided for @attendanceShiftsCard.
  ///
  /// In en, this message translates to:
  /// **'Shifts'**
  String get attendanceShiftsCard;

  /// No description provided for @attendanceAddShift.
  ///
  /// In en, this message translates to:
  /// **'Add shift'**
  String get attendanceAddShift;

  /// No description provided for @attendanceNoShifts.
  ///
  /// In en, this message translates to:
  /// **'No shifts yet. Riders without a shift are treated as freelancers: never late, never absent.'**
  String get attendanceNoShifts;

  /// No description provided for @attendanceShiftGrace.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min grace'**
  String attendanceShiftGrace(int minutes);

  /// No description provided for @attendanceShiftRiders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No riders} =1{1 rider} other{{count} riders}}'**
  String attendanceShiftRiders(int count);

  /// No description provided for @attendanceShiftOvernight.
  ///
  /// In en, this message translates to:
  /// **'Ends next day'**
  String get attendanceShiftOvernight;

  /// No description provided for @attendanceRetireShift.
  ///
  /// In en, this message translates to:
  /// **'Retire shift'**
  String get attendanceRetireShift;

  /// No description provided for @attendanceRetireBlocked.
  ///
  /// In en, this message translates to:
  /// **'Move the riders on this shift to another one first.'**
  String get attendanceRetireBlocked;

  /// No description provided for @attendanceShiftRetired.
  ///
  /// In en, this message translates to:
  /// **'Shift retired.'**
  String get attendanceShiftRetired;

  /// No description provided for @attendanceRidersCard.
  ///
  /// In en, this message translates to:
  /// **'Riders'**
  String get attendanceRidersCard;

  /// No description provided for @attendanceColRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get attendanceColRider;

  /// No description provided for @attendanceColCurrentShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get attendanceColCurrentShift;

  /// No description provided for @attendanceColActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get attendanceColActions;

  /// No description provided for @attendanceFreelancer.
  ///
  /// In en, this message translates to:
  /// **'No schedule (freelancer)'**
  String get attendanceFreelancer;

  /// No description provided for @attendanceChangeShift.
  ///
  /// In en, this message translates to:
  /// **'Change shift'**
  String get attendanceChangeShift;

  /// No description provided for @attendanceOpenAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendanceOpenAttendance;

  /// No description provided for @attendanceUpcomingShift.
  ///
  /// In en, this message translates to:
  /// **'{name} from {date}'**
  String attendanceUpcomingShift(String name, String date);

  /// No description provided for @attendanceNoRiders.
  ///
  /// In en, this message translates to:
  /// **'No riders on your fleet yet.'**
  String get attendanceNoRiders;

  /// No description provided for @attendanceNewShiftTitle.
  ///
  /// In en, this message translates to:
  /// **'New shift'**
  String get attendanceNewShiftTitle;

  /// No description provided for @attendanceShiftName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get attendanceShiftName;

  /// No description provided for @attendanceShiftStart.
  ///
  /// In en, this message translates to:
  /// **'Starts (HH:mm)'**
  String get attendanceShiftStart;

  /// No description provided for @attendanceShiftEnd.
  ///
  /// In en, this message translates to:
  /// **'Ends (HH:mm)'**
  String get attendanceShiftEnd;

  /// No description provided for @attendanceShiftDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get attendanceShiftDays;

  /// No description provided for @attendanceShiftGraceField.
  ///
  /// In en, this message translates to:
  /// **'Grace before late (minutes)'**
  String get attendanceShiftGraceField;

  /// No description provided for @attendanceShiftImmutable.
  ///
  /// In en, this message translates to:
  /// **'Shift hours cannot be changed later. To change them, add a new shift and move riders onto it, so past days keep the shift they were worked against.'**
  String get attendanceShiftImmutable;

  /// No description provided for @attendanceCreateShift.
  ///
  /// In en, this message translates to:
  /// **'Create shift'**
  String get attendanceCreateShift;

  /// No description provided for @attendanceShiftCreated.
  ///
  /// In en, this message translates to:
  /// **'Shift created.'**
  String get attendanceShiftCreated;

  /// No description provided for @attendanceShiftNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Give the shift a name.'**
  String get attendanceShiftNeedsName;

  /// No description provided for @attendanceShiftNeedsDays.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one day.'**
  String get attendanceShiftNeedsDays;

  /// No description provided for @attendanceShiftSameTimes.
  ///
  /// In en, this message translates to:
  /// **'A shift cannot start and end at the same time.'**
  String get attendanceShiftSameTimes;

  /// No description provided for @attendanceGraceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a number of minutes from 0 to 120.'**
  String get attendanceGraceInvalid;

  /// No description provided for @attendanceAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift for {name}'**
  String attendanceAssignTitle(String name);

  /// No description provided for @attendanceAssignFrom.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get attendanceAssignFrom;

  /// No description provided for @attendanceAssignNote.
  ///
  /// In en, this message translates to:
  /// **'Schedules start today or later. Once today\'s shift has begun, or once the rider has worked today, a change for today starts tomorrow, so past days and the day under way keep the schedule they are judged against.'**
  String get attendanceAssignNote;

  /// No description provided for @attendanceAssignSave.
  ///
  /// In en, this message translates to:
  /// **'Save schedule'**
  String get attendanceAssignSave;

  /// No description provided for @attendanceAssignSaved.
  ///
  /// In en, this message translates to:
  /// **'Schedule updated.'**
  String get attendanceAssignSaved;

  /// No description provided for @attendanceHistoryLimit.
  ///
  /// In en, this message translates to:
  /// **'This month is older than the duty history the platform keeps, so it can no longer be shown.'**
  String get attendanceHistoryLimit;

  /// No description provided for @attendanceManualTag.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get attendanceManualTag;

  /// No description provided for @attendanceTypedByHand.
  ///
  /// In en, this message translates to:
  /// **'Typed by hand in the Manual Attendance Log, not recorded by the app'**
  String get attendanceTypedByHand;

  /// No description provided for @attendanceLogPresentKeepsLate.
  ///
  /// In en, this message translates to:
  /// **'Present does not clear a late check-in. To excuse one, choose “Late, excused”.'**
  String get attendanceLogPresentKeepsLate;

  /// No description provided for @attendanceLogChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking this day for an existing entry…'**
  String get attendanceLogChecking;

  /// No description provided for @attendanceLogCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'This day could not be checked for an existing entry, so nothing can be saved for it yet. Choose the date again to retry.'**
  String get attendanceLogCheckFailed;

  /// No description provided for @attendanceRetiredShifts.
  ///
  /// In en, this message translates to:
  /// **'Retired shifts ({count})'**
  String attendanceRetiredShifts(int count);

  /// No description provided for @attendanceRetireKeepsHistory.
  ///
  /// In en, this message translates to:
  /// **'Past days stay judged against this shift. Retiring it only stops it being offered for new schedules.'**
  String get attendanceRetireKeepsHistory;

  /// No description provided for @attendanceLiveOnDuty.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Live: no riders on duty} =1{Live: 1 rider on duty} other{Live: {count} riders on duty}}'**
  String attendanceLiveOnDuty(int count);

  /// No description provided for @carrRidersNavReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation'**
  String get carrRidersNavReconciliation;

  /// No description provided for @carrRidersNavRidersHr.
  ///
  /// In en, this message translates to:
  /// **'Riders HR'**
  String get carrRidersNavRidersHr;

  /// No description provided for @carrRidersNavDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get carrRidersNavDirectory;

  /// No description provided for @carrRidersNavStatement.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get carrRidersNavStatement;

  /// No description provided for @carrRidersTitle.
  ///
  /// In en, this message translates to:
  /// **'Riders HR Directory'**
  String get carrRidersTitle;

  /// No description provided for @carrRidersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage rider profiles, status and regions'**
  String get carrRidersSubtitle;

  /// No description provided for @carrRidersStatTotal.
  ///
  /// In en, this message translates to:
  /// **'Total onboarded riders'**
  String get carrRidersStatTotal;

  /// No description provided for @carrRidersStatTotalNote.
  ///
  /// In en, this message translates to:
  /// **'Registered company fleet'**
  String get carrRidersStatTotalNote;

  /// No description provided for @carrRidersStatOnDuty.
  ///
  /// In en, this message translates to:
  /// **'Active on duty'**
  String get carrRidersStatOnDuty;

  /// No description provided for @carrRidersStatOnDutyNote.
  ///
  /// In en, this message translates to:
  /// **'Available or on a job'**
  String get carrRidersStatOnDutyNote;

  /// No description provided for @carrRidersStatSignalLost.
  ///
  /// In en, this message translates to:
  /// **'Signal lost'**
  String get carrRidersStatSignalLost;

  /// No description provided for @carrRidersStatSignalLostNote.
  ///
  /// In en, this message translates to:
  /// **'On duty, but their phone has gone quiet'**
  String get carrRidersStatSignalLostNote;

  /// No description provided for @carrRidersStatOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline / inactive'**
  String get carrRidersStatOffline;

  /// No description provided for @carrRidersStatOfflineNote.
  ///
  /// In en, this message translates to:
  /// **'Declared themselves off duty'**
  String get carrRidersStatOfflineNote;

  /// No description provided for @carrRidersPresenceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Presence could not be read just now'**
  String get carrRidersPresenceUnknown;

  /// No description provided for @carrRidersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search riders by name, ID...'**
  String get carrRidersSearchHint;

  /// No description provided for @carrRidersZoneAll.
  ///
  /// In en, this message translates to:
  /// **'Zone: All'**
  String get carrRidersZoneAll;

  /// No description provided for @carrRidersZoneValue.
  ///
  /// In en, this message translates to:
  /// **'Zone: {zone}'**
  String carrRidersZoneValue(String zone);

  /// No description provided for @carrRidersZoneTooltip.
  ///
  /// In en, this message translates to:
  /// **'A zone here is the region each rider wrote on their application'**
  String get carrRidersZoneTooltip;

  /// No description provided for @carrRidersVehicleAll.
  ///
  /// In en, this message translates to:
  /// **'Vehicle: All'**
  String get carrRidersVehicleAll;

  /// No description provided for @carrRidersVehicleValue.
  ///
  /// In en, this message translates to:
  /// **'Vehicle: {vehicle}'**
  String carrRidersVehicleValue(String vehicle);

  /// No description provided for @carrRidersVehicleMotorcycle.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get carrRidersVehicleMotorcycle;

  /// No description provided for @carrRidersVehicleCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get carrRidersVehicleCar;

  /// No description provided for @carrRidersVehicleBicycle.
  ///
  /// In en, this message translates to:
  /// **'Bicycle'**
  String get carrRidersVehicleBicycle;

  /// No description provided for @carrRidersVehicleVan.
  ///
  /// In en, this message translates to:
  /// **'Van'**
  String get carrRidersVehicleVan;

  /// No description provided for @carrRidersVehicleTruck.
  ///
  /// In en, this message translates to:
  /// **'Truck'**
  String get carrRidersVehicleTruck;

  /// No description provided for @carrRidersAddRider.
  ///
  /// In en, this message translates to:
  /// **'Add Rider'**
  String get carrRidersAddRider;

  /// No description provided for @carrRidersAddRiderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Approve somebody who has applied to ride for you'**
  String get carrRidersAddRiderTooltip;

  /// No description provided for @carrRidersAddRiderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Applications could not be read just now, so nobody can be approved from here'**
  String get carrRidersAddRiderUnavailable;

  /// No description provided for @carrRidersManageProfile.
  ///
  /// In en, this message translates to:
  /// **'Manage Profile'**
  String get carrRidersManageProfile;

  /// No description provided for @carrRidersDeliveredToday.
  ///
  /// In en, this message translates to:
  /// **'({count} today)'**
  String carrRidersDeliveredToday(int count);

  /// No description provided for @carrRidersRatingNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get carrRidersRatingNew;

  /// No description provided for @carrRidersStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get carrRidersStatusActive;

  /// No description provided for @carrRidersStatusSignalLost.
  ///
  /// In en, this message translates to:
  /// **'Signal lost'**
  String get carrRidersStatusSignalLost;

  /// No description provided for @carrRidersStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get carrRidersStatusOffline;

  /// No description provided for @carrRidersStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get carrRidersStatusSuspended;

  /// No description provided for @carrRidersStatusOnAJob.
  ///
  /// In en, this message translates to:
  /// **'On a job'**
  String get carrRidersStatusOnAJob;

  /// No description provided for @carrRidersNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No rider matches that.'**
  String get carrRidersNoMatch;

  /// No description provided for @carrRidersShowingOnly.
  ///
  /// In en, this message translates to:
  /// **'Showing only: {filter}'**
  String carrRidersShowingOnly(String filter);

  /// No description provided for @carrRidersShowEveryone.
  ///
  /// In en, this message translates to:
  /// **'Show everyone'**
  String get carrRidersShowEveryone;

  /// No description provided for @carrRidersDirectoryFootnote.
  ///
  /// In en, this message translates to:
  /// **'Zone is the region each rider gave on their application — the platform does not assign riders to your coverage zones. Rating is what customers left across all of a rider\'s deliveries. Presence reaches this page once a rider has carried your work, so a rider who has not yet shows none.'**
  String get carrRidersDirectoryFootnote;

  /// No description provided for @carrRidersWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a rider'**
  String get carrRidersWaitingTitle;

  /// No description provided for @carrRidersWaitingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nobody is waiting to ride for you} =1{1 person waiting to ride for you} other{{count} people waiting to ride for you}}'**
  String carrRidersWaitingCount(int count);

  /// No description provided for @carrRidersWaitingEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has applied to ride for you. Riders reach a fleet by applying — there is no way to create one directly.'**
  String get carrRidersWaitingEmpty;

  /// No description provided for @carrRidersApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get carrRidersApprove;

  /// No description provided for @carrRidersOnYourFleet.
  ///
  /// In en, this message translates to:
  /// **'On your fleet'**
  String get carrRidersOnYourFleet;

  /// No description provided for @carrRidersSuspendTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}'**
  String carrRidersSuspendTitle(String name);

  /// No description provided for @carrRidersReinstateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reinstate {name}'**
  String carrRidersReinstateTitle(String name);

  /// No description provided for @carrRidersSuspendBody.
  ///
  /// In en, this message translates to:
  /// **'They keep their sign-in and their history, and stop being offered work. You can reinstate them at any time.'**
  String get carrRidersSuspendBody;

  /// No description provided for @carrRidersReinstateBody.
  ///
  /// In en, this message translates to:
  /// **'They can be offered work again from the moment this is saved.'**
  String get carrRidersReinstateBody;

  /// No description provided for @carrRidersChooseReason.
  ///
  /// In en, this message translates to:
  /// **'Choose a reason'**
  String get carrRidersChooseReason;

  /// No description provided for @carrRidersNoteHint.
  ///
  /// In en, this message translates to:
  /// **'A note for the record (optional)'**
  String get carrRidersNoteHint;

  /// No description provided for @carrRidersSuspendRider.
  ///
  /// In en, this message translates to:
  /// **'Suspend Rider'**
  String get carrRidersSuspendRider;

  /// No description provided for @carrRidersReinstateRider.
  ///
  /// In en, this message translates to:
  /// **'Reinstate Rider'**
  String get carrRidersReinstateRider;

  /// No description provided for @carrRidersSuspendedToast.
  ///
  /// In en, this message translates to:
  /// **'{name} is suspended and will not be offered work.'**
  String carrRidersSuspendedToast(String name);

  /// No description provided for @carrRidersReinstatedToast.
  ///
  /// In en, this message translates to:
  /// **'{name} can take work again.'**
  String carrRidersReinstatedToast(String name);

  /// No description provided for @carrRidersReasonFraud.
  ///
  /// In en, this message translates to:
  /// **'Fraud'**
  String get carrRidersReasonFraud;

  /// No description provided for @carrRidersReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse'**
  String get carrRidersReasonAbuse;

  /// No description provided for @carrRidersReasonNonPayment.
  ///
  /// In en, this message translates to:
  /// **'Non-payment'**
  String get carrRidersReasonNonPayment;

  /// No description provided for @carrRidersReasonPolicyViolation.
  ///
  /// In en, this message translates to:
  /// **'Policy violation'**
  String get carrRidersReasonPolicyViolation;

  /// No description provided for @carrRidersReasonPartnerRequest.
  ///
  /// In en, this message translates to:
  /// **'Partner request'**
  String get carrRidersReasonPartnerRequest;

  /// No description provided for @carrRidersReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get carrRidersReasonOther;

  /// No description provided for @carrRidersProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider HR Profile'**
  String get carrRidersProfileTitle;

  /// No description provided for @carrRidersProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Documents, employment details and performance'**
  String get carrRidersProfileSubtitle;

  /// No description provided for @carrRidersBackToDirectory.
  ///
  /// In en, this message translates to:
  /// **'Back to riders'**
  String get carrRidersBackToDirectory;

  /// No description provided for @carrRidersBadgeId.
  ///
  /// In en, this message translates to:
  /// **'Badge ID: {code}'**
  String carrRidersBadgeId(String code);

  /// No description provided for @carrRidersPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get carrRidersPhone;

  /// No description provided for @carrRidersEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get carrRidersEmail;

  /// No description provided for @carrRidersLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get carrRidersLastSeen;

  /// No description provided for @carrRidersNoPresenceYet.
  ///
  /// In en, this message translates to:
  /// **'No duty or location yet'**
  String get carrRidersNoPresenceYet;

  /// No description provided for @carrRidersStaleNote.
  ///
  /// In en, this message translates to:
  /// **'Declared on duty, but the last location is too old to dispatch on.'**
  String get carrRidersStaleNote;

  /// No description provided for @carrRidersNoApplication.
  ///
  /// In en, this message translates to:
  /// **'The platform attached this rider directly, so there is no application on file — no name, contact details or documents to show.'**
  String get carrRidersNoApplication;

  /// No description provided for @carrRidersDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents Verification'**
  String get carrRidersDocumentsTitle;

  /// No description provided for @carrRidersDocNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get carrRidersDocNationalId;

  /// No description provided for @carrRidersDocDrivingLicence.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get carrRidersDocDrivingLicence;

  /// No description provided for @carrRidersDocVehicleRegistration.
  ///
  /// In en, this message translates to:
  /// **'Vehicle registration'**
  String get carrRidersDocVehicleRegistration;

  /// No description provided for @carrRidersDocVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get carrRidersDocVerified;

  /// No description provided for @carrRidersDocWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get carrRidersDocWaiting;

  /// No description provided for @carrRidersDocRefused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get carrRidersDocRefused;

  /// No description provided for @carrRidersDocNotUploaded.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get carrRidersDocNotUploaded;

  /// No description provided for @carrRidersDocOpen.
  ///
  /// In en, this message translates to:
  /// **'Open the document'**
  String get carrRidersDocOpen;

  /// No description provided for @carrRidersCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not be read just now.'**
  String get carrRidersCouldNotRead;

  /// No description provided for @carrRidersAvgRating.
  ///
  /// In en, this message translates to:
  /// **'Avg rating'**
  String get carrRidersAvgRating;

  /// No description provided for @carrRidersHappyCustomers.
  ///
  /// In en, this message translates to:
  /// **'{percent}% happy customers'**
  String carrRidersHappyCustomers(int percent);

  /// No description provided for @carrRidersNoRatingsYet.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get carrRidersNoRatingsYet;

  /// No description provided for @carrRidersDeliveriesWindow.
  ///
  /// In en, this message translates to:
  /// **'Deliveries, last {days} days'**
  String carrRidersDeliveriesWindow(int days);

  /// No description provided for @carrRidersClaimedCaption.
  ///
  /// In en, this message translates to:
  /// **'{claimed} claimed, {cancelled} cancelled after claiming'**
  String carrRidersClaimedCaption(int claimed, int cancelled);

  /// No description provided for @carrRidersCompletionRate.
  ///
  /// In en, this message translates to:
  /// **'Completion rate'**
  String get carrRidersCompletionRate;

  /// No description provided for @carrRidersCompletionCaption.
  ///
  /// In en, this message translates to:
  /// **'Delivered out of claimed, for your company'**
  String get carrRidersCompletionCaption;

  /// No description provided for @carrRidersNothingClaimed.
  ///
  /// In en, this message translates to:
  /// **'Nothing claimed in this window'**
  String get carrRidersNothingClaimed;

  /// No description provided for @carrRidersDeliveredTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivered today'**
  String get carrRidersDeliveredTodayLabel;

  /// No description provided for @carrRidersDeliveredTodayCaption.
  ///
  /// In en, this message translates to:
  /// **'For your company, since midnight'**
  String get carrRidersDeliveredTodayCaption;

  /// No description provided for @carrRidersOutputTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery output, last {days} days'**
  String carrRidersOutputTitle(int days);

  /// No description provided for @carrRidersOutputEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deliveries in this period'**
  String get carrRidersOutputEmpty;

  /// No description provided for @carrRidersOutputNote.
  ///
  /// In en, this message translates to:
  /// **'Days are split in the {zone} time zone, and only deliveries made for your company are counted.'**
  String carrRidersOutputNote(String zone);

  /// No description provided for @carrRidersHoursTitle.
  ///
  /// In en, this message translates to:
  /// **'Hours online, last {days} days'**
  String carrRidersHoursTitle(int days);

  /// No description provided for @carrRidersHoursValue.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String carrRidersHoursValue(String hours);

  /// No description provided for @carrRidersHoursTotal.
  ///
  /// In en, this message translates to:
  /// **'{hours} h in total'**
  String carrRidersHoursTotal(String hours);

  /// No description provided for @carrRidersShifts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shift} other{{count} shifts}}'**
  String carrRidersShifts(int count);

  /// No description provided for @carrRidersHoursNone.
  ///
  /// In en, this message translates to:
  /// **'No hours online to show for your company.'**
  String get carrRidersHoursNone;

  /// No description provided for @carrRidersHoursZone.
  ///
  /// In en, this message translates to:
  /// **'Days are split in the {zone} time zone, as the server reports them.'**
  String carrRidersHoursZone(String zone);

  /// No description provided for @carrRidersEmploymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Employment Details'**
  String get carrRidersEmploymentTitle;

  /// No description provided for @carrRidersStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get carrRidersStartDate;

  /// No description provided for @carrRidersApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get carrRidersApplied;

  /// No description provided for @carrRidersRegion.
  ///
  /// In en, this message translates to:
  /// **'Region (from their application)'**
  String get carrRidersRegion;

  /// No description provided for @carrRidersVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get carrRidersVehicle;

  /// No description provided for @carrRidersEmploymentNote.
  ///
  /// In en, this message translates to:
  /// **'Contract type, pay rate and zone assignment are not recorded on this platform.'**
  String get carrRidersEmploymentNote;

  /// No description provided for @carrRidersSuspendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Suspending works through a rider\'s application to you. The platform attached this rider directly, so ask YouDrop to suspend them.'**
  String get carrRidersSuspendUnavailable;

  /// No description provided for @carrRidersTerminate.
  ///
  /// In en, this message translates to:
  /// **'Terminate Contract'**
  String get carrRidersTerminate;

  /// No description provided for @carrRidersTerminateTitle.
  ///
  /// In en, this message translates to:
  /// **'End {name}\'s contract?'**
  String carrRidersTerminateTitle(String name);

  /// No description provided for @carrRidersTerminateBody.
  ///
  /// In en, this message translates to:
  /// **'{name} comes off your fleet straight away and is offered none of your work. They keep their YouDrop sign-in and their history, but they do not become one of YouDrop\'s own riders: they can take no work at all until another company hires them or YouDrop takes them on.'**
  String carrRidersTerminateBody(String name);

  /// No description provided for @carrRidersTerminateJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs in flight: while they are carrying a job for you, this is refused until that job is delivered or cancelled. Nothing they are carrying is dropped or handed to somebody else.'**
  String get carrRidersTerminateJobs;

  /// No description provided for @carrRidersTerminateMoney.
  ///
  /// In en, this message translates to:
  /// **'Collect any door cash they are holding for you first. Ending the contract settles nothing: what they have earned and collected stays on record exactly as it is.'**
  String get carrRidersTerminateMoney;

  /// No description provided for @carrRidersTerminateUndo.
  ///
  /// In en, this message translates to:
  /// **'Taking them back later means hiring them again.'**
  String get carrRidersTerminateUndo;

  /// No description provided for @carrRidersTerminateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Terminate contract'**
  String get carrRidersTerminateConfirm;

  /// No description provided for @carrRidersTerminated.
  ///
  /// In en, this message translates to:
  /// **'{name} is no longer on your fleet.'**
  String carrRidersTerminated(String name);

  /// No description provided for @carrRidersTerminateCarrying.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{They are carrying one of your jobs right now. Their contract can end once it is delivered or cancelled.} other{They are carrying {count} of your jobs right now. Their contract can end once those are delivered or cancelled.}}'**
  String carrRidersTerminateCarrying(int count);

  /// No description provided for @carrRidersNotOnFleet.
  ///
  /// In en, this message translates to:
  /// **'This rider is no longer on your fleet.'**
  String get carrRidersNotOnFleet;

  /// No description provided for @carrRidersNoPresenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more has no duty or location yet} other{{count} more have no duty or location yet}}'**
  String carrRidersNoPresenceCount(int count);

  /// No description provided for @carrRidersNoPresenceNote.
  ///
  /// In en, this message translates to:
  /// **'Their duty and location show here once YouDrop links them to your fleet — at the latest after their first delivery for you. Until then this page cannot tell whether they are on duty.'**
  String get carrRidersNoPresenceNote;

  /// No description provided for @carrRidersVehicleModel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle model'**
  String get carrRidersVehicleModel;

  /// No description provided for @carrRidersPlateNumber.
  ///
  /// In en, this message translates to:
  /// **'Plate number'**
  String get carrRidersPlateNumber;

  /// No description provided for @carrRidersDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get carrRidersDateOfBirth;

  /// No description provided for @carrRidersNationalIdNumber.
  ///
  /// In en, this message translates to:
  /// **'National ID number'**
  String get carrRidersNationalIdNumber;

  /// No description provided for @carrRidersDutyChanged.
  ///
  /// In en, this message translates to:
  /// **'Duty last changed'**
  String get carrRidersDutyChanged;

  /// No description provided for @carrRidersVehicleYear.
  ///
  /// In en, this message translates to:
  /// **'Vehicle year'**
  String get carrRidersVehicleYear;

  /// No description provided for @carrRidersTerminateReason.
  ///
  /// In en, this message translates to:
  /// **'Reason, kept on record'**
  String get carrRidersTerminateReason;

  /// No description provided for @carrRidersTerminateReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why is this contract ending?'**
  String get carrRidersTerminateReasonHint;

  /// No description provided for @carrRidersStatusStandingUnknown.
  ///
  /// In en, this message translates to:
  /// **'Standing unknown'**
  String get carrRidersStatusStandingUnknown;

  /// No description provided for @carrRidersStandingUnknownNote.
  ///
  /// In en, this message translates to:
  /// **'Whether this rider is suspended could not be read just now, so suspending and reinstating are not offered. Reload the page to try again.'**
  String get carrRidersStandingUnknownNote;

  /// No description provided for @attendanceBackToProfile.
  ///
  /// In en, this message translates to:
  /// **'Back to profile'**
  String get attendanceBackToProfile;

  /// No description provided for @blitzTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant Blitz'**
  String get blitzTitle;

  /// No description provided for @blitzSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your catalogue from shelf photos'**
  String get blitzSubtitle;

  /// No description provided for @blitzFastSetup.
  ///
  /// In en, this message translates to:
  /// **'Fast setup'**
  String get blitzFastSetup;

  /// No description provided for @blitzStepScan.
  ///
  /// In en, this message translates to:
  /// **'Scan shop'**
  String get blitzStepScan;

  /// No description provided for @blitzStepCheck.
  ///
  /// In en, this message translates to:
  /// **'Check items'**
  String get blitzStepCheck;

  /// No description provided for @blitzStepSave.
  ///
  /// In en, this message translates to:
  /// **'Save drafts'**
  String get blitzStepSave;

  /// No description provided for @blitzStepDone.
  ///
  /// In en, this message translates to:
  /// **'{step}, done'**
  String blitzStepDone(String step);

  /// No description provided for @blitzStepCurrent.
  ///
  /// In en, this message translates to:
  /// **'{step}, current step'**
  String blitzStepCurrent(String step);

  /// No description provided for @blitzIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Photograph your shelves, skip the typing'**
  String get blitzIntroTitle;

  /// No description provided for @blitzIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of each shelf. We read the product names and sizes and suggest a section and a price, and you check every item before anything is saved.'**
  String get blitzIntroBody;

  /// No description provided for @blitzTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get blitzTakePhoto;

  /// No description provided for @blitzChoosePhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose photos'**
  String get blitzChoosePhotos;

  /// No description provided for @blitzPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'Photos: {count} of {max}'**
  String blitzPhotoCount(int count, int max);

  /// No description provided for @blitzPhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Shelf photo {number}'**
  String blitzPhotoLabel(int number);

  /// No description provided for @blitzUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo {current} of {total}…'**
  String blitzUploading(int current, int total);

  /// No description provided for @blitzScanPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Scan 1 photo} other{Scan {count} photos}}'**
  String blitzScanPhotos(int count);

  /// No description provided for @blitzAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Reading your shelves…'**
  String get blitzAnalyzing;

  /// No description provided for @blitzAnalyzingHint.
  ///
  /// In en, this message translates to:
  /// **'This can take a minute or two. Keep this screen open.'**
  String get blitzAnalyzingHint;

  /// No description provided for @blitzScanComplete.
  ///
  /// In en, this message translates to:
  /// **'Scan complete'**
  String get blitzScanComplete;

  /// No description provided for @blitzItemsFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String blitzItemsFound(int count);

  /// No description provided for @blitzSampleTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample items'**
  String get blitzSampleTitle;

  /// No description provided for @blitzSampleBody.
  ///
  /// In en, this message translates to:
  /// **'The photo reader isn\'t switched on yet, so these are example items, not what\'s on your shelves. Skip any you don\'t sell.'**
  String get blitzSampleBody;

  /// No description provided for @blitzNoneFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t recognise any products in these photos.'**
  String get blitzNoneFound;

  /// No description provided for @blitzNoneFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Try closer photos with the labels facing the camera.'**
  String get blitzNoneFoundHint;

  /// No description provided for @blitzNewScan.
  ///
  /// In en, this message translates to:
  /// **'Start a new scan'**
  String get blitzNewScan;

  /// No description provided for @blitzReviewCta.
  ///
  /// In en, this message translates to:
  /// **'Review and save as drafts'**
  String get blitzReviewCta;

  /// No description provided for @blitzFooter.
  ///
  /// In en, this message translates to:
  /// **'Nothing reaches customers until you publish it.'**
  String get blitzFooter;

  /// No description provided for @blitzScansLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No scans left today} =1{1 scan left today} other{{count} scans left today}}'**
  String blitzScansLeft(int count);

  /// No description provided for @blitzQuotaReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s {limit} scans. Try again tomorrow.'**
  String blitzQuotaReached(int limit);

  /// No description provided for @blitzFailedRefused.
  ///
  /// In en, this message translates to:
  /// **'These photos couldn\'t be read. Try clear photos of your shop\'s shelves.'**
  String get blitzFailedRefused;

  /// No description provided for @blitzFailedUnreadable.
  ///
  /// In en, this message translates to:
  /// **'One of the photos couldn\'t be opened. Try taking it again.'**
  String get blitzFailedUnreadable;

  /// No description provided for @blitzFailedProvider.
  ///
  /// In en, this message translates to:
  /// **'The photo reader didn\'t answer.'**
  String get blitzFailedProvider;

  /// No description provided for @blitzFailedBusy.
  ///
  /// In en, this message translates to:
  /// **'Many shops are scanning right now. Try again in a minute.'**
  String get blitzFailedBusy;

  /// No description provided for @blitzFailedInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The scan was interrupted before it finished.'**
  String get blitzFailedInterrupted;

  /// No description provided for @blitzFailedOther.
  ///
  /// In en, this message translates to:
  /// **'The scan didn\'t finish.'**
  String get blitzFailedOther;

  /// No description provided for @blitzNoRetriesLeft.
  ///
  /// In en, this message translates to:
  /// **'This scan can\'t be tried again. Start a new one.'**
  String get blitzNoRetriesLeft;

  /// No description provided for @blitzCameraFailed.
  ///
  /// In en, this message translates to:
  /// **'The camera didn\'t open. Choose a photo instead.'**
  String get blitzCameraFailed;

  /// No description provided for @blitzUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'A photo didn\'t upload. Check your connection and try again.'**
  String get blitzUploadFailed;

  /// No description provided for @blitzCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'The scan couldn\'t start.'**
  String get blitzCouldNotStart;

  /// No description provided for @blitzConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check on the scan. Check your connection.'**
  String get blitzConnectionLost;

  /// No description provided for @blitzTag.
  ///
  /// In en, this message translates to:
  /// **'{name} · about {price}'**
  String blitzTag(String name, String price);

  /// No description provided for @blitzReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check items'**
  String get blitzReviewTitle;

  /// No description provided for @blitzReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What you keep is saved as a draft'**
  String get blitzReviewSubtitle;

  /// No description provided for @blitzKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get blitzKeep;

  /// No description provided for @blitzKeepItem.
  ///
  /// In en, this message translates to:
  /// **'Keep {name}'**
  String blitzKeepItem(String name);

  /// No description provided for @blitzName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get blitzName;

  /// No description provided for @blitzPriceUsd.
  ///
  /// In en, this message translates to:
  /// **'Price (USD)'**
  String get blitzPriceUsd;

  /// No description provided for @blitzSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get blitzSection;

  /// No description provided for @blitzNoSection.
  ///
  /// In en, this message translates to:
  /// **'No section'**
  String get blitzNoSection;

  /// No description provided for @blitzGuess.
  ///
  /// In en, this message translates to:
  /// **'Guess: {price}'**
  String blitzGuess(String price);

  /// No description provided for @blitzUseGuess.
  ///
  /// In en, this message translates to:
  /// **'Use this price'**
  String get blitzUseGuess;

  /// No description provided for @blitzCheckThis.
  ///
  /// In en, this message translates to:
  /// **'Not sure of this one — check it'**
  String get blitzCheckThis;

  /// No description provided for @blitzNeedName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get blitzNeedName;

  /// No description provided for @blitzNeedPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a price above 0'**
  String get blitzNeedPrice;

  /// No description provided for @blitzPriceDecimals.
  ///
  /// In en, this message translates to:
  /// **'Use at most two decimals'**
  String get blitzPriceDecimals;

  /// No description provided for @blitzSaveDrafts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing to save} =1{Save 1 draft} other{Save {count} drafts}}'**
  String blitzSaveDrafts(int count);

  /// No description provided for @blitzSkipAll.
  ///
  /// In en, this message translates to:
  /// **'Skip all items'**
  String get blitzSkipAll;

  /// No description provided for @blitzFixItems.
  ///
  /// In en, this message translates to:
  /// **'Fix the marked items first.'**
  String get blitzFixItems;

  /// No description provided for @blitzSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved as drafts'**
  String get blitzSavedTitle;

  /// No description provided for @blitzSavedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No products were added.} =1{1 product was added to your catalogue as a draft.} other{{count} products were added to your catalogue as drafts.}}'**
  String blitzSavedCount(int count);

  /// No description provided for @blitzSavedHint.
  ///
  /// In en, this message translates to:
  /// **'Drafts stay hidden from customers. Add a photo to each one, then publish it from Inventory.'**
  String get blitzSavedHint;

  /// No description provided for @blitzDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get blitzDone;

  /// No description provided for @blitzAlreadySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get blitzAlreadySaved;

  /// No description provided for @blitzTooManyPhotos.
  ///
  /// In en, this message translates to:
  /// **'A scan takes {max} photos at most, so the extra ones weren\'t added.'**
  String blitzTooManyPhotos(int max);

  /// No description provided for @blitzSectionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sections couldn\'t load, so each item keeps the section we suggested.'**
  String get blitzSectionsUnavailable;

  /// No description provided for @blitzEntryAction.
  ///
  /// In en, this message translates to:
  /// **'Scan shelves'**
  String get blitzEntryAction;

  /// No description provided for @blitzSettingsRow.
  ///
  /// In en, this message translates to:
  /// **'Build catalogue from photos'**
  String get blitzSettingsRow;

  /// No description provided for @blitzSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Check your connection and try again.'**
  String get blitzSaveFailed;

  /// No description provided for @blitzSavedEarlier.
  ///
  /// In en, this message translates to:
  /// **'These items had already been saved.'**
  String get blitzSavedEarlier;

  /// No description provided for @blitzListChanged.
  ///
  /// In en, this message translates to:
  /// **'Some items were already decided elsewhere, so they\'ve left the list. Check the rest and save again.'**
  String get blitzListChanged;

  /// No description provided for @giftHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a Gift'**
  String get giftHubTitle;

  /// No description provided for @giftHubBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Remittance Made Real'**
  String get giftHubBannerTitle;

  /// No description provided for @giftHubBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Support your loved ones in Lebanon. Choose real essentials, groceries or hot meals, delivered to their door — often the same day.'**
  String get giftHubBannerBody;

  /// No description provided for @giftHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get giftHowItWorks;

  /// No description provided for @giftStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Choose from local shops'**
  String get giftStep1Title;

  /// No description provided for @giftStep1Body.
  ///
  /// In en, this message translates to:
  /// **'Pick groceries, sweets, pharmacy items or a ready-made care bundle.'**
  String get giftStep1Body;

  /// No description provided for @giftStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Enter their address in Lebanon'**
  String get giftStep2Title;

  /// No description provided for @giftStep2Body.
  ///
  /// In en, this message translates to:
  /// **'We deliver wherever the shop you choose delivers.'**
  String get giftStep2Body;

  /// No description provided for @giftStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Same-day delivery'**
  String get giftStep3Title;

  /// No description provided for @giftStep3Body.
  ///
  /// In en, this message translates to:
  /// **'A rider hands it over with your personal note — the same day, while the shop is open.'**
  String get giftStep3Body;

  /// No description provided for @giftCategories.
  ///
  /// In en, this message translates to:
  /// **'Gift categories'**
  String get giftCategories;

  /// No description provided for @giftCatCarePackage.
  ///
  /// In en, this message translates to:
  /// **'Care Package'**
  String get giftCatCarePackage;

  /// No description provided for @giftCatGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get giftCatGroceries;

  /// No description provided for @giftCatMedicine.
  ///
  /// In en, this message translates to:
  /// **'Medicine & Health'**
  String get giftCatMedicine;

  /// No description provided for @giftRecentRecipients.
  ///
  /// In en, this message translates to:
  /// **'Recent recipients'**
  String get giftRecentRecipients;

  /// No description provided for @giftAddRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add a recipient'**
  String get giftAddRecipient;

  /// No description provided for @giftFeaturedBundles.
  ///
  /// In en, this message translates to:
  /// **'Featured care bundles'**
  String get giftFeaturedBundles;

  /// No description provided for @giftSameDayDeliverable.
  ///
  /// In en, this message translates to:
  /// **'Same-day deliverable'**
  String get giftSameDayDeliverable;

  /// No description provided for @giftHomeEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a gift to Lebanon'**
  String get giftHomeEntryTitle;

  /// No description provided for @giftHomeEntrySub.
  ///
  /// In en, this message translates to:
  /// **'Groceries, sweets and care bundles for family, delivered to their door'**
  String get giftHomeEntrySub;

  /// No description provided for @giftDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift Details'**
  String get giftDetailsTitle;

  /// No description provided for @giftCheckoutSub.
  ///
  /// In en, this message translates to:
  /// **'Diaspora Checkout'**
  String get giftCheckoutSub;

  /// No description provided for @giftRecipientInfo.
  ///
  /// In en, this message translates to:
  /// **'Recipient information'**
  String get giftRecipientInfo;

  /// No description provided for @giftRecipientName.
  ///
  /// In en, this message translates to:
  /// **'Recipient name'**
  String get giftRecipientName;

  /// No description provided for @giftRecipientNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Who is receiving it?'**
  String get giftRecipientNameRequired;

  /// No description provided for @giftRecipientPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number (Lebanon)'**
  String get giftRecipientPhone;

  /// No description provided for @giftPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a Lebanese number, e.g. 71 234 567'**
  String get giftPhoneInvalid;

  /// No description provided for @giftDeliveryDate.
  ///
  /// In en, this message translates to:
  /// **'Delivery date'**
  String get giftDeliveryDate;

  /// No description provided for @giftNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach a personal note'**
  String get giftNoteTitle;

  /// No description provided for @giftNoteHelper.
  ///
  /// In en, this message translates to:
  /// **'The shop sends your note with the gift.'**
  String get giftNoteHelper;

  /// No description provided for @giftWrapTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium gift wrapping'**
  String get giftWrapTitle;

  /// No description provided for @giftWrapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Festive wrapping, with your note on a card (+{amount})'**
  String giftWrapSubtitle(String amount);

  /// No description provided for @giftPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get giftPaymentTitle;

  /// No description provided for @giftCashNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Gifts are paid online — the person receiving it is never asked to pay.'**
  String get giftCashNotAllowed;

  /// No description provided for @giftNoPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Gifts are paid online, and online payment isn\'t switched on yet — so a gift can\'t be sent right now.'**
  String get giftNoPaymentMethods;

  /// No description provided for @giftTermsFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the gift\'s payment options.'**
  String get giftTermsFailed;

  /// No description provided for @giftOfflineCannotWait.
  ///
  /// In en, this message translates to:
  /// **'A gift can\'t wait for the connection the way a cash order can — it\'s paid online. Send it once you\'re back online.'**
  String get giftOfflineCannotWait;

  /// No description provided for @giftOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order summary'**
  String get giftOrderSummary;

  /// No description provided for @giftLineQty.
  ///
  /// In en, this message translates to:
  /// **'{qty}× {name}'**
  String giftLineQty(int qty, String name);

  /// No description provided for @giftWrapLine.
  ///
  /// In en, this message translates to:
  /// **'Gift wrapping'**
  String get giftWrapLine;

  /// No description provided for @giftDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get giftDeliveryFee;

  /// No description provided for @giftTotalUsd.
  ///
  /// In en, this message translates to:
  /// **'Total USD'**
  String get giftTotalUsd;

  /// No description provided for @giftApproxLbp.
  ///
  /// In en, this message translates to:
  /// **'≈ {amount}'**
  String giftApproxLbp(String amount);

  /// No description provided for @giftTotalConfirmed.
  ///
  /// In en, this message translates to:
  /// **'The final total is confirmed when your gift is placed.'**
  String get giftTotalConfirmed;

  /// No description provided for @giftSendAndPay.
  ///
  /// In en, this message translates to:
  /// **'Send Gift & Pay'**
  String get giftSendAndPay;

  /// No description provided for @giftForName.
  ///
  /// In en, this message translates to:
  /// **'Gift for {name}'**
  String giftForName(String name);

  /// No description provided for @giftWrapRequested.
  ///
  /// In en, this message translates to:
  /// **'Gift wrapping requested'**
  String get giftWrapRequested;

  /// No description provided for @giftCardMessage.
  ///
  /// In en, this message translates to:
  /// **'Card message'**
  String get giftCardMessage;

  /// No description provided for @giftRecipientPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient\'s phone'**
  String get giftRecipientPhoneLabel;

  /// No description provided for @giftBasketBanner.
  ///
  /// In en, this message translates to:
  /// **'Sending this basket as a gift'**
  String get giftBasketBanner;

  /// No description provided for @giftBasketNotGift.
  ///
  /// In en, this message translates to:
  /// **'Not a gift'**
  String get giftBasketNotGift;

  /// No description provided for @giftDeliveredToday.
  ///
  /// In en, this message translates to:
  /// **'Today, while the shop is open'**
  String get giftDeliveredToday;

  /// No description provided for @giftNoteLength.
  ///
  /// In en, this message translates to:
  /// **'{used}/{max}'**
  String giftNoteLength(int used, int max);

  /// No description provided for @giftUnnamed.
  ///
  /// In en, this message translates to:
  /// **'A gift — who it\'s for shows once it\'s yours to carry'**
  String get giftUnnamed;

  /// No description provided for @heatmapTitle.
  ///
  /// In en, this message translates to:
  /// **'Demand Radar'**
  String get heatmapTitle;

  /// No description provided for @heatmapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time neighborhood pulses'**
  String get heatmapSubtitle;

  /// No description provided for @heatmapActiveOrderDensities.
  ///
  /// In en, this message translates to:
  /// **'Active Order Densities'**
  String get heatmapActiveOrderDensities;

  /// No description provided for @heatmapLiveSyncing.
  ///
  /// In en, this message translates to:
  /// **'Live Syncing'**
  String get heatmapLiveSyncing;

  /// No description provided for @heatmapCantRefresh.
  ///
  /// In en, this message translates to:
  /// **'Can\'t refresh right now'**
  String get heatmapCantRefresh;

  /// No description provided for @heatmapLevelHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get heatmapLevelHigh;

  /// No description provided for @heatmapLevelMedium.
  ///
  /// In en, this message translates to:
  /// **'Med'**
  String get heatmapLevelMedium;

  /// No description provided for @heatmapLevelLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get heatmapLevelLow;

  /// A map label: an area name and how busy it is, e.g. "Hamra (High)".
  ///
  /// In en, this message translates to:
  /// **'{zone} ({level})'**
  String heatmapZoneWithLevel(String zone, String level);

  /// No description provided for @heatmapWindowHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get heatmapWindowHour;

  /// No description provided for @heatmapWindowDay.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get heatmapWindowDay;

  /// No description provided for @heatmapWindowWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get heatmapWindowWeek;

  /// No description provided for @heatmapAreasTitle.
  ///
  /// In en, this message translates to:
  /// **'Areas around your shop'**
  String get heatmapAreasTitle;

  /// No description provided for @heatmapNotOnMap.
  ///
  /// In en, this message translates to:
  /// **'Not on the map yet'**
  String get heatmapNotOnMap;

  /// No description provided for @heatmapNoneOnMap.
  ///
  /// In en, this message translates to:
  /// **'These areas aren\'t on the map yet'**
  String get heatmapNoneOnMap;

  /// No description provided for @heatmapMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The map can\'t load right now'**
  String get heatmapMapUnavailable;

  /// No description provided for @heatmapNoAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'We don\'t know your neighbourhood yet'**
  String get heatmapNoAreaTitle;

  /// No description provided for @heatmapNoAreaMessage.
  ///
  /// In en, this message translates to:
  /// **'Demand shows for the mapped areas near your shop\'s pin. Drop your pin if you haven\'t yet, and nearby areas will appear here once they\'re on the map.'**
  String get heatmapNoAreaMessage;

  /// No description provided for @heatmapNotEnoughTitle.
  ///
  /// In en, this message translates to:
  /// **'Not enough orders nearby yet'**
  String get heatmapNotEnoughTitle;

  /// The privacy floor: how many different customers an area needs before it is shown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{An area appears once {count} different customers have ordered there in this period, so no single customer can be picked out.}}'**
  String heatmapNotEnoughMessage(int count);

  /// No description provided for @heatmapCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load demand right now'**
  String get heatmapCouldNotLoad;

  /// No description provided for @heatmapNoShopMessage.
  ///
  /// In en, this message translates to:
  /// **'Demand around your shop shows here once your shop is set up.'**
  String get heatmapNoShopMessage;

  /// No description provided for @heatmapEntryBlurb.
  ///
  /// In en, this message translates to:
  /// **'See which neighbourhoods around your shop are ordering'**
  String get heatmapEntryBlurb;

  /// No description provided for @heatmapZoneCentreLatitude.
  ///
  /// In en, this message translates to:
  /// **'Centre latitude (optional)'**
  String get heatmapZoneCentreLatitude;

  /// No description provided for @heatmapZoneCentreLongitude.
  ///
  /// In en, this message translates to:
  /// **'Centre longitude (optional)'**
  String get heatmapZoneCentreLongitude;

  /// No description provided for @heatmapZoneCentreHelp.
  ///
  /// In en, this message translates to:
  /// **'Roughly the middle of the area. It places the area on merchants\' demand map; pricing never uses it.'**
  String get heatmapZoneCentreHelp;

  /// No description provided for @heatmapZoneCentreBoth.
  ///
  /// In en, this message translates to:
  /// **'Enter both, or leave both empty'**
  String get heatmapZoneCentreBoth;

  /// No description provided for @heatmapZoneCentreLatRange.
  ///
  /// In en, this message translates to:
  /// **'A latitude between -90 and 90'**
  String get heatmapZoneCentreLatRange;

  /// No description provided for @heatmapZoneCentreLngRange.
  ///
  /// In en, this message translates to:
  /// **'A longitude between -180 and 180'**
  String get heatmapZoneCentreLngRange;

  /// No description provided for @heatmapZoneOnMap.
  ///
  /// In en, this message translates to:
  /// **'On the demand map'**
  String get heatmapZoneOnMap;

  /// No description provided for @heatmapZoneNotOnMap.
  ///
  /// In en, this message translates to:
  /// **'Not on the demand map'**
  String get heatmapZoneNotOnMap;

  /// No description provided for @heatmapSubtitleDay.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood pulses over the last 24 hours'**
  String get heatmapSubtitleDay;

  /// No description provided for @heatmapSubtitleWeek.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood pulses over the last 7 days'**
  String get heatmapSubtitleWeek;

  /// No description provided for @heatmapUpdatedHourly.
  ///
  /// In en, this message translates to:
  /// **'Updated every hour'**
  String get heatmapUpdatedHourly;

  /// No description provided for @heatmapUpdatedDaily.
  ///
  /// In en, this message translates to:
  /// **'Updated once a day'**
  String get heatmapUpdatedDaily;

  /// No description provided for @heatmapLegendRelative.
  ///
  /// In en, this message translates to:
  /// **'Compared with the busiest area around you'**
  String get heatmapLegendRelative;

  /// No description provided for @heatmapNotLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shop isn\'t live yet'**
  String get heatmapNotLiveTitle;

  /// No description provided for @heatmapNotLiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Demand around your shop shows here once your shop is published.'**
  String get heatmapNotLiveMessage;

  /// No description provided for @payrollNavLabel.
  ///
  /// In en, this message translates to:
  /// **'Payroll'**
  String get payrollNavLabel;

  /// No description provided for @payrollTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider Payroll & Earnings Management'**
  String get payrollTitle;

  /// No description provided for @payrollSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approve payouts, calculate bonuses, and track payouts history'**
  String get payrollSubtitle;

  /// No description provided for @payrollPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Pay Period: {from} – {to}'**
  String payrollPeriodLabel(String from, String to);

  /// No description provided for @payrollPeriodTooltip.
  ///
  /// In en, this message translates to:
  /// **'Choose a pay period'**
  String get payrollPeriodTooltip;

  /// No description provided for @payrollPeriodOption.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to} · {state}'**
  String payrollPeriodOption(String from, String to, String state);

  /// No description provided for @payrollRulesButton.
  ///
  /// In en, this message translates to:
  /// **'Pay rules'**
  String get payrollRulesButton;

  /// No description provided for @payrollExport.
  ///
  /// In en, this message translates to:
  /// **'Export Payslips'**
  String get payrollExport;

  /// No description provided for @payrollExported.
  ///
  /// In en, this message translates to:
  /// **'Saved {file}.'**
  String payrollExported(String file);

  /// No description provided for @payrollStart.
  ///
  /// In en, this message translates to:
  /// **'Start pay run'**
  String get payrollStart;

  /// No description provided for @payrollRecompute.
  ///
  /// In en, this message translates to:
  /// **'Recompute'**
  String get payrollRecompute;

  /// No description provided for @payrollApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve pay run'**
  String get payrollApprove;

  /// No description provided for @payrollPayAll.
  ///
  /// In en, this message translates to:
  /// **'Record All Payments'**
  String get payrollPayAll;

  /// No description provided for @payrollDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get payrollDiscard;

  /// No description provided for @payrollKpiPool.
  ///
  /// In en, this message translates to:
  /// **'Total Payroll Pool'**
  String get payrollKpiPool;

  /// No description provided for @payrollKpiPoolNote.
  ///
  /// In en, this message translates to:
  /// **'To pay for {from} – {to}'**
  String payrollKpiPoolNote(String from, String to);

  /// No description provided for @payrollKpiRiders.
  ///
  /// In en, this message translates to:
  /// **'Riders on Payroll'**
  String get payrollKpiRiders;

  /// No description provided for @payrollKpiRidersValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No riders} =1{1 Rider} other{{count} Riders}}'**
  String payrollKpiRidersValue(int count);

  /// No description provided for @payrollKpiRidersNote.
  ///
  /// In en, this message translates to:
  /// **'With a payslip this period'**
  String get payrollKpiRidersNote;

  /// No description provided for @payrollKpiAverage.
  ///
  /// In en, this message translates to:
  /// **'Average Rider Earnings'**
  String get payrollKpiAverage;

  /// No description provided for @payrollKpiAverageNote.
  ///
  /// In en, this message translates to:
  /// **'Per {days}-day period'**
  String payrollKpiAverageNote(int days);

  /// No description provided for @payrollKpiBonuses.
  ///
  /// In en, this message translates to:
  /// **'Bonuses'**
  String get payrollKpiBonuses;

  /// No description provided for @payrollKpiBonusesNote.
  ///
  /// In en, this message translates to:
  /// **'Named bonuses and corrections'**
  String get payrollKpiBonusesNote;

  /// No description provided for @payrollLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rider Payroll Ledger'**
  String get payrollLedgerTitle;

  /// No description provided for @payrollColRider.
  ///
  /// In en, this message translates to:
  /// **'Rider name'**
  String get payrollColRider;

  /// No description provided for @payrollColBase.
  ///
  /// In en, this message translates to:
  /// **'Base pay'**
  String get payrollColBase;

  /// No description provided for @payrollColDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery pay'**
  String get payrollColDelivery;

  /// No description provided for @payrollColTips.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get payrollColTips;

  /// No description provided for @payrollColDeductions.
  ///
  /// In en, this message translates to:
  /// **'Deductions'**
  String get payrollColDeductions;

  /// No description provided for @payrollColGross.
  ///
  /// In en, this message translates to:
  /// **'Gross pay'**
  String get payrollColGross;

  /// No description provided for @payrollColNet.
  ///
  /// In en, this message translates to:
  /// **'Net pay'**
  String get payrollColNet;

  /// No description provided for @payrollColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get payrollColStatus;

  /// No description provided for @payrollColActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get payrollColActions;

  /// No description provided for @payrollPayslip.
  ///
  /// In en, this message translates to:
  /// **'Payslip'**
  String get payrollPayslip;

  /// No description provided for @payrollTipsNote.
  ///
  /// In en, this message translates to:
  /// **'Tips are the rider\'s own money and never part of their pay.'**
  String get payrollTipsNote;

  /// No description provided for @payrollHoursUnknown.
  ///
  /// In en, this message translates to:
  /// **'Hours for this rider could not be read.'**
  String get payrollHoursUnknown;

  /// No description provided for @payrollNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody on your fleet has pay in this period.'**
  String get payrollNobody;

  /// No description provided for @payrollTableNote.
  ///
  /// In en, this message translates to:
  /// **'This is your company\'s payroll, worked out from your pay rules. YouDrop does not pay your riders.'**
  String get payrollTableNote;

  /// No description provided for @payrollStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get payrollStatusDraft;

  /// No description provided for @payrollStatusDue.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get payrollStatusDue;

  /// No description provided for @payrollStatusNothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing to pay'**
  String get payrollStatusNothingDue;

  /// No description provided for @payrollStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid ✓'**
  String get payrollStatusPaid;

  /// No description provided for @payrollStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get payrollStatusFailed;

  /// No description provided for @payrollRunApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get payrollRunApproved;

  /// No description provided for @payrollRunPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get payrollRunPaid;

  /// No description provided for @payrollNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get payrollNotStarted;

  /// No description provided for @payrollRunMeta.
  ///
  /// In en, this message translates to:
  /// **'{state} · figures computed {time}'**
  String payrollRunMeta(String state, String time);

  /// No description provided for @payrollRunRevision.
  ///
  /// In en, this message translates to:
  /// **'Draft, revision {revision}'**
  String payrollRunRevision(int revision);

  /// No description provided for @payrollHoursAsOf.
  ///
  /// In en, this message translates to:
  /// **'Hours as read on {time}'**
  String payrollHoursAsOf(String time);

  /// No description provided for @payrollNoRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your pay rules first'**
  String get payrollNoRulesTitle;

  /// No description provided for @payrollNoRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Payroll works out each rider\'s pay from your company\'s own rules: what a delivery pays, whether hours are paid, and any deductions. Nothing is assumed for you.'**
  String get payrollNoRulesBody;

  /// No description provided for @payrollNoRunTitle.
  ///
  /// In en, this message translates to:
  /// **'No pay run for this period yet'**
  String get payrollNoRunTitle;

  /// No description provided for @payrollNoRunBody.
  ///
  /// In en, this message translates to:
  /// **'Starting one computes a draft from the deliveries and hours on record. Nothing is final until you approve it.'**
  String get payrollNoRunBody;

  /// No description provided for @payrollPeriodOpen.
  ///
  /// In en, this message translates to:
  /// **'This period runs until {date}. It can be approved once it is over.'**
  String payrollPeriodOpen(String date);

  /// No description provided for @payrollHoursMissing.
  ///
  /// In en, this message translates to:
  /// **'Attendance hours could not be read, so these figures leave hours out.'**
  String get payrollHoursMissing;

  /// No description provided for @payrollHoursNotDeployed.
  ///
  /// In en, this message translates to:
  /// **'Attendance hours are not available on this platform yet, so these figures leave hours out.'**
  String get payrollHoursNotDeployed;

  /// No description provided for @payrollHoursNotRead.
  ///
  /// In en, this message translates to:
  /// **'Your pay rules now use hours. Recompute to read them.'**
  String get payrollHoursNotRead;

  /// No description provided for @payrollJobsLateDraft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivery reached the ledger after these figures were computed. Recompute to include it.} other{{count} deliveries reached the ledger after these figures were computed. Recompute to include them.}}'**
  String payrollJobsLateDraft(int count);

  /// No description provided for @payrollJobsLateApproved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivery of this period reached the ledger after it was approved. Add a correction for the rider concerned.} other{{count} deliveries of this period reached the ledger after it was approved. Add corrections for the riders concerned.}}'**
  String payrollJobsLateApproved(int count);

  /// No description provided for @payrollPeriodChanged.
  ///
  /// In en, this message translates to:
  /// **'Your pay rules now pay these days in a different period. Discard this draft and start that period.'**
  String get payrollPeriodChanged;

  /// No description provided for @payrollLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Payroll could not be loaded just now.'**
  String get payrollLoadFailed;

  /// No description provided for @payrollTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get payrollTryAgain;

  /// No description provided for @payrollPayslipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Payslip for {from} – {to}'**
  String payrollPayslipSubtitle(String from, String to);

  /// No description provided for @payrollSectionPay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get payrollSectionPay;

  /// No description provided for @payrollSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get payrollSectionSummary;

  /// No description provided for @payrollSectionAttendance.
  ///
  /// In en, this message translates to:
  /// **'Hours and attendance'**
  String get payrollSectionAttendance;

  /// No description provided for @payrollSectionPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payrollSectionPayment;

  /// No description provided for @payrollLineDeliveries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivery × {rate}} other{{count} deliveries × {rate}}}'**
  String payrollLineDeliveries(int count, String rate);

  /// No description provided for @payrollLineHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h recorded × {rate}'**
  String payrollLineHours(String hours, String rate);

  /// No description provided for @payrollLineOvertime.
  ///
  /// In en, this message translates to:
  /// **'{hours} h overtime × {rate}'**
  String payrollLineOvertime(String hours, String rate);

  /// No description provided for @payrollLineTyped.
  ///
  /// In en, this message translates to:
  /// **'{hours} h typed by the office × {rate}'**
  String payrollLineTyped(String hours, String rate);

  /// No description provided for @payrollLineTypedUnpaid.
  ///
  /// In en, this message translates to:
  /// **'{hours} h typed by the office, not paid under your rules'**
  String payrollLineTypedUnpaid(String hours);

  /// No description provided for @payrollLineLate.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 late day × {rate}} other{{days} late days × {rate}}}'**
  String payrollLineLate(int days, String rate);

  /// No description provided for @payrollLineAbsence.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 absence × {rate}} other{{days} absences × {rate}}}'**
  String payrollLineAbsence(int days, String rate);

  /// No description provided for @payrollLineCash.
  ///
  /// In en, this message translates to:
  /// **'Company cash the rider held, kept from pay'**
  String get payrollLineCash;

  /// No description provided for @payrollLineBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus: {label}'**
  String payrollLineBonus(String label);

  /// No description provided for @payrollLineDeduction.
  ///
  /// In en, this message translates to:
  /// **'Deduction: {label}'**
  String payrollLineDeduction(String label);

  /// No description provided for @payrollLineCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction: {label}'**
  String payrollLineCorrection(String label);

  /// No description provided for @payrollLineOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get payrollLineOther;

  /// No description provided for @payrollOwes.
  ///
  /// In en, this message translates to:
  /// **'Owes the company {amount}. Nothing is paid.'**
  String payrollOwes(String amount);

  /// No description provided for @payrollTipsInfo.
  ///
  /// In en, this message translates to:
  /// **'Tips {amount}: the rider\'s own money, not part of this pay.'**
  String payrollTipsInfo(String amount);

  /// No description provided for @payrollCashKept.
  ///
  /// In en, this message translates to:
  /// **'Holds {amount} of the company\'s cash collected by {date}, more than this pay covers. It stays for the hub to collect.'**
  String payrollCashKept(String amount, String date);

  /// No description provided for @payrollHoursFacts.
  ///
  /// In en, this message translates to:
  /// **'Recorded {recorded} h · typed {typed} h · overtime {overtime} h'**
  String payrollHoursFacts(String recorded, String typed, String overtime);

  /// No description provided for @payrollDaysFacts.
  ///
  /// In en, this message translates to:
  /// **'Late days {lates} · absences {absences}'**
  String payrollDaysFacts(int lates, int absences);

  /// No description provided for @payrollAddBonus.
  ///
  /// In en, this message translates to:
  /// **'Add bonus'**
  String get payrollAddBonus;

  /// No description provided for @payrollAddDeduction.
  ///
  /// In en, this message translates to:
  /// **'Add deduction'**
  String get payrollAddDeduction;

  /// No description provided for @payrollRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get payrollRemove;

  /// No description provided for @payrollMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get payrollMarkPaid;

  /// No description provided for @payrollMarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Mark failed'**
  String get payrollMarkFailed;

  /// No description provided for @payrollAddCorrection.
  ///
  /// In en, this message translates to:
  /// **'Add correction'**
  String get payrollAddCorrection;

  /// No description provided for @payrollPaidOn.
  ///
  /// In en, this message translates to:
  /// **'Paid on {date} · {method}'**
  String payrollPaidOn(String date, String method);

  /// No description provided for @payrollRecordedBy.
  ///
  /// In en, this message translates to:
  /// **'Recorded by {name}'**
  String payrollRecordedBy(String name);

  /// No description provided for @payrollFailedBecause.
  ///
  /// In en, this message translates to:
  /// **'Payment failed: {reason}'**
  String payrollFailedBecause(String reason);

  /// No description provided for @payrollCorrections.
  ///
  /// In en, this message translates to:
  /// **'Corrections'**
  String get payrollCorrections;

  /// No description provided for @payrollCorrectionWaiting.
  ///
  /// In en, this message translates to:
  /// **'Paid in the rider\'s next pay run'**
  String get payrollCorrectionWaiting;

  /// No description provided for @payrollCorrectionPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid in a later pay run'**
  String get payrollCorrectionPaid;

  /// No description provided for @payrollLineDialogBonus.
  ///
  /// In en, this message translates to:
  /// **'Add a bonus for {name}'**
  String payrollLineDialogBonus(String name);

  /// No description provided for @payrollLineDialogDeduction.
  ///
  /// In en, this message translates to:
  /// **'Add a deduction for {name}'**
  String payrollLineDialogDeduction(String name);

  /// No description provided for @payrollLabelField.
  ///
  /// In en, this message translates to:
  /// **'What it is for'**
  String get payrollLabelField;

  /// No description provided for @payrollAmountField.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get payrollAmountField;

  /// No description provided for @payrollAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'An amount to the cent, like 25.00'**
  String get payrollAmountInvalid;

  /// No description provided for @payrollRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get payrollRequired;

  /// No description provided for @payrollReasonField.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get payrollReasonField;

  /// No description provided for @payrollReferenceField.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get payrollReferenceField;

  /// No description provided for @payrollSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get payrollSave;

  /// No description provided for @payrollCorrectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Correct {name}\'s pay'**
  String payrollCorrectionTitle(String name);

  /// No description provided for @payrollCorrectionBody.
  ///
  /// In en, this message translates to:
  /// **'The approved payslip stays as it is. The correction is paid in the rider\'s next pay run.'**
  String get payrollCorrectionBody;

  /// No description provided for @payrollCorrectionMore.
  ///
  /// In en, this message translates to:
  /// **'Pay more'**
  String get payrollCorrectionMore;

  /// No description provided for @payrollCorrectionLess.
  ///
  /// In en, this message translates to:
  /// **'Take back'**
  String get payrollCorrectionLess;

  /// No description provided for @payrollFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment to {name} did not go through?'**
  String payrollFailedTitle(String name);

  /// No description provided for @payrollFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The pay stays owed and can be recorded as paid later.'**
  String get payrollFailedBody;

  /// No description provided for @payrollPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Record paying {name} {amount}?'**
  String payrollPaidTitle(String name, String amount);

  /// No description provided for @payrollPaidBody.
  ///
  /// In en, this message translates to:
  /// **'This records that your company paid the rider. YouDrop moves no money.'**
  String get payrollPaidBody;

  /// No description provided for @payrollApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve pay for {from} – {to}?'**
  String payrollApproveTitle(String from, String to);

  /// No description provided for @payrollApproveBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 rider, {total} to pay. Payslips are final once approved; a mistake is corrected in a later pay run.} other{{count} riders, {total} to pay. Payslips are final once approved; a mistake is corrected in a later pay run.}}'**
  String payrollApproveBody(int count, String total);

  /// No description provided for @payrollApproveCash.
  ///
  /// In en, this message translates to:
  /// **'{amount} of company cash your riders collected by {date} and still hold is kept from their pay and recorded as handed to your company.'**
  String payrollApproveCash(String amount, String date);

  /// No description provided for @payrollApproveYes.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get payrollApproveYes;

  /// No description provided for @payrollPayAllTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Record 1 payment of {total}?} other{Record {count} payments totalling {total}?}}'**
  String payrollPayAllTitle(int count, String total);

  /// No description provided for @payrollPayAllBody.
  ///
  /// In en, this message translates to:
  /// **'This records that your company paid these riders, and cannot be undone. Failed payments are left to record one by one.'**
  String get payrollPayAllBody;

  /// No description provided for @payrollRecordYes.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get payrollRecordYes;

  /// No description provided for @payrollDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this draft?'**
  String get payrollDiscardTitle;

  /// No description provided for @payrollDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'Its figures are thrown away and its history is kept. You can start the period again.'**
  String get payrollDiscardBody;

  /// No description provided for @payrollDiscardYes.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get payrollDiscardYes;

  /// No description provided for @payrollDone.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get payrollDone;

  /// No description provided for @payrollApproved.
  ///
  /// In en, this message translates to:
  /// **'Pay run approved.'**
  String get payrollApproved;

  /// No description provided for @payrollErrFiguresChanged.
  ///
  /// In en, this message translates to:
  /// **'The figures changed since you looked. Check the new ones, then approve again.'**
  String get payrollErrFiguresChanged;

  /// No description provided for @payrollErrCashChanged.
  ///
  /// In en, this message translates to:
  /// **'A rider\'s cash changed a moment ago. Nothing was approved; approve again to see the new figures.'**
  String get payrollErrCashChanged;

  /// No description provided for @payrollErrTotalChanged.
  ///
  /// In en, this message translates to:
  /// **'The total waiting for payment is now {amount}. Nothing was recorded.'**
  String payrollErrTotalChanged(String amount);

  /// No description provided for @payrollErrRefused.
  ///
  /// In en, this message translates to:
  /// **'That could not be done: the pay run has changed or no longer allows it. Reload and try again.'**
  String get payrollErrRefused;

  /// No description provided for @payrollErrFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be done just now. Please try again.'**
  String get payrollErrFailed;

  /// No description provided for @payrollErrRulesStart.
  ///
  /// In en, this message translates to:
  /// **'New rules cannot start on that day. Pick one of the days offered.'**
  String get payrollErrRulesStart;

  /// No description provided for @payrollRulesNow.
  ///
  /// In en, this message translates to:
  /// **'In force since {from}'**
  String payrollRulesNow(String from);

  /// No description provided for @payrollRulesNone.
  ///
  /// In en, this message translates to:
  /// **'No pay rules yet.'**
  String get payrollRulesNone;

  /// No description provided for @payrollRulesNext.
  ///
  /// In en, this message translates to:
  /// **'New rules start on {date}'**
  String payrollRulesNext(String date);

  /// No description provided for @payrollRulesCycle.
  ///
  /// In en, this message translates to:
  /// **'Pay riders'**
  String get payrollRulesCycle;

  /// No description provided for @payrollCycleSemiMonthly.
  ///
  /// In en, this message translates to:
  /// **'Twice a month (1st–15th, 16th–end)'**
  String get payrollCycleSemiMonthly;

  /// No description provided for @payrollCycleMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get payrollCycleMonthly;

  /// No description provided for @payrollRulesStart.
  ///
  /// In en, this message translates to:
  /// **'Starting on'**
  String get payrollRulesStart;

  /// No description provided for @payrollRulesPerDelivery.
  ///
  /// In en, this message translates to:
  /// **'Pay per delivery'**
  String get payrollRulesPerDelivery;

  /// No description provided for @payrollRulesHourly.
  ///
  /// In en, this message translates to:
  /// **'Hourly base (optional)'**
  String get payrollRulesHourly;

  /// No description provided for @payrollRulesHourlyHint.
  ///
  /// In en, this message translates to:
  /// **'Empty for no hourly pay'**
  String get payrollRulesHourlyHint;

  /// No description provided for @payrollRulesTyped.
  ///
  /// In en, this message translates to:
  /// **'Pay hours the office typed'**
  String get payrollRulesTyped;

  /// No description provided for @payrollRulesOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime multiplier'**
  String get payrollRulesOvertime;

  /// No description provided for @payrollRulesLate.
  ///
  /// In en, this message translates to:
  /// **'Deduction per late day'**
  String get payrollRulesLate;

  /// No description provided for @payrollRulesAbsence.
  ///
  /// In en, this message translates to:
  /// **'Deduction per absence'**
  String get payrollRulesAbsence;

  /// No description provided for @payrollRulesSave.
  ///
  /// In en, this message translates to:
  /// **'Save rules'**
  String get payrollRulesSave;

  /// No description provided for @payrollRulesNote.
  ///
  /// In en, this message translates to:
  /// **'Rules take effect from the first day of a pay period and never change a pay run already approved.'**
  String get payrollRulesNote;

  /// No description provided for @payrollMultiplierInvalid.
  ///
  /// In en, this message translates to:
  /// **'Between 1.00 and 5.00'**
  String get payrollMultiplierInvalid;

  /// No description provided for @payrollRulesNoStart.
  ///
  /// In en, this message translates to:
  /// **'No day is open for new rules right now.'**
  String get payrollRulesNoStart;

  /// No description provided for @payrollCashMethodKeptFromPay.
  ///
  /// In en, this message translates to:
  /// **'Kept from pay'**
  String get payrollCashMethodKeptFromPay;

  /// No description provided for @payrollReadBeforeEnd.
  ///
  /// In en, this message translates to:
  /// **'These figures were read on {time}, before the period ended. Recompute to count the whole period before approving.'**
  String payrollReadBeforeEnd(String time);

  /// No description provided for @payrollDeliveriesNotDeployed.
  ///
  /// In en, this message translates to:
  /// **'Deliveries cannot be counted from orders on this platform yet, so these figures count only deliveries that earned a fee: free deliveries are missing from them.'**
  String get payrollDeliveriesNotDeployed;

  /// No description provided for @payrollDeliveriesMissing.
  ///
  /// In en, this message translates to:
  /// **'Deliveries could not be counted from orders just now, so these figures count only deliveries that earned a fee. Recompute to count every delivery.'**
  String get payrollDeliveriesMissing;

  /// No description provided for @payrollHoursMissingFor.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Hours could not be read for {names}, so their pay leaves hours out.} other{Hours could not be read for {names}, so their pay leaves hours out.}}'**
  String payrollHoursMissingFor(int count, String names);

  /// No description provided for @payrollNamesMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{names} and 1 other} other{{names} and {count} others}}'**
  String payrollNamesMore(String names, int count);

  /// No description provided for @payrollListSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get payrollListSeparator;

  /// No description provided for @payrollApproveDeliveriesLedger.
  ///
  /// In en, this message translates to:
  /// **'Deliveries were counted only from jobs that earned a fee, so free deliveries are missing from this pay.'**
  String get payrollApproveDeliveriesLedger;

  /// No description provided for @payrollApproveWithoutMissing.
  ///
  /// In en, this message translates to:
  /// **'Approve without what is missing'**
  String get payrollApproveWithoutMissing;

  /// No description provided for @payrollErrNeedsAcknowledgement.
  ///
  /// In en, this message translates to:
  /// **'Something is missing from these figures. Tick the box to approve without it.'**
  String get payrollErrNeedsAcknowledgement;

  /// No description provided for @payrollErrRecomputeNeeded.
  ///
  /// In en, this message translates to:
  /// **'These figures were read before the period ended. Recompute, check them and approve again.'**
  String get payrollErrRecomputeNeeded;

  /// No description provided for @payrollHoursNotListed.
  ///
  /// In en, this message translates to:
  /// **'Attendance shows no time this rider worked for your company in this period, so their hours are not known.'**
  String get payrollHoursNotListed;

  /// No description provided for @chatRoomEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Neighbourhood chat'**
  String get chatRoomEntryTitle;

  /// No description provided for @chatRoomEntrySub.
  ///
  /// In en, this message translates to:
  /// **'Talk with the people who live around you'**
  String get chatRoomEntrySub;

  /// No description provided for @chatRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'{area} chat'**
  String chatRoomTitle(String area);

  /// No description provided for @chatRoomLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get chatRoomLive;

  /// No description provided for @chatRoomMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 neighbour} other{{count} neighbours}}'**
  String chatRoomMembers(int count);

  /// No description provided for @chatRoomCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get chatRoomCommunity;

  /// No description provided for @chatRoomComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message or ask a neighbour…'**
  String get chatRoomComposerHint;

  /// No description provided for @chatRoomEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Say hello to your neighbours.'**
  String get chatRoomEmpty;

  /// No description provided for @chatRoomCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load your neighbourhood chat'**
  String get chatRoomCouldNotLoad;

  /// No description provided for @chatRoomPickAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your area to join its chat'**
  String get chatRoomPickAreaTitle;

  /// No description provided for @chatRoomPickAreaBody.
  ///
  /// In en, this message translates to:
  /// **'Neighbourhood chat follows the area of your delivery address.'**
  String get chatRoomPickAreaBody;

  /// No description provided for @chatRoomChooseArea.
  ///
  /// In en, this message translates to:
  /// **'Choose area'**
  String get chatRoomChooseArea;

  /// No description provided for @chatRoomUnknownAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'Your area has no neighbourhood chat'**
  String get chatRoomUnknownAreaTitle;

  /// No description provided for @chatRoomUnknownAreaBody.
  ///
  /// In en, this message translates to:
  /// **'Pick one of the delivery areas for your address to join its chat.'**
  String get chatRoomUnknownAreaBody;

  /// No description provided for @chatRoomMoveBlocked.
  ///
  /// In en, this message translates to:
  /// **'You can move to your new area\'s chat from {date}.'**
  String chatRoomMoveBlocked(String date);

  /// No description provided for @chatRoomMuted.
  ///
  /// In en, this message translates to:
  /// **'A moderator has paused your messages here until {date}.'**
  String chatRoomMuted(String date);

  /// No description provided for @chatRoomHidden.
  ///
  /// In en, this message translates to:
  /// **'This message was removed'**
  String get chatRoomHidden;

  /// No description provided for @chatRoomNeighbour.
  ///
  /// In en, this message translates to:
  /// **'Neighbour'**
  String get chatRoomNeighbour;

  /// No description provided for @chatRoomReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get chatRoomReport;

  /// No description provided for @chatRoomReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this message?'**
  String get chatRoomReportTitle;

  /// No description provided for @chatRoomReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam or advertising'**
  String get chatRoomReasonSpam;

  /// No description provided for @chatRoomReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse or harassment'**
  String get chatRoomReasonAbuse;

  /// No description provided for @chatRoomReasonPersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Someone\'s personal details'**
  String get chatRoomReasonPersonalInfo;

  /// No description provided for @chatRoomReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get chatRoomReasonOther;

  /// No description provided for @chatRoomReportSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks. A moderator will review it.'**
  String get chatRoomReportSent;

  /// No description provided for @chatRoomBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get chatRoomBlock;

  /// No description provided for @chatRoomBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String chatRoomBlockTitle(String name);

  /// No description provided for @chatRoomBlockBody.
  ///
  /// In en, this message translates to:
  /// **'You won\'t see their messages in neighbourhood chat. They won\'t be told.'**
  String get chatRoomBlockBody;

  /// No description provided for @chatRoomBlockedToast.
  ///
  /// In en, this message translates to:
  /// **'Blocked. You won\'t see their messages.'**
  String get chatRoomBlockedToast;

  /// No description provided for @chatRoomCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get chatRoomCopy;

  /// No description provided for @chatRoomCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get chatRoomCopied;

  /// No description provided for @chatRoomRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Community rules'**
  String get chatRoomRulesTitle;

  /// No description provided for @chatRoomRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Be kind to your neighbours. No spam or advertising, no harassment, and never post anyone\'s phone number or address. Moderators remove messages that break these rules.'**
  String get chatRoomRulesBody;

  /// No description provided for @chatRoomBlockedPeople.
  ///
  /// In en, this message translates to:
  /// **'People you blocked'**
  String get chatRoomBlockedPeople;

  /// No description provided for @chatRoomNoBlocks.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t blocked anyone.'**
  String get chatRoomNoBlocks;

  /// No description provided for @chatRoomUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get chatRoomUnblock;

  /// No description provided for @chatSlowDown.
  ///
  /// In en, this message translates to:
  /// **'You\'re sending messages too fast. Wait a moment and try again.'**
  String get chatSlowDown;

  /// No description provided for @chatTooLong.
  ///
  /// In en, this message translates to:
  /// **'That message is too long.'**
  String get chatTooLong;

  /// No description provided for @chatActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work. Try again.'**
  String get chatActionFailed;

  /// No description provided for @chatShopWith.
  ///
  /// In en, this message translates to:
  /// **'Chat with {shop}'**
  String chatShopWith(String shop);

  /// No description provided for @chatShopHintCustomer.
  ///
  /// In en, this message translates to:
  /// **'Message the shop…'**
  String get chatShopHintCustomer;

  /// No description provided for @chatShopHintMerchant.
  ///
  /// In en, this message translates to:
  /// **'Reply to the customer…'**
  String get chatShopHintMerchant;

  /// No description provided for @chatShopEmptyCustomer.
  ///
  /// In en, this message translates to:
  /// **'Ask the shop anything: what\'s in stock, prices, opening hours.'**
  String get chatShopEmptyCustomer;

  /// No description provided for @chatShopEmptyMerchant.
  ///
  /// In en, this message translates to:
  /// **'No messages in this conversation yet.'**
  String get chatShopEmptyMerchant;

  /// No description provided for @chatShopCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load this conversation'**
  String get chatShopCouldNotLoad;

  /// No description provided for @chatShopQuietCustomer.
  ///
  /// In en, this message translates to:
  /// **'This chat has gone quiet.'**
  String get chatShopQuietCustomer;

  /// No description provided for @chatShopReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get chatShopReopen;

  /// No description provided for @chatShopQuietMerchant.
  ///
  /// In en, this message translates to:
  /// **'This conversation has gone quiet. The customer can start it again from your shop\'s page.'**
  String get chatShopQuietMerchant;

  /// No description provided for @chatShopInboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer messages'**
  String get chatShopInboxTitle;

  /// No description provided for @chatShopInboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'No customer messages yet'**
  String get chatShopInboxEmpty;

  /// No description provided for @chatShopInboxEmptySub.
  ///
  /// In en, this message translates to:
  /// **'Customers can message your shop from its page in the app.'**
  String get chatShopInboxEmptySub;

  /// No description provided for @chatShopInboxCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load customer messages'**
  String get chatShopInboxCouldNotLoad;

  /// No description provided for @chatShopCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get chatShopCustomer;

  /// No description provided for @chatShopYouPrefix.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String chatShopYouPrefix(String text);

  /// No description provided for @chatShopQuietBadge.
  ///
  /// In en, this message translates to:
  /// **'Quiet'**
  String get chatShopQuietBadge;

  /// No description provided for @chatModerationTitle.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get chatModerationTitle;

  /// No description provided for @chatModerationSub.
  ///
  /// In en, this message translates to:
  /// **'Reported neighbourhood chat messages, oldest first.'**
  String get chatModerationSub;

  /// No description provided for @chatModerationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports waiting'**
  String get chatModerationEmpty;

  /// No description provided for @chatModerationCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load the moderation queue'**
  String get chatModerationCouldNotLoad;

  /// No description provided for @chatModerationReports.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 report} other{{count} reports}}'**
  String chatModerationReports(int count);

  /// No description provided for @chatModerationHide.
  ///
  /// In en, this message translates to:
  /// **'Hide message'**
  String get chatModerationHide;

  /// No description provided for @chatModerationDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get chatModerationDismiss;

  /// No description provided for @chatModerationMute.
  ///
  /// In en, this message translates to:
  /// **'Mute author'**
  String get chatModerationMute;

  /// No description provided for @chatModerationUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute author'**
  String get chatModerationUnmute;

  /// No description provided for @chatModerationMute24h.
  ///
  /// In en, this message translates to:
  /// **'For 24 hours'**
  String get chatModerationMute24h;

  /// No description provided for @chatModerationMute7d.
  ///
  /// In en, this message translates to:
  /// **'For 7 days'**
  String get chatModerationMute7d;

  /// No description provided for @chatModerationMute30d.
  ///
  /// In en, this message translates to:
  /// **'For 30 days'**
  String get chatModerationMute30d;

  /// No description provided for @chatModerationReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (kept in the audit trail)'**
  String get chatModerationReasonLabel;

  /// No description provided for @chatModerationReasonTooShort.
  ///
  /// In en, this message translates to:
  /// **'Write at least 3 characters'**
  String get chatModerationReasonTooShort;

  /// No description provided for @chatModerationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get chatModerationConfirm;

  /// No description provided for @chatModerationRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get chatModerationRemoved;

  /// No description provided for @chatModerationMutedUntil.
  ///
  /// In en, this message translates to:
  /// **'Author muted until {date}'**
  String chatModerationMutedUntil(String date);

  /// No description provided for @chatModerationDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get chatModerationDone;

  /// No description provided for @chatModerationRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get chatModerationRefresh;

  /// No description provided for @chatRoomOlderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load earlier messages. Tap to try again.'**
  String get chatRoomOlderFailed;

  /// No description provided for @chatRoomPostAfterDelivery.
  ///
  /// In en, this message translates to:
  /// **'You can post here after your first delivery to this area.'**
  String get chatRoomPostAfterDelivery;

  /// No description provided for @chatRoomPostingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Posting is paused while we check your deliveries. Try again shortly.'**
  String get chatRoomPostingUnavailable;

  /// No description provided for @chatShopUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread message} other{{count} unread messages}}'**
  String chatShopUnreadCount(int count);

  /// No description provided for @multiCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Basket'**
  String get multiCartTitle;

  /// No description provided for @multiCartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One checkout, every shop'**
  String get multiCartSubtitle;

  /// No description provided for @multiCartShopCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shop} other{{count} shops}}'**
  String multiCartShopCount(int count);

  /// No description provided for @multiCartFromShop.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{From {store} (1 item)} other{From {store} ({count} items)}}'**
  String multiCartFromShop(int count, String store);

  /// No description provided for @multiCartShopDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery from this shop'**
  String get multiCartShopDelivery;

  /// No description provided for @multiCartDeliveryFromShops.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delivery from 1 shop} other{Delivery from {count} shops}}'**
  String multiCartDeliveryFromShops(int count);

  /// No description provided for @multiCartCheckoutAmount.
  ///
  /// In en, this message translates to:
  /// **'Checkout — {amount}'**
  String multiCartCheckoutAmount(String amount);

  /// No description provided for @multiCartBelowMinimum.
  ///
  /// In en, this message translates to:
  /// **'Add {amount} more from {store} to reach its minimum order'**
  String multiCartBelowMinimum(String amount, String store);

  /// No description provided for @multiCartShopClosed.
  ///
  /// In en, this message translates to:
  /// **'{store} is closed right now. Remove its items to check out.'**
  String multiCartShopClosed(String store);

  /// No description provided for @multiCartShopNotServing.
  ///
  /// In en, this message translates to:
  /// **'{store} doesn\'t deliver to your address. Remove its items to check out.'**
  String multiCartShopNotServing(String store);

  /// No description provided for @multiCartShopUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{store} can\'t take this order right now.'**
  String multiCartShopUnavailable(String store);

  /// No description provided for @multiCartRemoveShop.
  ///
  /// In en, this message translates to:
  /// **'Remove {store}'**
  String multiCartRemoveShop(String store);

  /// No description provided for @multiCartShopLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'{max, plural, =1{One shop per basket} other{Up to {max} shops per basket}}'**
  String multiCartShopLimitTitle(int max);

  /// No description provided for @multiCartShopLimitBody.
  ///
  /// In en, this message translates to:
  /// **'Check out, or remove a shop from your basket, before adding items from another.'**
  String get multiCartShopLimitBody;

  /// No description provided for @multiCartPartOfOrder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Part of a {count}-shop order}}'**
  String multiCartPartOfOrder(int count);

  /// No description provided for @multiCartCannotWait.
  ///
  /// In en, this message translates to:
  /// **'A basket from several shops can\'t wait for the connection: its shops\' orders are placed together, while you\'re online. Check out once you\'re back.'**
  String get multiCartCannotWait;

  /// No description provided for @multiCartGiftOneShop.
  ///
  /// In en, this message translates to:
  /// **'A gift is sent from one shop at a time. Remove the other shops\' items, or send this basket as an ordinary order.'**
  String get multiCartGiftOneShop;

  /// No description provided for @multiCartPlaced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order placed · {amount}} other{{count} orders placed · {amount}}}'**
  String multiCartPlaced(int count, String amount);

  /// No description provided for @multiCartPricesUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating prices…'**
  String get multiCartPricesUpdating;

  /// No description provided for @multiCartPricesFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm the latest prices.'**
  String get multiCartPricesFailed;

  /// No description provided for @multiCartPriceChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'The total has changed'**
  String get multiCartPriceChangedTitle;

  /// No description provided for @multiCartPriceChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Your basket now comes to {total}, not the {agreed} you saw. Place its orders at the new total?'**
  String multiCartPriceChangedBody(String total, String agreed);

  /// No description provided for @multiCartEarlierCheckoutPlaced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Your earlier checkout already went through: all {count} of its orders are in Orders.}}'**
  String multiCartEarlierCheckoutPlaced(int count);

  /// No description provided for @svcVerticalServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get svcVerticalServices;

  /// No description provided for @svcCategoryPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get svcCategoryPrinting;

  /// No description provided for @svcCategoryTailoring.
  ///
  /// In en, this message translates to:
  /// **'Tailoring & alterations'**
  String get svcCategoryTailoring;

  /// No description provided for @svcCategoryRepairs.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get svcCategoryRepairs;

  /// No description provided for @svcCategoryPhotography.
  ///
  /// In en, this message translates to:
  /// **'Photography'**
  String get svcCategoryPhotography;

  /// No description provided for @svcCategoryCleaning.
  ///
  /// In en, this message translates to:
  /// **'Cleaning'**
  String get svcCategoryCleaning;

  /// No description provided for @svcCategoryBeauty.
  ///
  /// In en, this message translates to:
  /// **'Beauty'**
  String get svcCategoryBeauty;

  /// No description provided for @svcCategoryTutoring.
  ///
  /// In en, this message translates to:
  /// **'Tutoring'**
  String get svcCategoryTutoring;

  /// No description provided for @svcActionCollected.
  ///
  /// In en, this message translates to:
  /// **'Customer collected'**
  String get svcActionCollected;

  /// No description provided for @svcDeclineTooBusy.
  ///
  /// In en, this message translates to:
  /// **'Too busy right now'**
  String get svcDeclineTooBusy;

  /// No description provided for @svcDeclineCannotDo.
  ///
  /// In en, this message translates to:
  /// **'We can\'t do this job'**
  String get svcDeclineCannotDo;

  /// No description provided for @svcDeclineFileProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem with the file'**
  String get svcDeclineFileProblem;

  /// No description provided for @svcDeclineOther.
  ///
  /// In en, this message translates to:
  /// **'Other reason'**
  String get svcDeclineOther;
}

class _DeliveryStringsDelegate extends LocalizationsDelegate<DeliveryStrings> {
  const _DeliveryStringsDelegate();

  @override
  Future<DeliveryStrings> load(Locale locale) {
    return SynchronousFuture<DeliveryStrings>(lookupDeliveryStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_DeliveryStringsDelegate old) => false;
}

DeliveryStrings lookupDeliveryStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return DeliveryStringsAr();
    case 'en':
      return DeliveryStringsEn();
  }

  throw FlutterError(
      'DeliveryStrings.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
