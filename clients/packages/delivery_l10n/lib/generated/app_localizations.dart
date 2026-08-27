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
  /// **'Create an account'**
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
  /// **'Sign up'**
  String get authSignUp;

  /// No description provided for @authSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter your credentials to log in.'**
  String get authSignInSubtitle;

  /// No description provided for @authEmailOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Email or phone number'**
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

  /// No description provided for @authZonesComingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Zones are not mapped yet'**
  String get authZonesComingSoonTitle;

  /// No description provided for @authZonesComingSoonBlurb.
  ///
  /// In en, this message translates to:
  /// **'Pickable delivery zones arrive with the coverage map. Until then, the area above is what we go by.'**
  String get authZonesComingSoonBlurb;

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

  /// No description provided for @custAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get custAppLanguage;

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
  /// **'Search menu items...'**
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
  /// **'Upload delicious food image'**
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

  /// No description provided for @merchbSaveMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Save Menu Item'**
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
