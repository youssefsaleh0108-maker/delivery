import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the customer wants their order delivered.
///
/// Held here rather than typed fresh at checkout every time. The home screen shows it, checkout
/// pre-fills from it, and the last few are remembered so a customer switching between home and
/// work picks rather than retypes.
///
/// Device-local for now. A server-side address book is the right eventual home — it would follow
/// the customer between devices and let the rider app read it — but this keeps the address out of
/// a free-text box without waiting on that.
class DeliveryAddress {
  const DeliveryAddress({
    required this.line,
    this.label,
    this.notes,
    this.zoneId,
    this.zoneName,
    this.latitude,
    this.longitude,
  });

  /// The address itself, as the customer typed it.
  final String line;

  /// Optional "Home", "Work". Purely for recognising it in a list.
  final String? label;

  /// Buzzer codes, floor, "leave at the door" — sent to the rider as order notes.
  final String? notes;

  /// The area this address is in, as picked from a list.
  ///
  /// Nullable, and stays that way: addresses saved before areas existed have none, and a shop that
  /// prices a flat fee everywhere does not care. An order with no area is priced exactly as it
  /// always was rather than refused.
  final String? zoneId;

  /// Kept alongside the id so the address reads correctly without a lookup, including offline and
  /// including after the area has been retired.
  final String? zoneName;

  /// Where the address is, when it came out of the place picker rather than a free-text box.
  ///
  /// Both-or-neither, like the store pin: an address typed by hand has no coordinates, and that is
  /// its normal state, not an error. When present they travel with the order so the tracking
  /// service has a real point to measure the rider's ETA against.
  final double? latitude;
  final double? longitude;

  /// Whether the picker pinned this address to a point on the map.
  bool get hasPoint => latitude != null && longitude != null;

  String get display => label == null || label!.isEmpty ? line : '$label · $line';

  DeliveryAddress withZone(String? id, String? name) => DeliveryAddress(
      line: line,
      label: label,
      notes: notes,
      zoneId: id,
      zoneName: name,
      latitude: latitude,
      longitude: longitude);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'line': line,
        'label': label,
        'notes': notes,
        'zoneId': zoneId,
        'zoneName': zoneName,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => DeliveryAddress(
        line: json['line'] as String,
        label: json['label'] as String?,
        notes: json['notes'] as String?,
        zoneId: json['zoneId'] as String?,
        zoneName: json['zoneName'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is DeliveryAddress && other.line.trim().toLowerCase() == line.trim().toLowerCase();

  @override
  int get hashCode => line.trim().toLowerCase().hashCode;
}

/// Owns the chosen address and the recent ones, and persists both, PER SIGNED-IN PERSON.
///
/// The key is scoped by the Keycloak `sub`. It used to be one fixed key for the whole device, so
/// every account that signed in on a phone inherited whatever addresses the last one had saved —
/// which is what a tester sees immediately, signing in as a customer, then a rider, then a
/// merchant, and finding the same delivery locations under all three. On a shared or handed-over
/// phone it also shows one person where another one lives.
class DeliveryAddressStore extends ChangeNotifier {
  DeliveryAddressStore({FlutterSecureStorage? storage, required this.ownerId})
      : _storage = storage ?? const FlutterSecureStorage();

  /// The Keycloak `sub` of whoever is signed in. Null only before a session exists, in which case
  /// nothing is written at all rather than written somewhere a later account would read it.
  final String? ownerId;

  /// The device-wide key this used to write to. Read once, only to delete it — see [load].
  static const String _legacyKey = 'delivery.addresses';
  static const String _keyPrefix = 'delivery.addresses.';
  static const int _maxRecents = 5;

  String? get _key => ownerId == null ? null : '$_keyPrefix$ownerId';

  final FlutterSecureStorage _storage;

  DeliveryAddress? _selected;
  List<DeliveryAddress> _recents = <DeliveryAddress>[];
  bool _loaded = false;

  DeliveryAddress? get selected => _selected;

  List<DeliveryAddress> get recents => List<DeliveryAddress>.unmodifiable(_recents);

  bool get isSet => _selected != null;

  bool get loaded => _loaded;

  /// What the home screen header shows.
  ///
  /// The prompt is passed in rather than held here: this is a store with no BuildContext, and the
  /// only part of the answer that needs translating is the case where there is no address yet.
  String headerLabelOr(String prompt) => _selected?.display ?? prompt;

  Future<void> load() async {
    // Delete the old device-wide blob rather than adopt it. Nothing records whose addresses those
    // were, so handing them to whoever signs in next is exactly the bug being fixed here — and
    // attributing somebody's home address to the wrong account is worse than asking for it again.
    try {
      await _storage.delete(key: _legacyKey);
    } catch (_) {
      // Nothing to do: it is a cleanup, and a failure leaves an unread key behind.
    }

    final String? key = _key;
    if (key == null) {
      _loaded = true;
      notifyListeners();
      return;
    }

    try {
      final String? raw = await _storage.read(key: key);
      if (raw != null) {
        final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
        _recents = (json['recents'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => DeliveryAddress.fromJson(e as Map<String, dynamic>))
            .toList();
        final Map<String, dynamic>? sel = json['selected'] as Map<String, dynamic>?;
        _selected = sel == null ? null : DeliveryAddress.fromJson(sel);
      }
    } catch (_) {
      // A corrupt or unreadable blob must not stop the app booting — the customer simply has no
      // saved address and is asked for one.
      _recents = <DeliveryAddress>[];
      _selected = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Selects an address and promotes it to the top of the recents.
  Future<void> select(DeliveryAddress address) async {
    _selected = address;
    // Equality is on the address line, so re-selecting an existing one moves it rather than
    // duplicating it.
    _recents = <DeliveryAddress>[
      address,
      ..._recents.where((DeliveryAddress a) => a != address),
    ].take(_maxRecents).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> forget(DeliveryAddress address) async {
    _recents = _recents.where((DeliveryAddress a) => a != address).toList();
    if (_selected == address) {
      _selected = _recents.isEmpty ? null : _recents.first;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final String? key = _key;
    if (key == null) {
      // No session, so there is no one to attribute this to. Held in memory for the session and
      // written nowhere — a guest's address must not become the next account's address.
      return;
    }
    try {
      await _storage.write(
        key: key,
        value: jsonEncode(<String, dynamic>{
          'selected': _selected?.toJson(),
          'recents': _recents.map((DeliveryAddress a) => a.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Persistence is a convenience. Failing to write must not lose the address the customer
      // just chose for this session.
    }
  }
}

// -------------------------------------------------------------------------------------------
// Wave-2 customer strings.
// -------------------------------------------------------------------------------------------

/// Localised strings for the wave-2 customer wiring, resolved from the same keys the l10n
/// fragments carry (`l10n-fragments2/cust2.json` and the API layer's `core.json`).
///
/// This extension exists so the wiring compiles and speaks both languages *before* the fragments
/// are merged into the shared .arb files. Every member matches its fragment key by name and by
/// value, and Dart resolves instance members ahead of extension members — so the moment the
/// finish agent merges and regenerates `DeliveryStrings`, the generated getters take over at
/// every call site and this extension goes dormant. It can then be deleted.
///
/// It lives in this file because every customer screen already imports the address store, so the
/// strings ride along without a screen having to import another screen just to speak.
extension CustWave2Strings on DeliveryStrings {
  bool get _ar => localeName.startsWith('ar');
  String _s(String en, String ar) => _ar ? ar : en;

  // ---------------------------------------------------------------- payments
  String get custTestPayment => _s('Test payment', 'دفعة تجريبية');
  String get custPaymentDeclined => _s(
      'The payment was declined and your order was not placed.',
      'رُفض الدفع ولم يُقدَّم طلبك.');
  String get paymentWallet => _s('Wallet', 'المحفظة');
  String get paymentTestModeNote => _s('Test payment — no real money moves in this build',
      'دفعة تجريبية — لا يُحوَّل أي مال حقيقي في هذه النسخة');

  // ---------------------------------------------------------------- promo codes
  String get custPromoRemove => _s('Remove the code', 'إزالة الرمز');
  String get custPromoChecking => _s('Checking the code…', 'جارٍ التحقق من الرمز…');
  String get promoApplied => _s('The code was applied', 'تم تطبيق الرمز');
  String get promoUnknownCode => _s('That code was not recognised', 'الرمز غير معروف');
  String get promoNotActive => _s('That code is no longer available', 'هذا الرمز لم يعد متاحاً');
  String get promoNotStarted =>
      _s('That code cannot be used yet', 'لا يمكن استخدام هذا الرمز بعد');
  String get promoExpired => _s('That code has expired', 'انتهت صلاحية هذا الرمز');
  String get promoBelowMinimum => _s('Your basket is below the minimum for that code',
      'سلّتك أقل من الحد الأدنى لهذا الرمز');
  String get promoFullyRedeemed =>
      _s('That code has been fully redeemed', 'استُنفد هذا الرمز بالكامل');
  String get promoAlreadyUsed =>
      _s('You have already used that code', 'سبق أن استخدمت هذا الرمز');
  String get promoWorthNothing =>
      _s('That code is worth nothing on this order', 'لا قيمة لهذا الرمز على هذا الطلب');
  String get promoDidNotApply => _s('That code did not apply', 'لم يُطبَّق هذا الرمز');
  String get promoCouldNotCheck =>
      _s('Could not check the code', 'تعذّر التحقق من الرمز');

  // ---------------------------------------------------------------- eta
  String get etaMinShort => _s('min', 'دقيقة');
  String get etaArriving => _s('Expected arrival', 'الوصول المتوقع');
  String get etaRemaining => _s('Remaining', 'المتبقي');
  String get etaWaitingFirstFix =>
      _s("Waiting for the rider's first GPS fix", 'بانتظار أول إشارة GPS من السائق');
  String get etaPositionOutOfDate =>
      _s("The rider's position is out of date", 'موقع السائق غير محدَّث');
  String get etaNoMapPoint =>
      _s('No map point to measure to', 'لا توجد نقطة على الخريطة للقياس إليها');
  String get etaRouteServiceDown =>
      _s('The route service did not answer', 'خدمة المسارات لم تستجب');
  String get etaNothingOnItsWay => _s('Nothing is on its way', 'لا يوجد شيء في الطريق');
  String get etaUnavailable => _s('No estimate available', 'لا يتوفر تقدير للوصول');
  String get etaHeadingToShop => _s('Heading to the shop', 'في الطريق إلى المتجر');
  String get etaOnTheWayToYou => _s('On the way to you', 'في الطريق إليك');
  String get etaStraightLineNote => _s(
      'Rough estimate — measured in a straight line, not by road',
      'تقدير تقريبي — يُقاس بخط مستقيم لا عبر الطرقات');

  // ---------------------------------------------------------------- chat
  String get custChatWithRider => _s('Message the rider', 'مراسلة السائق');
  String get chatTypeMessage => _s('Type a message…', 'اكتب رسالة…');
  String get chatSend => _s('Send', 'إرسال');
  String get chatClosed => _s('This conversation is closed', 'أُغلقت هذه المحادثة');
  String get chatNoMessagesYet => _s('No messages yet', 'لا رسائل بعد');
  String get chatCouldNotSend => _s('Could not send your message', 'تعذّر إرسال رسالتك');
  String get couldNotLoadChat => _s('Could not load the conversation', 'تعذّر تحميل المحادثة');

  // ---------------------------------------------------------------- rider rating
  String get custRateYourRider => _s('Rate your rider', 'قيّم السائق');
  String get custHowWasDelivery => _s('How was your delivery?', 'كيف كانت تجربة التوصيل؟');
  String get custAddCommentOptional =>
      _s('Add a comment (optional)', 'أضف تعليقاً (اختياري)');
  String get custSubmitRating => _s('Submit rating', 'إرسال التقييم');
  String get custThanksForRating =>
      _s('Thanks for rating your rider', 'شكراً لتقييمك السائق');
  String get custAlreadyRatedDelivery => _s('You rated this delivery', 'لقد قيّمت هذا التوصيل');
  String get custCouldNotSendRating => _s('Could not send your rating', 'تعذّر إرسال تقييمك');
  String ratingStars(int n) => _s('$n stars', '$n نجوم');

  // ---------------------------------------------------------------- the address picker
  String get searchForAPlace => _s('Search for a place…', 'ابحث عن مكان…');
  String get noPlacesFound => _s('No places found', 'لم يُعثر على أماكن');
  String get couldNotSearchPlaces => _s('Could not search just now', 'تعذّر البحث الآن');
  String get addressPinnedOnMap => _s('Pinned on the map', 'محدَّد على الخريطة');

  // ---------------------------------------------------------------- notification preferences
  String get notifPreferences => _s('Notification preferences', 'تفضيلات الإشعارات');
  String get notifPrefsBlurb =>
      _s('Choose how we reach you, topic by topic', 'اختر كيف نتواصل معك، موضوعاً بموضوع');
  String get notifAlwaysOn => _s(
      'Always on — account and security messages cannot be switched off',
      'مفعَّل دائماً — لا يمكن إيقاف رسائل الحساب والأمان');
  String get couldNotLoadPreferences =>
      _s('Could not load your preferences', 'تعذّر تحميل تفضيلاتك');
  String get couldNotSaveThatChange =>
      _s('Could not save that change', 'تعذّر حفظ هذا التغيير');
  String get notifCatOrderUpdates => _s('Order updates', 'تحديثات الطلبات');
  String get notifCatChat => _s('Chat', 'المحادثات');
  String get notifCatPromotions => _s('Promotions', 'العروض الترويجية');
  String get notifCatAccount => _s('Account and security', 'الحساب والأمان');
  String get notifChannelPush => _s('Push', 'إشعارات فورية');
  String get notifChannelInApp => _s('In-app', 'داخل التطبيق');
  String get notifChannelEmail => _s('Email', 'البريد الإلكتروني');
  String get notifChannelSms => _s('SMS', 'رسائل نصية');

  // ---------------------------------------------------------------- cross-sell
  String get crossSellBoughtTogether => _s('Often bought together', 'يُشترى معاً غالباً');
  String get crossSellSameShelf => _s('From the same shelf', 'من الرف نفسه');
  String get crossSellYouMightAlsoLike => _s('You might also like', 'قد يعجبك أيضاً');
  String crossSellTogetherCount(int count) => _s('$count× together', '$count× معاً');
}

/// The sentence the basket shows for a promo quote the server refused.
String custPromoReasonLabel(DeliveryStrings t, PromoQuoteReason reason) => switch (reason) {
      PromoQuoteReason.ok => t.promoApplied,
      PromoQuoteReason.unknownCode => t.promoUnknownCode,
      PromoQuoteReason.notActive => t.promoNotActive,
      PromoQuoteReason.notStarted => t.promoNotStarted,
      PromoQuoteReason.expired => t.promoExpired,
      PromoQuoteReason.belowMinimum => t.promoBelowMinimum,
      PromoQuoteReason.fullyRedeemed => t.promoFullyRedeemed,
      PromoQuoteReason.customerLimitReached => t.promoAlreadyUsed,
      PromoQuoteReason.nothingToDiscount => t.promoWorthNothing,
      PromoQuoteReason.unknown => t.promoDidNotApply,
    };

/// The sentence for an ETA the server declined to number, in the customer's language.
String custEtaReasonLabel(DeliveryStrings t, EtaUnavailableReason reason) => switch (reason) {
      EtaUnavailableReason.noFix => t.etaWaitingFirstFix,
      EtaUnavailableReason.staleFix => t.etaPositionOutOfDate,
      EtaUnavailableReason.noDestination => t.etaNoMapPoint,
      EtaUnavailableReason.providerUnavailable => t.etaRouteServiceDown,
      EtaUnavailableReason.orderComplete => t.etaNothingOnItsWay,
      EtaUnavailableReason.unknown => t.etaUnavailable,
    };

/// Which stretch of the journey an estimate covers, in the customer's language.
String custEtaLegLabel(DeliveryStrings t, EtaLeg leg) => switch (leg) {
      EtaLeg.toPickup => t.etaHeadingToShop,
      EtaLeg.toDropoff => t.etaOnTheWayToYou,
    };

/// A notification category's label — the wire string itself for one this build does not know,
/// because a row the server sent must render even when it cannot be translated.
String custNotifCategoryLabel(DeliveryStrings t, NotificationPreference pref) =>
    switch (pref.category) {
      NotificationCategory.orderUpdates => t.notifCatOrderUpdates,
      NotificationCategory.chat => t.notifCatChat,
      NotificationCategory.promotions => t.notifCatPromotions,
      NotificationCategory.account => t.notifCatAccount,
      null => pref.categoryWire,
    };

/// A notification channel's label, same contract as [custNotifCategoryLabel].
String custNotifChannelLabel(DeliveryStrings t, NotificationChannel? channel, String wire) =>
    switch (channel) {
      NotificationChannel.push => t.notifChannelPush,
      NotificationChannel.inApp => t.notifChannelInApp,
      NotificationChannel.email => t.notifChannelEmail,
      NotificationChannel.sms => t.notifChannelSms,
      null => wire,
    };
