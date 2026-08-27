// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class DeliveryStringsAr extends DeliveryStrings {
  DeliveryStringsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'YouDrop';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navShops => 'المتاجر';

  @override
  String get navBasket => 'السلة';

  @override
  String get navOrders => 'الطلبات';

  @override
  String get navButler => 'بتلر';

  @override
  String get alerts => 'التنبيهات';

  @override
  String get settings => 'الإعدادات';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get deliverTo => 'التوصيل إلى';

  @override
  String get setDeliveryAddress => 'حدّد عنوان التوصيل';

  @override
  String get address => 'العنوان';

  @override
  String get addressHint => 'شارع الاختبار ١٢، شقة ٤';

  @override
  String get labelOptional => 'التسمية (اختياري)';

  @override
  String get labelHint => 'المنزل، العمل';

  @override
  String get riderNotesOptional => 'ملاحظات للسائق (اختياري)';

  @override
  String get riderNotesHint => 'جرس ٤، الطابق الثاني';

  @override
  String get deliverHere => 'التوصيل هنا';

  @override
  String get recent => 'الأخيرة';

  @override
  String get whereShouldWeBring => 'إلى أين نوصل طلبك؟';

  @override
  String get forgetThisAddress => 'حذف هذا العنوان';

  @override
  String get addressTooShort => 'أضف تفاصيل أكثر ليتمكن السائق من الوصول إليك';

  @override
  String get searchShops => 'ابحث عن متاجر ومأكولات';

  @override
  String get all => 'الكل';

  @override
  String get allStores => 'كل المتاجر';

  @override
  String get yourFavourites => 'مفضلتك';

  @override
  String get starredShops => 'المتاجر المحفوظة';

  @override
  String get offersForYou => 'عروض لك';

  @override
  String shopsDelivering(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count متجر توصل إليك',
      many: '$count متجرًا توصل إليك',
      few: '$count متاجر توصل إليك',
      two: 'متجران يوصلان إليك',
      one: 'متجر واحد يوصل إليك',
      zero: 'لا توجد متاجر توصل إليك',
    );
    return '$_temp0';
  }

  @override
  String get noShopsMatch => 'لا توجد متاجر مطابقة';

  @override
  String get tryClearingAFilter => 'جرّب إزالة أحد عوامل التصفية.';

  @override
  String get nothingDeliveringHere => 'لا يوجد توصيل إلى هنا حتى الآن.';

  @override
  String get couldNotLoadStorefront => 'تعذّر تحميل المتاجر';

  @override
  String get tryAgain => 'أعد المحاولة';

  @override
  String get filterOffers => 'العروض';

  @override
  String get filterUnder30 => 'أقل من ٣٠ دقيقة';

  @override
  String get filterFreeDelivery => 'توصيل مجاني';

  @override
  String get filterHighlyRated => '٤٫٥ فأكثر';

  @override
  String get clear => 'مسح';

  @override
  String get statusOpen => 'مفتوح';

  @override
  String get statusBusy => 'مزدحم';

  @override
  String get statusClosingSoon => 'يغلق قريبًا';

  @override
  String get statusClosed => 'مغلق';

  @override
  String get ratingNew => 'جديد';

  @override
  String get freeDelivery => 'توصيل مجاني';

  @override
  String deliveryFeeLabel(String amount) {
    return 'توصيل $amount';
  }

  @override
  String etaRange(int from, int to) {
    return '$from-$to دقيقة';
  }

  @override
  String get tabShop => 'التسوق';

  @override
  String get tabAisles => 'الأقسام';

  @override
  String get tabOffers => 'العروض';

  @override
  String get tabBuyAgain => 'اطلب مجددًا';

  @override
  String get everything => 'الكل';

  @override
  String itemCount(int count) {
    return '$count منتج';
  }

  @override
  String get add => 'أضف';

  @override
  String get nothingOnShelves => 'لا توجد منتجات بعد';

  @override
  String get nothingInAisle => 'لا يوجد شيء في هذا القسم';

  @override
  String get noOffersHere => 'لا توجد عروض حاليًا';

  @override
  String get noHistoryHere => 'لا يوجد شيء من هذا المتجر في سجلك';

  @override
  String get appliesEverywhere => 'ينطبق على كل المتاجر';

  @override
  String get required => 'مطلوب';

  @override
  String get optional => 'اختياري';

  @override
  String get soldOut => 'نفدت الكمية';

  @override
  String addWithTotal(String total) {
    return 'أضف · $total';
  }

  @override
  String get basket => 'السلة';

  @override
  String get basketEmpty => 'سلتك فارغة';

  @override
  String get subtotal => 'المجموع الفرعي';

  @override
  String get delivery => 'التوصيل';

  @override
  String get total => 'الإجمالي';

  @override
  String get free => 'مجاني';

  @override
  String get checkout => 'إتمام الطلب';

  @override
  String checkoutWithTotal(String total) {
    return 'إتمام الطلب · $total';
  }

  @override
  String get minimumNotReached => 'لم يتم بلوغ الحد الأدنى';

  @override
  String minimumExplanation(String minimum, String shortfall) {
    return 'الحد الأدنى لهذا المتجر $minimum — أضف $shortfall أخرى.';
  }

  @override
  String get viewBasket => 'عرض السلة';

  @override
  String get startNewBasket => 'بدء سلة جديدة؟';

  @override
  String basketFromAnotherShop(String shop) {
    return 'سلتك تحتوي على منتجات من $shop. يمكننا التوصيل من متجر واحد فقط في كل مرة.';
  }

  @override
  String get keepIt => 'الاحتفاظ بها';

  @override
  String get startHere => 'ابدأ من هنا';

  @override
  String get payment => 'الدفع';

  @override
  String get payWithCash => 'نقدًا عند الاستلام';

  @override
  String get payWithCard => 'بطاقة';

  @override
  String get paidWith => 'الدفع بواسطة';

  @override
  String get orderDetails => 'تفاصيل الطلب';

  @override
  String get yourOrder => 'طلبك';

  @override
  String get reorder => 'اطلب مجددًا';

  @override
  String deliveredOn(String when) {
    return 'تم التوصيل في: $when';
  }

  @override
  String placedOn(String when) {
    return 'تم الطلب في: $when';
  }

  @override
  String get deliveryCharge => 'رسوم التوصيل';

  @override
  String get back => 'رجوع';

  @override
  String get couldNotLoadOrder => 'تعذّر تحميل هذا الطلب';

  @override
  String get noOrdersYet => 'لا توجد طلبات بعد';

  @override
  String get tracking => 'التتبع';

  @override
  String get live => 'منشور';

  @override
  String get stepPlaced => 'تم الطلب';

  @override
  String get stepAccepted => 'تم القبول';

  @override
  String get stepPreparing => 'قيد التحضير';

  @override
  String get stepReady => 'جاهز';

  @override
  String get stepOnTheWay => 'في الطريق';

  @override
  String get stepDelivered => 'تم التوصيل';

  @override
  String get waitingForRider => 'بانتظار أول موقع للسائق.';

  @override
  String get locationAfterPickup => 'يظهر موقع السائق بعد استلام طلبك.';

  @override
  String get fixes => 'التحديثات';

  @override
  String get travelled => 'المسافة';

  @override
  String get lastSeen => 'آخر ظهور';

  @override
  String get rateYourOrder => 'قيّم طلبك';

  @override
  String get yourRating => 'تقييمك';

  @override
  String get leaveAComment => 'اكتب تعليقًا (اختياري)';

  @override
  String get submitReview => 'إرسال';

  @override
  String get reviews => 'التقييمات';

  @override
  String get noReviewsYet => 'لا توجد تقييمات بعد';

  @override
  String get butler => 'الخدمة الشخصية';

  @override
  String get butlerTagline => 'أي شيء يمكن حمله على دراجة';

  @override
  String get butlerBlurb =>
      'أخبرنا بما تحتاجه ومن أين. سيشتريه المتسوق ويوصله إليك.';

  @override
  String get butlerPrompt => 'تحتاج شيئًا غير موجود هنا؟ سنشتريه لك.';

  @override
  String get whatDoYouNeed => 'ما الذي تحتاجه؟';

  @override
  String get whereFromOptional => 'من أين؟ (اختياري)';

  @override
  String get budgetCapOptional => 'الحد الأقصى للميزانية (اختياري)';

  @override
  String get requestAButler => 'اطلب خدمة شخصية';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get nothingYet => 'لا يوجد شيء بعد';

  @override
  String get orderUpdatesHere => 'ستظهر تحديثات الطلب هنا.';

  @override
  String get language => 'اللغة';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get splashTagline => 'بقالة ومأكولات وأكثر — توصيل إلى بابك.';

  @override
  String get signInFailed => 'تعذّر تسجيل دخولك.';

  @override
  String get account => 'الحساب';

  @override
  String get navAccount => 'الحساب';

  @override
  String get signOutConfirm => 'ستحتاج إلى تسجيل الدخول مجددًا للطلب.';

  @override
  String get profile => 'الملف';

  @override
  String get roles => 'الأدوار';

  @override
  String get selectRequiredOptions => 'اختر الخيارات المطلوبة';

  @override
  String orderPlacedToast(String id, String total) {
    return 'تم تقديم الطلب رقم $id · $total';
  }

  @override
  String get deliveryAddress => 'عنوان التوصيل';

  @override
  String get addressRequired => 'نحتاج إلى عنوان لتوصيل طلبك';

  @override
  String get contactPhoneOptional => 'رقم هاتف للتواصل (اختياري)';

  @override
  String get merchantNotesOptional => 'ملاحظات للمتجر (اختياري)';

  @override
  String get couldNotLoadShop => 'تعذّر تحميل هذا المتجر';

  @override
  String get couldNotLoadMore => 'تعذّر تحميل المزيد — حاول مرة أخرى';

  @override
  String chooseUpTo(int count, String group) {
    return 'اختر حتى $count من $group';
  }

  @override
  String get cancelThisOrder => 'إلغاء هذا الطلب؟';

  @override
  String get cancelOrder => 'إلغاء الطلب';

  @override
  String get cancel => 'إلغاء';

  @override
  String get couldNotLoadOrders => 'تعذّر تحميل طلباتك.';

  @override
  String get browseAndPlaceFirst => 'تصفّح المتاجر وقدّم طلبك الأول.';

  @override
  String get replaceYourBasket => 'استبدال سلتك؟';

  @override
  String basketFromShopReplace(String shop) {
    return 'سلتك تحتوي على أصناف من $shop. إعادة الطلب ستستبدلها.';
  }

  @override
  String get replace => 'استبدال';

  @override
  String openStore(String store) {
    return 'افتح $store';
  }

  @override
  String get markAllRead => 'تعليم الكل كمقروء';

  @override
  String get couldNotLoadNotifications => 'تعذّر تحميل التنبيهات';

  @override
  String get pullDownToTryAgain => 'اسحب للأسفل للمحاولة مرة أخرى.';

  @override
  String get setAddressFirst => 'حدّد عنوان التوصيل أولاً';

  @override
  String get whatAreWeMoving => 'ما الذي ننقله؟';

  @override
  String get pickUpFrom => 'الاستلام من';

  @override
  String get whoReceivesItOptional => 'من سيستلمه؟ (اختياري)';

  @override
  String get buyMeSomething => 'اشترِ لي شيئًا';

  @override
  String get aShopperBuysIt => 'يشتريه المتسوّق لك';

  @override
  String get deliverYourStuff => 'وصّل أغراضك';

  @override
  String get youAlreadyHaveIt => 'الغرض لديك بالفعل';

  @override
  String get yourErrands => 'مهامك';

  @override
  String get couldNotLoadErrands => 'تعذّر تحميل مهامك';

  @override
  String get noThanks => 'لا شكرًا';

  @override
  String payAmount(String amount) {
    return 'ادفع $amount';
  }

  @override
  String get trackIt => 'تتبّعه';

  @override
  String get whatDidItCost => 'كم كانت التكلفة؟';

  @override
  String cappedAt(String amount) {
    return 'الحد الأقصى المحدّد $amount';
  }

  @override
  String get goodsTotal => 'إجمالي المشتريات';

  @override
  String get receiptNumberOptional => 'رقم الإيصال (اختياري)';

  @override
  String get sendForApproval => 'أرسل للموافقة';

  @override
  String get noErrandsWaiting => 'لا توجد مهام في الانتظار.';

  @override
  String get nothingToClaim => 'لا يوجد شيء بانتظار الاستلام.';

  @override
  String get claim => 'استلام';

  @override
  String get reportWhatItCost => 'أبلغ عن التكلفة';

  @override
  String get deliveries => 'التوصيلات';

  @override
  String contactLabel(String phone) {
    return 'للتواصل: $phone';
  }

  @override
  String get couldNotUpdateFavourites => 'تعذّر تحديث مفضلتك.';

  @override
  String get itemNoLongerAvailable => 'أحد هذه الأصناف لم يعد متوفرًا.';

  @override
  String get checkDeliveryDetails => 'يرجى التحقق من تفاصيل التوصيل.';

  @override
  String get couldNotPlaceOrder => 'تعذّر تقديم الطلب. حاول مرة أخرى.';

  @override
  String get placing => 'جارٍ التقديم…';

  @override
  String placeOrderWithTotal(String total) {
    return 'قدّم الطلب · $total';
  }

  @override
  String get nothingStillAvailable =>
      'لا يوجد شيء من هذا الطلب ما زال متوفرًا.';

  @override
  String addedToBasket(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count صنف إلى سلتك',
      many: 'تمت إضافة $count صنفًا إلى سلتك',
      few: 'تمت إضافة $count أصناف إلى سلتك',
      two: 'تمت إضافة صنفين إلى سلتك',
      one: 'تمت إضافة صنف واحد إلى سلتك',
      zero: 'لم يُضف شيء إلى سلتك',
    );
    return '$_temp0';
  }

  @override
  String addedSomeMissing(int added, int missing) {
    return 'تمت إضافة $added؛ $missing لم يعد متوفرًا';
  }

  @override
  String get couldNotReorder => 'تعذّرت إعادة الطلب الآن.';

  @override
  String get reorderWillReplace => 'إعادة الطلب ستبدأ سلة جديدة.';

  @override
  String setByStoreCharged(String store) {
    return 'يحدّدها $store وتُحصّل عند التوصيل.';
  }

  @override
  String get cancelBeforeAccepted =>
      'يمكنك الإلغاء قبل قبول المتجر للطلب فقط. لا يمكن التراجع عن هذا.';

  @override
  String get cancelledByCustomer => 'أُلغي من قبل العميل';

  @override
  String get tooLateToCancel => 'فات الأوان — بدأ المتجر بتحضير هذا الطلب.';

  @override
  String get couldNotCancelOrder => 'تعذّر إلغاء الطلب.';

  @override
  String riderAt(String lat, String lng) {
    return 'السائق عند $lat، $lng';
  }

  @override
  String get couldNotPriceCombination => 'تعذّر تسعير هذا الاختيار.';

  @override
  String optionSoldOut(String name) {
    return '$name — نفدت الكمية';
  }

  @override
  String addToReachMinimum(String amount) {
    return 'أضف $amount للوصول إلى الحد الأدنى';
  }

  @override
  String get removeFromFavourites => 'إزالة من المفضلة';

  @override
  String get addToFavourites => 'إضافة إلى المفضلة';

  @override
  String minOrderLabel(String amount) {
    return 'الحد الأدنى $amount';
  }

  @override
  String closesAtLabel(String when) {
    return 'يغلق $when';
  }

  @override
  String get noAislesYet => 'لا توجد أقسام في هذا المتجر بعد';

  @override
  String get signInToSeeHistory => 'سجّل الدخول لترى ما طلبته سابقًا';

  @override
  String tabAislesCount(int count) {
    return 'الأقسام ($count)';
  }

  @override
  String tabOffersCount(int count) {
    return 'العروض ($count)';
  }

  @override
  String get basketFromAnotherShopSingle =>
      'يمكننا التوصيل من متجر واحد فقط في كل مرة.';

  @override
  String get basketHasOtherShopItems =>
      'تحتوي هذه السلة على أصناف من متجر آخر.';

  @override
  String distanceKm(String km) {
    return '$km كم';
  }

  @override
  String distanceM(String m) {
    return '$m م';
  }

  @override
  String get justNow => 'الآن';

  @override
  String secondsAgo(int count) {
    return 'منذ $count ثانية';
  }

  @override
  String minutesAgo(int count) {
    return 'منذ $count دقيقة';
  }

  @override
  String hoursAgo(int count) {
    return 'منذ $count ساعة';
  }

  @override
  String daysAgo(int count) {
    return 'منذ $count يوم';
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
      'تم الإرسال. سيستلمها المتسوّق ويخبرك بالتكلفة قبل الدفع.';

  @override
  String get sentMoveConfirmation => 'تم الإرسال. سيأتي السائق لاستلامها.';

  @override
  String get cannotRequestErrands => 'هذا الحساب لا يمكنه طلب المهام';

  @override
  String get couldNotSendRequest => 'تعذّر إرسال الطلب';

  @override
  String get butlerMoveTagline => 'أرسل شيئًا عبر المدينة';

  @override
  String get butlerMoveBlurb =>
      'الغرض لديك بالفعل؟ يستلمه السائق من عنوان ويسلّمه في عنوان آخر. لا يُشترى شيء.';

  @override
  String get buyHint => 'شاحن هاتف من نوع USB-C وزجاجة مياه';

  @override
  String get buyValidator => 'أضف تفاصيل أكثر ليعرف المتسوّق ما يشتريه';

  @override
  String get whereFromHint => 'أي صيدلية قرب الحمرا';

  @override
  String get budgetValidator => 'أدخل رقمًا أو اتركه فارغًا';

  @override
  String get moveHint => 'ظرف A4 يحتوي مستندات، لا شيء قابل للكسر';

  @override
  String get moveValidator => 'أضف تفاصيل أكثر ليعرف السائق ما يتوقعه';

  @override
  String get pickUpHint => 'شارع كليمنصو ٨، مكتب الاستقبال';

  @override
  String get pickUpValidator => 'من أين يستلمها السائق؟';

  @override
  String get receiverHint => 'الاسم ورقم الهاتف';

  @override
  String get requestAPickup => 'اطلب استلامًا';

  @override
  String errandFeeBuy(String fee) {
    return 'رسوم المهمة $fee. يخبرك المتسوّق بتكلفة المشتريات قبل أن تدفع أي شيء.';
  }

  @override
  String errandFeeMove(String fee) {
    return 'رسوم المهمة $fee. لا يُشترى شيء، لذا هذا هو السعر كاملًا.';
  }

  @override
  String get dropOffAt => 'التسليم في';

  @override
  String get thatDidNotWork => 'لم ينجح ذلك';

  @override
  String aboveYourCap(String cap) {
    return 'هذا أعلى من الحد الذي حدّدته وهو $cap.';
  }

  @override
  String get declined => 'مرفوض';

  @override
  String get approvedOnItsWay => 'تمت الموافقة — في الطريق إليك';

  @override
  String get cancelled => 'ملغى';

  @override
  String waitingForShopper(String fee) {
    return 'بانتظار من يستلمها · الرسوم $fee';
  }

  @override
  String get shopperIsOnIt => 'المتسوّق يعمل عليها. سيخبرك بالتكلفة.';

  @override
  String riderOnTheWayToCollect(String total) {
    return 'السائق في طريقه لاستلامها · $total';
  }

  @override
  String goodsPlusFee(String goods, String fee, String total) {
    return 'المشتريات $goods + الرسوم $fee = $total';
  }

  @override
  String agreedAt(String total) {
    return 'تم الاتفاق على $total';
  }

  @override
  String get youDeclinedThisPrice => 'لقد رفضت هذا السعر';

  @override
  String get nobodyPickedThisUp => 'لم يستلمها أحد';

  @override
  String get butlerStatusOpen => 'متاحة';

  @override
  String get butlerStatusClaimed => 'مستلمة';

  @override
  String get butlerStatusYourCall => 'بانتظار قرارك';

  @override
  String get butlerStatusAgreed => 'متفق عليها';

  @override
  String get butlerStatusExpired => 'منتهية';

  @override
  String get somebodyElseClaimed => 'استلمها شخص آخر';

  @override
  String get whatYouPaidBeforeFee => 'ما دفعته، قبل رسوم المهمة';

  @override
  String get sentForApproval => 'تم الإرسال. سيوافقون على السعر قبل التسليم.';

  @override
  String cappedAtBudget(String amount) {
    return 'حدّدوا الحد الأقصى بـ $amount';
  }

  @override
  String get yours => 'لك';

  @override
  String get buyAndBring => 'اشترِ وأحضر';

  @override
  String get collectAndDrop => 'استلم وسلّم';

  @override
  String get from => 'من';

  @override
  String get collectAndDropInstruction =>
      'استلمها وسلّمها. ستجدها في تبويب التوصيلات.';

  @override
  String get waitingOnApproval => 'بانتظار موافقتهم. لا تسلّمها قبل ذلك.';

  @override
  String get approvedDeliverIt => 'تمت الموافقة. سلّمها من تبويب التوصيلات.';

  @override
  String headingWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String availableWithCount(int count) {
    return 'المتاحة ($count)';
  }

  @override
  String mineWithCount(int count) {
    return 'الخاصة بي ($count)';
  }

  @override
  String get errands => 'المهام';

  @override
  String get nothingWaitingForPickup => 'لا يوجد شيء بانتظار الاستلام الآن.';

  @override
  String get noActiveDeliveries => 'ليس لديك توصيلات نشطة.';

  @override
  String get anotherRiderClaimedIt => 'استلمها سائق آخر قبلك.';

  @override
  String get orderAlreadyMovedOn => 'هذا الطلب تجاوز هذه المرحلة.';

  @override
  String contactPhone(String phone) {
    return 'للتواصل: $phone';
  }

  @override
  String get statusReadyForPickup => 'جاهز للاستلام';

  @override
  String get statusCancelled => 'ملغى';

  @override
  String get actionAccept => 'قبول';

  @override
  String get actionPrepare => 'ابدأ التحضير';

  @override
  String get actionMarkReady => 'حدّده كجاهز';

  @override
  String get actionClaim => 'استلام';

  @override
  String get actionPickedUp => 'تم الاستلام';

  @override
  String get actionDelivered => 'تم التسليم';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get verticalRestaurants => 'مطاعم';

  @override
  String get verticalCoffee => 'قهوة';

  @override
  String get verticalGroceries => 'بقالة';

  @override
  String get verticalConvenience => 'متاجر صغيرة';

  @override
  String get verticalPharmacy => 'صيدلية';

  @override
  String get verticalElectronics => 'إلكترونيات';

  @override
  String get verticalFlowersGifts => 'زهور وهدايا';

  @override
  String orderPlacedToastShort(String ref, String total) {
    return 'تم تقديم الطلب رقم $ref · $total';
  }

  @override
  String minimumExplanationFull(String minimum, String shortfall) {
    return 'الحد الأدنى لهذا المتجر $minimum — أضف $shortfall أخرى.';
  }

  @override
  String addToReachMinimumShort(String amount) {
    return 'أضف $amount للوصول إلى الحد الأدنى';
  }

  @override
  String actionFailed(String action) {
    return 'تعذّر $action.';
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
      other: '$count صنف',
      many: '$count صنفًا',
      few: '$count أصناف',
      two: 'صنفان',
      one: 'صنف واحد',
      zero: 'لا أصناف',
    );
    return '$_temp0';
  }

  @override
  String riderAtShort(String lat, String lng) {
    return 'السائق عند $lat، $lng';
  }

  @override
  String waitingOnApprovalOf(String total) {
    return 'بانتظار موافقتهم على $total. لا تسلّمها قبل ذلك.';
  }

  @override
  String get aislesCount => 'الأقسام';

  @override
  String get signInPrompt => 'سجّل الدخول لترى ما طلبته سابقًا';

  @override
  String get merchantPortal => 'بوابة التاجر';

  @override
  String get navProducts => 'المنتجات';

  @override
  String get navDelivery => 'التوصيل';

  @override
  String get navMyShop => 'متجري';

  @override
  String get manageYourCatalog => 'أدر قائمة منتجاتك';

  @override
  String get signingIn => 'جارٍ تسجيل الدخول…';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get notAMerchant => 'هذا الحساب غير مسجّل كتاجر.';

  @override
  String get signInAsSomeoneElse => 'سجّل الدخول بحساب آخر';

  @override
  String get carrierNotAvailableToYou => 'شركة التوصيل هذه غير متاحة لك';

  @override
  String couldNotLoadCarriers(String error) {
    return 'تعذّر تحميل شركات التوصيل: $error';
  }

  @override
  String get whoCarriesYourOrders => 'من يوصّل طلباتك';

  @override
  String get whoCarriesBlurb =>
      'من يوصّل طلباتك. يسري هذا من لحظة جهوز الطلب للاستلام — أما الطلبات التي في طريقها فتبقى مع شركة التوصيل التي خرجت معها.';

  @override
  String get yourOwnDrivers => 'سائقوك';

  @override
  String get fleetRidersBlurb =>
      'تضيف المنصّة السائقين إلى أسطولك. الأسطول الذي لا سائق فيه لا يستطيع استلام شيء.';

  @override
  String get whenCarrierCannotTake => 'عندما لا تستطيع شركتك أخذ الطلب';

  @override
  String get letThePlatformChoose => 'دع المنصّة تختار';

  @override
  String get whoeverIsAvailable =>
      'أي شركة متاحة تستطيع أخذ المهمة. هذا هو الخيار الافتراضي.';

  @override
  String get thePlatformWillChoose => 'ستختار المنصّة';

  @override
  String notTakingWorkNow(String kind) {
    return '$kind  ·  لا تقبل العمل حاليًا';
  }

  @override
  String carrierWillCarry(String name) {
    return '$name ستوصّل طلباتك';
  }

  @override
  String get ownDriversBlurb =>
      'إن كان لديك سائقون، يمكنهم توصيل طلباتك وتتدخّل المنصّة فقط عندما ينشغلون.';

  @override
  String get yourFleetIsSetUp => 'تم إعداد أسطولك';

  @override
  String get setUpMyOwnDrivers => 'أعدّ سائقيّ الخاصين';

  @override
  String get anotherCarrierMayStepIn => 'يمكن لشركة أخرى أن تتدخّل';

  @override
  String get onlyYourChosenCarrier => 'ستُستخدم شركتك المختارة فقط';

  @override
  String get letSomeoneElseStepIn => 'اسمح لغيرها بالتدخّل';

  @override
  String get onlyAppliesOnceChosen => 'يسري هذا فقط بعد اختيارك لشركة توصيل.';

  @override
  String get fallbackOnBlurb =>
      'إن لم تستطع شركتك أخذ الطلب، ستأخذه أخرى. تخرج الطلبات متأخرة بدل ألا تخرج أبدًا.';

  @override
  String get fallbackOffBlurb =>
      'تنتظر الطلبات شركتك. لا شيء يخرج مع غيرها — والطلب الذي لا تستطيع أخذه يبقى عندك.';

  @override
  String get cancelledByMerchant => 'أُلغي من قبل التاجر';

  @override
  String get orderAlreadyMovedRefreshing =>
      'هذا الطلب تجاوز هذه المرحلة. جارٍ التحديث.';

  @override
  String get columnToAccept => 'بانتظار القبول';

  @override
  String get columnPreparing => 'قيد التحضير';

  @override
  String get columnAwaitingRider => 'بانتظار سائق';

  @override
  String get columnDelivered => 'تم التسليم';

  @override
  String get showCompleted => 'أظهر المكتملة';

  @override
  String get refresh => 'تحديث';

  @override
  String updatesEvery(int seconds) {
    return 'يتحدّث كل $seconds ثانية';
  }

  @override
  String get liveOrders => 'الطلبات الجارية';

  @override
  String get couldNotLoadOrdersShort => 'تعذّر تحميل الطلبات.';

  @override
  String get noOrdersYetMerchant => 'لا توجد طلبات بعد.';

  @override
  String get noOrdersNeedingAttention => 'لا توجد طلبات تحتاج انتباهك.';

  @override
  String get riderAssigned => 'تم تعيين سائق';

  @override
  String noteWithText(String note) {
    return 'ملاحظة: $note';
  }

  @override
  String get saved => 'تم الحفظ';

  @override
  String get couldNotSaveProduct => 'تعذّر حفظ هذا المنتج';

  @override
  String get images => 'الصور';

  @override
  String get uploadFailed => 'فشل الرفع';

  @override
  String get newProduct => 'منتج جديد';

  @override
  String get editProduct => 'تعديل المنتج';

  @override
  String get nameLabel => 'الاسم';

  @override
  String get nameRequired => 'الاسم مطلوب';

  @override
  String get descriptionLabel => 'الوصف';

  @override
  String get priceLabel => 'السعر';

  @override
  String get enterANumber => 'أدخل رقمًا';

  @override
  String get priceMustBePositive => 'يجب أن يكون السعر أكبر من صفر';

  @override
  String get categoryLabel => 'الفئة';

  @override
  String get uncategorised => 'بدون فئة';

  @override
  String get saving => 'جارٍ الحفظ…';

  @override
  String get save => 'حفظ';

  @override
  String get saveProductFirst => 'احفظ المنتج أولًا ثم أضف الصور.';

  @override
  String get needsAPhotoToPublish =>
      'يحتاج المنتج إلى صورة واحدة على الأقل قبل نشره.';

  @override
  String get addPhoto => 'أضف صورة';

  @override
  String get remove => 'إزالة';

  @override
  String get couldNotPublishProduct => 'تعذّر نشر هذا المنتج';

  @override
  String get archiveThisProduct => 'أرشفة هذا المنتج؟';

  @override
  String archiveConfirm(String name) {
    return 'سيُسحب \"$name\" من قائمة المنتجات. الطلبات القائمة التي تشير إليه لن تتأثر.';
  }

  @override
  String get archive => 'أرشفة';

  @override
  String get myProducts => 'منتجاتي';

  @override
  String get onSale => 'معروضة';

  @override
  String productsTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count منتج',
      many: '$count منتجًا',
      few: '$count منتجات',
      two: 'منتجان',
      one: 'منتج واحد',
      zero: 'لا منتجات',
    );
    return '$_temp0';
  }

  @override
  String get drafts => 'المسوّدات';

  @override
  String get noPhoto => 'لا صورة';

  @override
  String photoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة',
      many: '$count صورة',
      few: '$count صور',
      two: 'صورتان',
      one: 'صورة واحدة',
      zero: 'لا صور',
    );
    return '$_temp0';
  }

  @override
  String get archived => 'مؤرشفة';

  @override
  String get yourProducts => 'منتجاتك';

  @override
  String get publish => 'نشر';

  @override
  String get edit => 'تعديل';

  @override
  String get draft => 'مسوّدة';

  @override
  String get moreActions => 'خيارات أخرى';

  @override
  String get noProductsYet => 'لا منتجات بعد';

  @override
  String get createYourFirstProduct => 'أنشئ منتجك الأول، أضف صورة، ثم انشره.';

  @override
  String get somethingWentWrong => 'حدث خطأ ما';

  @override
  String detailWithRef(String detail, String ref) {
    return '$detail (المرجع: $ref)';
  }

  @override
  String thatDidNotWorkWith(String error) {
    return 'لم ينجح ذلك: $error';
  }

  @override
  String get shopSaved => 'تم حفظ المتجر';

  @override
  String get couldNotLoadYourShop => 'تعذّر تحميل متجرك';

  @override
  String get noShopYet => 'لا يوجد متجر بعد';

  @override
  String get shopCreatedAutomatically =>
      'أضف منتجك الأول ويُنشأ لك متجر تلقائيًا.';

  @override
  String get howYourShopAppears => 'كيف يظهر متجرك للعملاء';

  @override
  String get shopName => 'اسم المتجر';

  @override
  String get tagline => 'العبارة التعريفية';

  @override
  String get taglineHint => 'مشاوي على الفحم ومازة طوال اليوم';

  @override
  String get tags => 'الوسوم';

  @override
  String get tagsHint => 'لبناني، مشاوي، مازة (مفصولة بفواصل)';

  @override
  String get addressLabel => 'العنوان';

  @override
  String get pictures => 'الصور';

  @override
  String get logoRecognisedBy => 'شعارك هو ما يعرفك به العملاء في نتائج البحث';

  @override
  String get logo => 'الشعار';

  @override
  String get logoHint => 'الشكل المربّع هو الأفضل. يظهر على كل بطاقة متجر.';

  @override
  String get cover => 'صورة الغلاف';

  @override
  String get coverHint => 'عريضة. تظهر خلف ترويسة متجرك.';

  @override
  String get generatedTileBlurb =>
      'إلى أن ترفع صورة، يرى العملاء بطاقة مولّدة تحمل أحرف اسمك — متناسقة ولائقة، لكنها ليست صورتك.';

  @override
  String get whatCustomersAreCharged =>
      'ما يُحتسب على العملاء وما يُقال لهم أن يتوقعوه';

  @override
  String get deliveryFeeLabelMerchant => 'رسوم التوصيل';

  @override
  String get minimumOrder => 'الحد الأدنى للطلب';

  @override
  String get etaFromMin => 'المدة من (دقيقة)';

  @override
  String get etaToMin => 'المدة إلى (دقيقة)';

  @override
  String get serverAppliesTerms =>
      'يطبّق الخادم الاثنين عند تقديم الطلب — تُرفض السلة التي تقلّ عن الحد الأدنى، وتُضاف الرسوم إلى إجمالي العميل.';

  @override
  String get openingHours => 'ساعات العمل';

  @override
  String get openingHoursBlurb =>
      'يظهر متجرك كمفتوح أو يوشك على الإغلاق أو مغلق بناءً على هذه الساعات';

  @override
  String get addASecondWindow => 'أضف فترة ثانية';

  @override
  String get secondWindowBlurb =>
      'أضف فترة ثانية لليوم لتقسيم ساعاتك — مثلًا فترة صباحية وأخرى مسائية، مع إغلاق بينهما.';

  @override
  String get saveChanges => 'حفظ التغييرات';

  @override
  String get listedOnStorefront => 'مدرج في واجهة المتاجر';

  @override
  String get notListedYet => 'غير مدرج بعد';

  @override
  String get markedBusy30 => 'تم تحديده كمشغول لمدة ٣٠ دقيقة';

  @override
  String get busy30m => 'مشغول ٣٠ د';

  @override
  String get noLongerBusy => 'لم يعد محدّدًا كمشغول';

  @override
  String get notBusy => 'غير مشغول';

  @override
  String get yourShopIsLive => 'متجرك يعمل الآن';

  @override
  String get opens => 'يفتح';

  @override
  String get closes => 'يغلق';

  @override
  String get removeThisWindow => 'احذف هذه الفترة';

  @override
  String get upload => 'رفع';

  @override
  String labelRemoved(String label) {
    return 'تمت إزالة $label';
  }

  @override
  String get pictureUpdated => 'تم تحديث الصورة';

  @override
  String get requiredField => 'مطلوب';

  @override
  String get aNumber => 'رقم';

  @override
  String get cannotBeNegative => 'لا يمكن أن يكون سالبًا';

  @override
  String get signInFailedShort => 'فشل تسجيل الدخول';

  @override
  String get providerKindInHouse => 'أسطول المنصّة';

  @override
  String get providerKindCompany => 'شركة توصيل';

  @override
  String get providerKindOwnDrivers => 'سائقونك';

  @override
  String get carrierPortal => 'بوابة شركة التوصيل';

  @override
  String get carrierPortalTagline =>
      'شركتك وأسطولك وحجم العمل الذي يُعرض عليك.';

  @override
  String get notACarrier => 'هذا الحساب غير مسجّل لدى شركة توصيل.';

  @override
  String get noCompanyYet => 'لا توجد شركة مرتبطة بهذا الحساب بعد';

  @override
  String get askThePlatformToAttachYou =>
      'اطلب من المنصّة ربط حسابك بشركة التوصيل الخاصة بك.';

  @override
  String get howYouAreDoing => 'أداؤك';

  @override
  String get deliveryScore => 'تقييم التوصيل';

  @override
  String get tooEarlyToTell => 'من المبكر الحكم';

  @override
  String get ordersDelivered => 'الطلبات المسلّمة';

  @override
  String get timeToClaim => 'وقت الاستلام';

  @override
  String get timeOnTheRoad => 'الوقت على الطريق';

  @override
  String get scoreBlurb =>
      'يحدّد هذا التقييم حجم العمل الذي يُعرض عليك عندما يترك التاجر الاختيار للمنصّة. تسليم ما تستلمه هو الأهم، ثم سرعة الاستلام.';

  @override
  String get scoreProvisionalBlurb =>
      'ما زلنا نمنحك العمل بحسن النية. سيصبح التقييم تقييمك أنت بدل أن يكون افتراضًا بعد بضعة طلبات أخرى.';

  @override
  String get takingOrders => 'استقبال الطلبات';

  @override
  String get takingWork => 'يستقبل العمل';

  @override
  String get youAreTakingOrders => 'أنت تستقبل الطلبات';

  @override
  String get youAreNotTakingOrders => 'أنت لا تستقبل الطلبات';

  @override
  String get pauseExplanation =>
      'الإيقاف المؤقت يمنع إرسال طلبات جديدة إليك. أما ما هو مُسنَد إلى سائقيك فلا يتأثر.';

  @override
  String get suspendedByPlatform =>
      'أوقفت المنصّة شركتك. لا يمكنك استئناف العمل بنفسك — تواصل مع المنصّة.';

  @override
  String get pauseNewOrders => 'أوقف الطلبات الجديدة';

  @override
  String get startTakingOrders => 'ابدأ استقبال الطلبات';

  @override
  String get pausedNoNewOrders => 'تم الإيقاف. لن تُرسل إليك طلبات جديدة.';

  @override
  String get resumedTakingOrders => 'عدت إلى استقبال الطلبات.';

  @override
  String get yourFleet => 'أسطولك';

  @override
  String get noRidersBlurb =>
      'لا يوجد لديك سائقون. تبدو شركتك متاحة ولا تستطيع استلام شيء، وهي أكثر الحالات إرباكًا لعدم وصول العمل — اطلب من المنصّة إضافة سائقيك.';

  @override
  String get ridersAddedByPlatform => 'تضيف المنصّة السائقين إلى أسطولك.';

  @override
  String get gettingPaid => 'استلام المستحقات';

  @override
  String get noPayoutAccount => 'لا يوجد حساب لاستلام المستحقات';

  @override
  String get payoutNeedsAttentionBlurb =>
      'لم يؤكّد المصرف هذا الحساب. قد تفشل التحويلات إليك — يمكن للمنصّة إعادة التحقق منه.';

  @override
  String get area => 'المنطقة';

  @override
  String get pickYourArea => 'اختر منطقتك لنعرف من يستطيع الوصول إليك';

  @override
  String feeToArea(String area, String fee) {
    return 'التوصيل إلى $area: $fee';
  }

  @override
  String doesNotDeliverToArea(String area) {
    return 'هذا المتجر لا يوصّل إلى $area';
  }

  @override
  String get deliveryAreas => 'مناطق التوصيل';

  @override
  String get whereYouDeliver => 'إلى أين توصّل، وكم تتقاضى للوصول إلى هناك';

  @override
  String get flatFeeEverywhere => 'أنت تتقاضى رسومًا واحدة لكل المناطق';

  @override
  String get flatFeeExplanation =>
      'أضف منطقة أدناه لتسعّر حسب المسافة. قبل ذلك، كل طلب يكلّف رسوم التوصيل المعتادة وأنت توصّل إلى أي مكان.';

  @override
  String get addAnArea => 'أضف منطقة';

  @override
  String get feeToHere => 'الرسوم';

  @override
  String get minimumHere => 'الحد الأدنى';

  @override
  String get extraMinutes => 'دقائق إضافية';

  @override
  String get usesShopMinimum => 'يستخدم الحد الأدنى لمتجرك';

  @override
  String get stopDelivering => 'أوقف التوصيل هنا';

  @override
  String get areasYouServe => 'المناطق التي توصّل إليها';

  @override
  String get onlyTheseAreas =>
      'أنت توصّل فقط إلى المناطق المدرجة هنا. الطلبات من غيرها تُرفض.';

  @override
  String get manageAreas => 'مناطق التوصيل';

  @override
  String get manageAreasBlurb =>
      'القائمة التي يختار منها العملاء عند إدخال العنوان. تسعّر المتاجر توصيلها لكل منطقة.';

  @override
  String get newArea => 'منطقة جديدة';

  @override
  String get areaName => 'اسم المنطقة';

  @override
  String get regionOptional => 'المحافظة (اختياري)';

  @override
  String get sortOrder => 'الترتيب في القائمة';

  @override
  String get retire => 'إخفاء';

  @override
  String get reinstate => 'إعادة';

  @override
  String get retired => 'مخفية';

  @override
  String get retiredExplanation =>
      'المناطق المخفية تختفي من القائمة لكنها تبقى صالحة للعناوين التي تشير إليها.';

  @override
  String get noAreasYet => 'لا توجد مناطق بعد';

  @override
  String get noAreasBlurb =>
      'قبل إضافة المناطق، يتقاضى كل متجر رسوم توصيل واحدة ويوصّل إلى أي مكان.';

  @override
  String get navWhatsApp => 'واتساب';

  @override
  String get whatsappInbox => 'صندوق واتساب';

  @override
  String get whatsappInboxBlurb =>
      'الزبائن الذين يراسلون متجرك. حوّل ما طلبوه إلى طلبية من هنا مباشرة.';

  @override
  String get noConversations => 'لا رسائل بعد';

  @override
  String get noConversationsBlurb =>
      'عندما يراسل زبون رقمك المربوط، تظهر المحادثة هنا.';

  @override
  String get connectedNumbers => 'الأرقام المربوطة';

  @override
  String get connectNumber => 'اربط رقماً';

  @override
  String get numberId => 'معرّف رقم واتساب';

  @override
  String get numberLabel => 'التسمية';

  @override
  String get displayNumber => 'رقم الهاتف';

  @override
  String get connect => 'اربط';

  @override
  String get disconnect => 'افصل';

  @override
  String get disconnectNumberWarning =>
      'تتوقف الرسائل الجديدة إلى هذا الرقم. تبقى محادثاتك الحالية محفوظة.';

  @override
  String get noNumbersYet => 'لا رقم مربوط';

  @override
  String get noNumbersBlurb => 'اربط رقم واتساب الذي يراسلك عليه زبائنك أصلاً.';

  @override
  String get selectAConversation => 'اختر محادثة';

  @override
  String get selectAConversationBlurb =>
      'اختر شخصاً من القائمة لقراءة ما طلبه.';

  @override
  String get showArchived => 'إظهار المؤرشفة';

  @override
  String get showActive => 'إظهار النشطة';

  @override
  String get typeAReply => 'اكتب رداً';

  @override
  String get sendReply => 'إرسال';

  @override
  String get replyNotSent => 'حُفظ، لكن تعذّر الإرسال';

  @override
  String get voiceNote => 'رسالة صوتية';

  @override
  String get photo => 'صورة';

  @override
  String get document => 'مستند';

  @override
  String get locationPin => 'موقع';

  @override
  String get unsupportedMessage => 'رسالة غير مدعومة';

  @override
  String get startAnOrder => 'ابدأ طلبية';

  @override
  String get theRequest => 'ما طلبوه';

  @override
  String get addItem => 'أضف صنفاً';

  @override
  String get estimate => 'تقدير';

  @override
  String get estimateNote =>
      'تقدير بأسعار اليوم. يُحتسب المجموع النهائي عند التأكيد.';

  @override
  String get deliveryDetails => 'تفاصيل التوصيل';

  @override
  String get orderNotes => 'ملاحظات';

  @override
  String get confirmOrder => 'أكّد الطلبية';

  @override
  String get confirmOrderWarning => 'هذا ينشئ طلبية حقيقية ويحجز سائقاً.';

  @override
  String get discardRequest => 'إلغاء';

  @override
  String get orderPlaced => 'تم إنشاء الطلبية';

  @override
  String get draftDiscarded => 'أُلغيت';

  @override
  String get nothingToOrderYet => 'لم تُضف أصناف بعد';

  @override
  String get nothingToOrderYetBlurb => 'أضف ما طلبه الزبون من قائمتك.';

  @override
  String get chooseOptions => 'اختر الخيارات';

  @override
  String get quantity => 'الكمية';

  @override
  String get addToOrder => 'أضف إلى الطلبية';

  @override
  String get phoneLabel => 'رقم الهاتف';

  @override
  String get budgetExhausted =>
      'نفدت الميزانية. لن تُمنح إعفاءات جديدة حتى يلحق الإيراد.';

  @override
  String deliveryWasFree(String amount) {
    return 'عادةً $amount — تكفّلنا بها';
  }

  @override
  String get noCommissionOnThisOrder => 'بلا عمولة على هذه الطلبية';

  @override
  String get deliveryPaidByPlatform => 'المنصة تكفّلت برسوم التوصيل';

  @override
  String get navCompany => 'الشركة';

  @override
  String get navJobs => 'المهام';

  @override
  String get navEarnings => 'الأرباح';

  @override
  String get jobsTitle => 'مهامك';

  @override
  String get jobsBlurb => 'كل ما يحمله سائقوك، وكل ما سلّموه.';

  @override
  String get noJobsYet => 'لا مهام بعد';

  @override
  String get noJobsBlurb => 'ستظهر هنا الطلبيات المسندة إلى شركتك.';

  @override
  String get earningsTitle => 'الأرباح';

  @override
  String get earned => 'المحقق';

  @override
  String get expected => 'المتوقع';

  @override
  String get jobsDelivered => 'مُسلّمة';

  @override
  String get jobsInFlight => 'قيد التنفيذ';

  @override
  String get savedByOffers => 'وُفّر بالعروض';

  @override
  String earningsWindowNote(int days, String cut) {
    return 'خلال آخر $days يوماً، بعد حصة المنصة البالغة $cut% من كل رسم توصيل.';
  }

  @override
  String get savedByOffersNote =>
      'تنازلت المنصة عن حصتها في بعض توصيلاتك، فاحتفظت بكامل الرسم.';

  @override
  String get expectedNote => 'قيمة العمل الجاري إن اكتمل كله. غير مستحق بعد.';

  @override
  String get yourFeeOnThis => 'رسمك';

  @override
  String get navDashboard => 'لوحة المتابعة';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get continueWithGoogle => 'المتابعة باستخدام Google';

  @override
  String get signInWithAPasscode => 'تسجيل الدخول برمز المرور';

  @override
  String get couldNotSignInWithGoogle => 'لم يكتمل تسجيل الدخول عبر Google.';

  @override
  String get enterYourPasscode => 'أدخل رمز المرور';

  @override
  String get chooseAPasscode => 'اختر رمز مرور';

  @override
  String get confirmYourPasscode => 'أدخله مرة أخرى';

  @override
  String get sixDigitsYouWillUseToSignIn => 'ستة أرقام تستخدمها لتسجيل الدخول';

  @override
  String get passcodeMustBeSixDigits =>
      'يجب أن يتكوّن رمز المرور من ستة أرقام.';

  @override
  String get passcodesDoNotMatch => 'الرمزان غير متطابقين. حاول مرة أخرى.';

  @override
  String get merchantHome => 'متجرك';

  @override
  String get orJoinUs => 'أو';

  @override
  String get sellOrDeliverWithUs => 'انضم إلينا بائعًا أو موصّلًا';

  @override
  String get welcomeBack => 'أهلًا بعودتك';

  @override
  String get usernameOrEmail => 'اسم المستخدم أو البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get hide => 'إخفاء';

  @override
  String get show => 'إظهار';

  @override
  String get noAccountYet => 'جديد هنا؟';

  @override
  String get couldNotReachTheServer =>
      'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.';

  @override
  String get whatIsYourEmail => 'ما بريدك الإلكتروني؟';

  @override
  String get enterAValidEmail => 'أدخل بريدًا إلكترونيًا صحيحًا.';

  @override
  String get lastNameOptional => 'اسم العائلة (اختياري)';

  @override
  String get choosePassword => 'اختر كلمة مرور';

  @override
  String get atLeastEightCharacters => '٨ أحرف على الأقل';

  @override
  String get passwordTooShort => 'استخدم ٨ أحرف على الأقل.';

  @override
  String get deliveryPortal => 'بوابة التوصيل';

  @override
  String get backoffice => 'الإدارة';

  @override
  String get switchArea => 'تبديل البوابة';

  @override
  String get navCategories => 'الفئات';

  @override
  String get navCatalog => 'الكتالوج';

  @override
  String get navBanners => 'اللافتات';

  @override
  String get navOnboarding => 'طلبات الانضمام';

  @override
  String get navCarriers => 'شركات التوصيل';

  @override
  String get navAreas => 'المناطق';

  @override
  String get navFinance => 'المالية';

  @override
  String get navOffers => 'العروض';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get howTradeIsGoing => 'كيف تسير الأعمال';

  @override
  String get howWorkIsGoing => 'كيف يسير العمل';

  @override
  String get ordersToday => 'طلبات اليوم';

  @override
  String get salesToday => 'مبيعات اليوم';

  @override
  String get jobsToday => 'مهام اليوم';

  @override
  String get earnedToday => 'أرباح اليوم';

  @override
  String upOnYesterday(int percent) {
    return 'أعلى بنسبة $percent% عن أمس';
  }

  @override
  String downOnYesterday(int percent) {
    return 'أقل بنسبة $percent% عن أمس';
  }

  @override
  String get sameAsYesterday => 'مثل أمس';

  @override
  String get noneYesterday => 'لا شيء أمس';

  @override
  String get nothingYetToday => 'لا شيء اليوم حتى الآن';

  @override
  String get needsYouNow => 'بانتظارك الآن';

  @override
  String get toAccept => 'بانتظار القبول';

  @override
  String get preparingNow => 'قيد التحضير';

  @override
  String get readyForPickup => 'جاهز للاستلام';

  @override
  String get outForDelivery => 'في الطريق';

  @override
  String get allCaughtUp => 'لا شيء بانتظارك.';

  @override
  String lastDaysHeading(int days) {
    return 'آخر $days يوماً';
  }

  @override
  String get quietSoFar => 'لا حركة في هذه الفترة بعد.';

  @override
  String get noJobsSoFar => 'لا مهام في هذه الفترة بعد.';

  @override
  String get barChartLegend =>
      'الغامق يعني ما تم تسليمه، والفاتح ما طُلب ولم يُسلَّم.';

  @override
  String get ordersInWindow => 'الطلبات';

  @override
  String get deliveredInWindow => 'المُسلَّمة';

  @override
  String get salesInWindow => 'المبيعات';

  @override
  String get feesInWindow => 'رسوم المنصة';

  @override
  String feesInWindowNote(String cut) {
    return '$cut% من المبيعات المُسلَّمة.';
  }

  @override
  String get bestSellers => 'الأكثر مبيعاً';

  @override
  String get nothingSoldYet => 'لم يُبَع شيء في هذه الفترة بعد.';

  @override
  String soldQty(int qty) {
    return '$qty مبيعاً';
  }

  @override
  String get savedForYou => 'وفّرته العروض';

  @override
  String get savedForYouNote => 'تنازلت المنصة عن حصتها في بعض طلباتك.';

  @override
  String get navApplicants => 'المتقدمون';

  @override
  String waitingOnYou(int count) {
    return '$count بانتظار ردك';
  }

  @override
  String get everyoneWhoApplied => 'كل من تقدّم للعمل معك.';

  @override
  String get waitingOnly => 'بانتظار الرد فقط';

  @override
  String get everyone => 'الجميع';

  @override
  String get nobodyWaiting => 'لا أحد بانتظار ردك.';

  @override
  String get nobodyHasApplied => 'لم يتقدّم أحد بعد.';

  @override
  String get hiringAlsoCreatesTheirAccount =>
      'قبوله يُنشئ حسابه ويضيفه إلى أسطولك، ليتمكن من استلام المهام فوراً.';

  @override
  String get addToMyFleet => 'أضِفه إلى أسطولي';

  @override
  String get turnDown => 'اعتذر';

  @override
  String turnDownName(String name) {
    return 'الاعتذار لـ $name';
  }

  @override
  String get theyAreSentThisWordForWord =>
      'سيصله هذا النص حرفياً. اذكر ما الذي يجب أن يتغيّر.';

  @override
  String riderAdded(String name) {
    return '$name أصبح ضمن أسطولك. أرسلنا له طريقة تسجيل الدخول.';
  }

  @override
  String applicantTurnedDown(String name) {
    return 'تم إبلاغ $name.';
  }

  @override
  String turnedDownBecause(String reason) {
    return 'تم الاعتذار: $reason';
  }

  @override
  String get onYourFleetNow => 'ضمن أسطولك. يمكن إرسال المهام إليه.';

  @override
  String get thatDidNotGoThrough => 'لم تتم العملية. حاول مرة أخرى.';

  @override
  String get wantToRideForACompany => 'تريد العمل مع شركة توصيل؟';

  @override
  String get rideWithUs => 'اعمل معنا';

  @override
  String get whoWouldYouRideFor => 'مع أي شركة تريد العمل؟';

  @override
  String get theCompanyDecidesNotUs =>
      'أنت تتقدّم إلى الشركة وليس إلينا. هي من تقرأ الطلب وتقرّر، وسنبلغك بالنتيجة في الحالتين.';

  @override
  String get couldNotLoadCompanies => 'تعذّر تحميل الشركات.';

  @override
  String get nobodyIsHiringRightNow =>
      'لا توجد شركات توصيل تستقبل طلبات حالياً.';

  @override
  String get aboutYou => 'عنك';

  @override
  String get yourName => 'اسمك';

  @override
  String get anythingWeShouldKnowRider => 'شيء يجب أن يعرفوه؟ (اختياري)';

  @override
  String get yourEmail => 'بريدك الإلكتروني';

  @override
  String get weSendACodeToCheckItReachesYou =>
      'نرسل رمزاً من ستة أرقام للتأكد من وصوله إليك. كل ما يلي ذلك يُرسل إليه، بما في ذلك طريقة تسجيل الدخول.';

  @override
  String get yourPhoneOptional => 'رقم هاتفك (اختياري)';

  @override
  String get aNumberHelpsWhenAnOrderNeedsSorting =>
      'مفيد عندما يحتاج أمر يخص التوصيل إلى حل سريع. تخطَّه إن لم ترغب.';

  @override
  String get sendCode => 'أرسل الرمز';

  @override
  String get sendAnother => 'أرسل رمزاً آخر';

  @override
  String get theCodeWeSent => 'الرمز الذي أرسلناه';

  @override
  String get verify => 'تحقّق';

  @override
  String get skipThis => 'تخطَّ هذا';

  @override
  String get continueLabel => 'متابعة';

  @override
  String get sendApplication => 'أرسل الطلب';

  @override
  String get applicationSent => 'تم إرسال الطلب';

  @override
  String companyWillBeInTouch(String company) {
    return 'ستقرأ $company طلبك وتتواصل معك عبر البريد الإلكتروني.';
  }

  @override
  String get keepThisReference => 'احتفظ بهذا الرقم المرجعي';

  @override
  String get done => 'تم';

  @override
  String get paymentMethod => 'طريقة الدفع';

  @override
  String get cashOnDelivery => 'الدفع عند الاستلام';

  @override
  String get card => 'بطاقة';

  @override
  String get payTheRiderWhenItArrives => 'ادفع للمندوب عند وصول طلبك';

  @override
  String get cardNotAvailableYet => 'غير متاح حالياً';

  @override
  String get paymentDue => 'مستحق عند التسليم';

  @override
  String get paymentAwaitingAuthorisation => 'بانتظار التفويض';

  @override
  String get paymentAuthorised => 'تم التفويض';

  @override
  String get paymentPaid => 'مدفوع';

  @override
  String get paymentRefunded => 'تم الاسترداد';

  @override
  String get paymentFailed => 'فشل الدفع';

  @override
  String get chooseAnAddress => 'اختر عنواناً';

  @override
  String get addANewAddress => 'أضف عنواناً جديداً';

  @override
  String riderGreeting(String name) {
    return 'أهلاً، $name';
  }

  @override
  String get riderHeaderLine => 'هذا ما هو متاح على اللوحة الآن.';

  @override
  String riderWaitingCount(int count) {
    return '$count بالانتظار';
  }

  @override
  String riderOnTheWayCount(int count) {
    return '$count في الطريق';
  }

  @override
  String get newJobsAppearHere =>
      'تظهر المهام الجديدة هنا فور تجهيز المتجر لأي طلب.';

  @override
  String get claimOneToSeeItHere => 'اقبل مهمة من قائمة المتاح وستظهر هنا.';

  @override
  String collectCash(String amount) {
    return 'حصّل $amount نقداً';
  }

  @override
  String get alreadyPaid => 'مدفوع مسبقاً';

  @override
  String get partnerChoiceTitle => 'بيع أو وصّل معنا';

  @override
  String get partnerChoiceIntro => 'اختر ما ينطبق عليك وسنكمل معك الخطوات.';

  @override
  String get applyAsMerchant => 'بيع على يو دروب';

  @override
  String get applyAsMerchantBlurb => 'لديك متجر وتريد عرض منتجاتك في التطبيق.';

  @override
  String get applyAsRider => 'وصّل مع يو دروب';

  @override
  String get applyAsRiderBlurb => 'تريد توصيل الطلبات وتتقاضى أجرًا عن كل طلب.';

  @override
  String get whoWillYouRideFor => 'لمن ستوصّل؟';

  @override
  String get rideForYouDrop => 'يو دروب';

  @override
  String get rideForYouDropBlurb =>
      'انضم إلى أسطولنا. نحن نراجع طلبك ونحن ندفع لك.';

  @override
  String get rideForACompany => 'شركة توصيل';

  @override
  String get rideForACompanyBlurb =>
      'قدّم إلى إحدى الشركات أدناه. هي من تقرر، لا نحن.';

  @override
  String get yourBusiness => 'نشاطك التجاري';

  @override
  String get businessName => 'اسم النشاط';

  @override
  String get theNameCustomersWillSee => 'الاسم الذي سيراه العملاء في التطبيق.';

  @override
  String get yourNameAsOwner => 'اسمك';

  @override
  String get anythingWeShouldKnowMerchant =>
      'هل من شيء نحتاج معرفته؟ (اختياري)';

  @override
  String get weWillBeInTouch => 'سنقرأ طلبك ونتواصل معك عبر البريد.';

  @override
  String get finishSettingUpInTheApp =>
      'جهّز متجرك الآن وتصفّح كل شيء. يُفتح النشر في السوق بعد الموافقة.';

  @override
  String get continueAsGuest => 'المتابعة بدون حساب';

  @override
  String get guestApplicationExplainer =>
      'لا تحتاج حسابًا لتقديم الطلب. تختار رمز الدخول في النهاية وتستطيع الدخول فورًا ومتابعة طلبك أثناء مراجعتنا له.';

  @override
  String codeSentTo(String destination) {
    return 'أرسلنا رمزًا من 6 أرقام إلى $destination. ينتهي خلال 10 دقائق ويُستخدم مرة واحدة.';
  }

  @override
  String get enterTheCode => 'أدخل الرمز';

  @override
  String get didntGetIt => 'لم يصلك؟';

  @override
  String get yourApplicationReference => 'رقم طلبك المرجعي';

  @override
  String get referenceExplainer =>
      'اذكره عند التواصل معنا، واستخدمه لمتابعة طلبك في أي وقت. ليس كلمة مرور ولا يُستخدم لتسجيل الدخول.';

  @override
  String get unlockWithFingerprint => 'افتح ببصمة الإصبع';

  @override
  String get useFingerprintNextTime => 'استخدم بصمتك في المرة القادمة';

  @override
  String get fingerprintKeepsYourAccountClosed =>
      'تبقى جلستك مقفلة حتى تفتحها، فلا يستطيع من يمسك هاتفك الدخول إلى حسابك.';

  @override
  String get fingerprintNotSetUp =>
      'لا توجد بصمة أو تعرّف وجه مُسجّل على هذا الهاتف. أضِف واحدة من إعدادات أندرويد ثم عُد إلى هنا.';

  @override
  String get couldNotVerifyYou =>
      'تعذر التحقق منك. أعد المحاولة أو سجّل الدخول برمز الدخول.';

  @override
  String get signInWithPasscodeInstead => 'سأستخدم رمز الدخول';

  @override
  String get locked => 'مقفل';

  @override
  String get notNow => 'ليس الآن';

  @override
  String get turnOn => 'تفعيل';

  @override
  String get biometricUnlock => 'الفتح بالبصمة';

  @override
  String get chooseYourPasscode => 'اختر رمز الدخول';

  @override
  String get passcodeLetsYouFollowIt =>
      'ستة أرقام. ستستخدمها لتسجيل الدخول ومتابعة طلبك أثناء مراجعتنا له.';

  @override
  String get applicationPending => 'تم استلام طلبك';

  @override
  String get weAreReadingIt =>
      'نقرأ طلبك الآن. سنراسلك فور صدور القرار، وتبقى الحالة ظاهرة هنا.';

  @override
  String companyIsReadingIt(String company) {
    return '$company تقرأ طلبك. ستصلك رسالة فور اتخاذ القرار.';
  }

  @override
  String get applicationStatus => 'الحالة';

  @override
  String get statusSubmitted => 'بانتظار المراجعة';

  @override
  String get statusInReview => 'قيد المراجعة الآن';

  @override
  String get statusApproved => 'تمت الموافقة — يجري إعداد حسابك';

  @override
  String get statusRejected => 'لم يُقبل';

  @override
  String get statusProvisioned => 'تمت الموافقة';

  @override
  String get statusFailed => 'حدث خطأ أثناء إعداد حسابك. نحن نعالج الأمر.';

  @override
  String get checkAgain => 'تحديث';

  @override
  String get whatHappensNext => 'ما الخطوة التالية';

  @override
  String get nextStepsPending =>
      'لا شيء عليك الآن. بعد الموافقة يصبح هذا التطبيق متجرك أو لوحة طلباتك — بنفس تسجيل الدخول ونفس رمز الدخول.';

  @override
  String get couldNotCreateSignIn =>
      'تعذّر إعداد تسجيل الدخول. طلبك استُلم على أي حال.';

  @override
  String get pendingBannerMerchant =>
      'طلبك قيد المراجعة. جهّز متجرك الآن — يمكنك النشر في السوق بعد الموافقة.';

  @override
  String get pendingBannerRider =>
      'طلبك قيد المراجعة. تصفّح لوحة الطلبات — يمكنك استلام التوصيلات بعد الموافقة.';

  @override
  String get notWhilePending => 'يمكنك فعل ذلك بعد الموافقة على طلبك.';

  @override
  String get viewApplication => 'عرض الطلب';

  @override
  String get accountReadySignInInstead =>
      'حسابك جاهز، لكن تعذّر تسجيل دخولك. أغلق هذه الشاشة وسجّل الدخول ببريدك ورمز الدخول الذي اخترته.';

  @override
  String get dayByDay => 'يومًا بيوم';

  @override
  String get authTagline => 'أي شيء يُوصَل، إلى أي مكان';

  @override
  String get authRoleCustomer => 'زبون';

  @override
  String get authRoleCustomerBlurb => 'اطلب واستلم توصيلاتك';

  @override
  String get authRoleRider => 'سائق توصيل';

  @override
  String get authRoleRiderBlurb => 'وصّل الطلبات واكسب';

  @override
  String get authRoleMerchant => 'تاجر';

  @override
  String get authRoleMerchantBlurb => 'بِع ونمِّ عملك';

  @override
  String get authAlreadyHaveAnAccount => 'لديك حساب بالفعل؟';

  @override
  String get authDontHaveAnAccount => 'ليس لديك حساب؟';

  @override
  String get authSignUp => 'أنشئ حساباً';

  @override
  String get authSignInSubtitle => 'أدخل بياناتك لتسجيل الدخول.';

  @override
  String get authEmailOrPhone => 'البريد الإلكتروني أو رقم الهاتف';

  @override
  String get authEmailOrPhoneHint => 'مثال: name@domain.com أو ‎+961…';

  @override
  String get authPasscodeHint => 'رمزك المكوَّن من ستة أرقام';

  @override
  String get authForgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get authUseTheKeypad => 'استخدم لوحة الأرقام';

  @override
  String get authOrContinueWith => 'أو تابع باستخدام';

  @override
  String get authComingSoon => 'قريباً';

  @override
  String get authShowPassword => 'إظهار الرمز';

  @override
  String get authHidePassword => 'إخفاء الرمز';

  @override
  String get authDeleteDigit => 'حذف آخر رقم';

  @override
  String get authCreateAccountSubtitle => 'ابدأ باستلام أي شيء إلى أي مكان.';

  @override
  String get authFullName => 'الاسم الكامل';

  @override
  String get authFullNameHint => 'مثال: سارة جنكينز';

  @override
  String get authEmailAddress => 'البريد الإلكتروني';

  @override
  String get authEmailHint => 'مثال: sarah.j@gmail.com';

  @override
  String get authPhoneNumber => 'رقم الهاتف';

  @override
  String get authPhoneHint => '70 123 456';

  @override
  String get authConfirmPassword => 'تأكيد الرمز';

  @override
  String get authPasscodeKeepGoing => 'تابع';

  @override
  String get authPasscodeComplete => 'مكتمل';

  @override
  String get authAgreeToTerms => 'أوافق على الشروط وسياسة الخصوصية';

  @override
  String get authTermsPrefix => 'بإنشائك حساباً فإنك توافق على ';

  @override
  String get authTermsOfService => 'شروط الخدمة';

  @override
  String get authTermsAnd => ' و';

  @override
  String get authPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get authPleaseAcceptTheTerms => 'يرجى الموافقة على الشروط للمتابعة.';

  @override
  String get authVerifyYourEmail => 'تحقق من بريدك الإلكتروني';

  @override
  String get authVerifyYourNumber => 'تحقق من رقمك';

  @override
  String get authStep => 'الخطوة';

  @override
  String get authComplete => 'مكتمل';

  @override
  String get authNext => 'التالي';

  @override
  String get authGetStarted => 'لنبدأ';

  @override
  String get authSubmitApplication => 'إرسال الطلب';

  @override
  String get authSendingApplication => 'جارٍ إرسال طلبك…';

  @override
  String get authCouldNotSendApplication =>
      'تعذّر إرسال طلبك. لم يُفقد شيء — حاول مرة أخرى.';

  @override
  String get authRiderIntroTitle => 'انضم كسائق توصيل';

  @override
  String get authRiderIntroBlurb =>
      'ساعات مرنة، أجر تنافسي، وتنقّل سهل — ابدأ التوصيل مع يودروب خلال دقائق.';

  @override
  String get authRiderBenefitHours => 'ساعات مرنة';

  @override
  String get authRiderBenefitPay => 'أجر تنافسي';

  @override
  String get authRiderBenefitNavigation => 'تنقّل سهل';

  @override
  String get authWhatYouNeedToSignUp => 'ما تحتاجه للتسجيل';

  @override
  String get authNeedValidId => 'هوية سارية';

  @override
  String get authNeedDriversLicence => 'رخصة قيادة';

  @override
  String get authNeedVehicleDocuments => 'أوراق المركبة';

  @override
  String get authMerchantSignUp => 'تسجيل التاجر';

  @override
  String get authMerchantIntroTitle => 'سجّل عملك';

  @override
  String get authMerchantIntroBlurb =>
      'اصل إلى زبائن أكثر، أدر منتجاتك بسهولة، وتابع أداءك لحظة بلحظة.';

  @override
  String get authWhatYouGet => 'ما ستحصل عليه';

  @override
  String get authMerchantBenefitReach =>
      'الوصول إلى زبائن أكثر عبر شبكة التوصيل لدينا';

  @override
  String get authMerchantBenefitManage => 'إدارة سهلة للمنتجات وتنفيذ الطلبات';

  @override
  String get authMerchantBenefitAnalytics => 'تحليلات لحظية لتحسين مبيعاتك';

  @override
  String get authWhatYouNeed => 'ما تحتاجه';

  @override
  String get authNeedBusinessLicence => 'رخصة تجارية';

  @override
  String get authNeedTaxCertificate => 'شهادة ضريبية';

  @override
  String get authNeedBankDetails => 'بيانات الحساب المصرفي';

  @override
  String get authPersonalInformation => 'المعلومات الشخصية';

  @override
  String get authPersonalInformationBlurb =>
      'املأ بياناتك الأساسية لإنشاء ملفك كسائق توصيل.';

  @override
  String get authDateOfBirth => 'تاريخ الميلاد';

  @override
  String get authDateOfBirthHint => 'يوم / شهر / سنة';

  @override
  String get authNationalId => 'رقم الهوية الوطنية';

  @override
  String get authNationalIdHint => 'كما هو مطبوع على هويتك';

  @override
  String get authVehicleDetails => 'تفاصيل المركبة';

  @override
  String get authVehicleDetailsBlurb =>
      'اختر فئة مركبتك وسجّل بياناتها الرسمية.';

  @override
  String get authVehicleType => 'نوع المركبة';

  @override
  String get authVehicleMotorcycle => 'دراجة نارية';

  @override
  String get authVehicleCar => 'سيارة';

  @override
  String get authVehicleBicycle => 'دراجة هوائية';

  @override
  String get authVehicleVan => 'شاحنة صغيرة';

  @override
  String get authVehicleModel => 'ماركة المركبة / الطراز';

  @override
  String get authVehicleModelHint => 'مثال: ياماها TMAX / تويوتا يارِس';

  @override
  String get authPlateNumber => 'رقم اللوحة';

  @override
  String get authPlateNumberHint => 'مثال: 1234 ABC';

  @override
  String get authVehicleYear => 'سنة الصنع';

  @override
  String get authVehicleYearHint => 'مثال: 2024';

  @override
  String get authSelectDeliveryZone => 'اختر منطقة التوصيل';

  @override
  String get authSelectDeliveryZoneBlurb =>
      'في أي مناطق من المدينة تفضّل التوصيل؟';

  @override
  String get authMapComingSoon => 'خريطة التغطية قريباً';

  @override
  String get authPreferredArea => 'المنطقة المفضّلة';

  @override
  String get authPreferredAreaHint => 'مثال: الحمرا، الأشرفية';

  @override
  String get authAvailableZones => 'المناطق المتاحة';

  @override
  String get authZonesComingSoonTitle => 'لم تُرسَم المناطق بعد';

  @override
  String get authZonesComingSoonBlurb =>
      'ستتوفّر المناطق القابلة للاختيار مع خريطة التغطية. حتى ذلك الحين نعتمد على المنطقة المذكورة أعلاه.';

  @override
  String get authBusinessInformation => 'معلومات العمل';

  @override
  String get authBusinessInformationBlurb =>
      'أخبرنا عن شركتك وعن الشخص المسؤول.';

  @override
  String get authBusinessShopName => 'اسم العمل / المتجر';

  @override
  String get authBusinessShopNameHint => 'مثال: مطعم روز غاردن';

  @override
  String get authOwnerFullName => 'الاسم الكامل للمالك';

  @override
  String get authOwnerFullNameHint => 'مثال: جين كوبر';

  @override
  String get authBusinessType => 'نوع العمل';

  @override
  String get authBusinessTypeHint => 'اختر واحداً';

  @override
  String get authBusinessTypeRestaurant => 'مطعم';

  @override
  String get authBusinessTypeGrocery => 'بقالة';

  @override
  String get authBusinessTypePharmacy => 'صيدلية';

  @override
  String get authBusinessTypeBakery => 'مخبز';

  @override
  String get authBusinessTypeRetail => 'بيع بالتجزئة';

  @override
  String get authBusinessTypeOther => 'أخرى';

  @override
  String get authContactEmail => 'البريد الإلكتروني للتواصل';

  @override
  String get authReviewAndSubmit => 'المراجعة والإرسال';

  @override
  String get authReviewAndSubmitBlurb =>
      'راجع ما سنرسله. يمكنك العودة وتعديل أي شيء.';

  @override
  String get authDocuments => 'المستندات';

  @override
  String get authDocumentsBlurb => 'الأوراق التي سنحتاجها قبل أن تبدأ.';

  @override
  String get authDocumentsComingSoonTitle => 'رفع المستندات سيتاح قريباً';

  @override
  String get authDocumentsComingSoonBlurb =>
      'يمكنك إكمال طلبك من دونه — سنطلب الأوراق عبر البريد الإلكتروني قبل أن تبدأ.';

  @override
  String get authBankDetails => 'بيانات الحساب المصرفي';

  @override
  String get authBankDetailsBlurb => 'إلى أين ستُحوَّل أرباحك.';

  @override
  String get authBankComingSoonTitle => 'إعداد التحويلات سيتاح قريباً';

  @override
  String get authBankComingSoonBlurb =>
      'لا نأخذ بيانات الحساب المصرفي قبل صدور القرار. ستُعدّ التحويلات بعد الموافقة على طلبك.';

  @override
  String get authApplicationSubmitted => 'تم إرسال الطلب';

  @override
  String get authApplicationSubmittedBlurb =>
      'استلمنا طلبك وفريق العمليات لدينا يطّلع عليه الآن.';

  @override
  String get authWhatToExpectNext => 'ما الذي سيحدث تالياً';

  @override
  String get authExpectVerification => 'نتحقق من بياناتك (١–٣ أيام)';

  @override
  String get authExpectBackgroundCheck => 'التحقق من الخلفية';

  @override
  String get authExpectTrainingInvite => 'دعوة إلى تدريب السائقين';

  @override
  String get authWeWillNotifyYou =>
      'سنعلمك عبر البريد الإلكتروني فور صدور القرار.';

  @override
  String get authApplicationUnderReview => 'الطلب قيد المراجعة';

  @override
  String get authApplicationUnderReviewBlurb =>
      'شكراً لك. وصلنا تسجيلك وفريقنا يراجعه الآن. عادةً ما يستغرق ذلك يوماً أو يومين.';

  @override
  String get authExplorationModeActive => 'وضع الاستكشاف مُفعَّل';

  @override
  String get authExplorationModeBlurb =>
      'بينما تنتظر، يمكنك إعداد منتجاتك وقوائمك والتجوّل في التطبيق. لن يُنشر شيء قبل الموافقة على طلبك.';

  @override
  String get authApplicationChecklist => 'قائمة مراحل الطلب';

  @override
  String get authChecklistAccountCreated => 'أُنشئ الحساب';

  @override
  String get authChecklistDocuments => 'رفع المستندات';

  @override
  String get authChecklistAudit => 'التدقيق الأمني والامتثال';

  @override
  String get authChecklistActivation => 'تفعيل المتجر ونشره';

  @override
  String get authExploreDashboard => 'استكشف لوحة التحكم';

  @override
  String get custSeeAll => 'عرض الكل';

  @override
  String get custShowLess => 'عرض أقل';

  @override
  String get custAllCategories => 'كل الفئات';

  @override
  String get custFilters => 'عوامل التصفية';

  @override
  String get custMyBasket => 'سلّتي';

  @override
  String get custPromoCode => 'رمز الخصم';

  @override
  String get custApply => 'تطبيق';

  @override
  String get custOrderSummary => 'ملخّص الطلب';

  @override
  String get custDiscounts => 'الخصومات';

  @override
  String get custTotalAmount => 'المبلغ الإجمالي';

  @override
  String get custProceedToCheckout => 'المتابعة إلى الدفع';

  @override
  String get custAddToBasket => 'أضف إلى السلة';

  @override
  String get custDeliveryTime => 'وقت التوصيل';

  @override
  String get custMinOrderStat => 'الحد الأدنى';

  @override
  String custRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تقييم',
      many: '$count تقييمًا',
      few: '$count تقييمات',
      two: 'تقييمان',
      one: 'تقييم واحد',
      zero: 'لا تقييمات',
    );
    return '$_temp0';
  }

  @override
  String custShopsInCategory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count متجر',
      many: '$count متجرًا',
      few: '$count متاجر',
      two: 'متجران',
      one: 'متجر واحد',
      zero: 'لا متاجر',
    );
    return '$_temp0';
  }

  @override
  String get custPeopleAlsoOrdered => 'طلب الآخرون أيضًا';

  @override
  String get custSoon => 'قريبًا';

  @override
  String get custIncreaseQuantity => 'زيادة الكمية';

  @override
  String get custDecreaseQuantity => 'إنقاص الكمية';

  @override
  String get custSearchInShop => 'ابحث في هذا المتجر';

  @override
  String get custShopSearchHint => 'ابحث في القائمة';

  @override
  String get custButlerTitle => 'خدمة يودروب الشخصية';

  @override
  String get custChooseWhatYouNeed => 'اختر ما تحتاج المساعدة فيه';

  @override
  String get custBuyAnything => 'اشترِ أي شيء';

  @override
  String get custBuyAnythingBlurb => 'نشتري ونوصّل من أي مكان';

  @override
  String get custSendAnything => 'أرسل أي شيء';

  @override
  String get custSendAnythingBlurb => 'توصيل واستلام وإرسال الأغراض';

  @override
  String get custRecentTasks => 'المهام الأخيرة';

  @override
  String get custSearchTasksHint => 'ابحث في مهامك';

  @override
  String get custNoTasksMatch => 'لا توجد مهام تطابق هذا البحث';

  @override
  String get custStatusPending => 'قيد الانتظار';

  @override
  String get custWaitingOnYou => 'بانتظار ردّك';

  @override
  String get custApplePay => 'أبل باي';

  @override
  String get custOrderNotes => 'ملاحظات الطلب';

  @override
  String get custOrderNotesHint =>
      'مثلًا: اترك الطلب عند الباب، الجرس لا يعمل...';

  @override
  String get custTotalPrice => 'السعر الإجمالي';

  @override
  String get custPlaceOrder => 'تأكيد الطلب';

  @override
  String get custOrderStatus => 'حالة الطلب';

  @override
  String get custOrderRef => 'طلب';

  @override
  String get custItemsOrdered => 'الأصناف المطلوبة';

  @override
  String get custLiveMap => 'الخريطة المباشرة';

  @override
  String get custAccountSettings => 'إعدادات الحساب';

  @override
  String get custAppLanguage => 'لغة التطبيق';

  @override
  String get custMyAddresses => 'عناويني';

  @override
  String get custPaymentMethods => 'طرق الدفع';

  @override
  String get custOrderHistory => 'سجل الطلبات';

  @override
  String get custHelpSupport => 'المساعدة والدعم';

  @override
  String get custLabelAddressAs => 'سمِّ هذا العنوان:';

  @override
  String get custLabelHome => 'المنزل';

  @override
  String get custLabelWork => 'العمل';

  @override
  String get custLabelOther => 'أخرى';

  @override
  String get merchTodaySummary => 'ملخص اليوم';

  @override
  String get merchPendingOrders => 'الطلبات المعلّقة';

  @override
  String get merchNewOrders => 'طلبات جديدة';

  @override
  String get merchView => 'عرض';

  @override
  String get merchRecentOrders => 'أحدث الطلبات';

  @override
  String get merchViewAll => 'عرض الكل';

  @override
  String get merchActive => 'نشط';

  @override
  String get merchInactive => 'غير نشط';

  @override
  String get merchPublishShop => 'انشر متجرك';

  @override
  String get merchShopHidden => 'تم إخفاء متجرك عن السوق.';

  @override
  String get merchOrderFlow => 'مسار الطلبات';

  @override
  String get merchManagerView => 'عرض المدير';

  @override
  String get merchTabNew => 'جديد';

  @override
  String get merchTabCompleted => 'مكتملة';

  @override
  String get merchReject => 'رفض';

  @override
  String get merchFlowStatus => 'حالة المسار';

  @override
  String get merchCustomerDetails => 'بيانات العميل';

  @override
  String get merchItemsBreakdown => 'تفاصيل الأصناف';

  @override
  String get merchSpecialInstructions => 'تعليمات خاصة';

  @override
  String get merchGrandTotal => 'الإجمالي الكلي';

  @override
  String get merchStepPickedUp => 'تم الاستلام';

  @override
  String get merchNothingInThisList => 'لا يوجد شيء في هذه القائمة.';

  @override
  String get merchOpenOrder => 'فتح الطلب';

  @override
  String get merchbMenuItems => 'أصناف القائمة';

  @override
  String get merchbManageAvailability => 'إدارة التوفر';

  @override
  String get merchbSearchMenuItems => 'ابحث في أصناف القائمة...';

  @override
  String get merchbAvailable => 'متاح';

  @override
  String get merchbOffShelf => 'خارج العرض';

  @override
  String get merchbAddProduct => 'إضافة منتج';

  @override
  String get merchbAvailability => 'التوفر';

  @override
  String get merchbNoMatchingItems => 'لا توجد أصناف مطابقة';

  @override
  String get merchbAddNewProduct => 'إضافة منتج جديد';

  @override
  String get merchbProductImage => 'صورة المنتج';

  @override
  String get merchbUploadImageCta => 'ارفع صورة شهية للطبق';

  @override
  String get merchbUploadHint => 'PNG أو JPG بحجم أقصاه 5 ميغابايت';

  @override
  String get merchbVariantsOptions => 'الخيارات والإضافات';

  @override
  String get merchbAddOption => '+ إضافة خيار';

  @override
  String merchbChoicesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خيار',
      few: '$count خيارات',
      two: 'خياران',
      one: 'خيار واحد',
    );
    return '$_temp0';
  }

  @override
  String get merchbNoOptionsYet => 'لا توجد خيارات على هذا الصنف بعد';

  @override
  String get merchbOptionsReadOnly =>
      'تظهر كما يراها الزبون. تعديل الخيارات سيتوفر قريباً.';

  @override
  String get merchbSaveMenuItem => 'حفظ الصنف';

  @override
  String get merchbSoon => 'قريباً';

  @override
  String get merchbShopConfiguration => 'إعدادات المتجر';

  @override
  String get merchbShopStatus => 'حالة المتجر';

  @override
  String get merchbBannerAndLogo => 'غلاف المتجر وشعاره';

  @override
  String get merchbChangeCover => 'تغيير الغلاف';

  @override
  String get merchbChangeLogo => 'تغيير الشعار';

  @override
  String get merchbShopAddress => 'عنوان المتجر';

  @override
  String get merchbMapPreviewSoon => 'معاينة الخريطة';

  @override
  String get merchbOperatingDetails => 'تفاصيل التشغيل';

  @override
  String get merchbSaveShopSettings => 'حفظ إعدادات المتجر';

  @override
  String merchbHoursDaily(String from, String to) {
    return 'يومياً: $from - $to';
  }

  @override
  String get merchbHoursCustom => 'جدول مخصص';

  @override
  String get merchbHoursNone => 'لم تُحدَّد ساعات العمل';

  @override
  String get merchbEditHours => 'تعديل ساعات العمل';

  @override
  String get merchbDay => 'اليوم';

  @override
  String get merchbTimeHint => 'ساعة:دقيقة';

  @override
  String get merchbDayMonday => 'الاثنين';

  @override
  String get merchbDayTuesday => 'الثلاثاء';

  @override
  String get merchbDayWednesday => 'الأربعاء';

  @override
  String get merchbDayThursday => 'الخميس';

  @override
  String get merchbDayFriday => 'الجمعة';

  @override
  String get merchbDaySaturday => 'السبت';

  @override
  String get merchbDaySunday => 'الأحد';

  @override
  String get merchbAccountSettings => 'إعدادات الحساب';

  @override
  String get merchbRoleOwner => 'المالك';

  @override
  String get merchbAppLanguage => 'لغة التطبيق';

  @override
  String get merchbLangShortEn => 'EN';

  @override
  String get merchbLangShortAr => 'AR';

  @override
  String get merchbShopProfile => 'ملف المتجر';

  @override
  String get merchbPaymentBankDetails => 'الدفع والحساب البنكي';

  @override
  String get merchbNotificationSettings => 'إعدادات الإشعارات';

  @override
  String get merchbShopAnalytics => 'تحليلات المتجر';

  @override
  String get merchbLogOutAccount => 'تسجيل الخروج من الحساب';

  @override
  String get riderComingSoon => 'قريباً';

  @override
  String get riderTabAvailable => 'المتاحة';

  @override
  String get riderTabActive => 'الجارية';

  @override
  String get riderTabEarnings => 'الأرباح';

  @override
  String get riderSegmentDeliveries => 'التوصيلات';

  @override
  String get riderRegionZone => 'منطقة العمل';

  @override
  String riderDeliveriesNearby(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count توصيلة قريبة',
      many: '$count توصيلة قريبة',
      few: '$count توصيلات قريبة',
      two: 'توصيلتان قريبتان',
      one: 'توصيلة واحدة قريبة',
      zero: 'لا توجد توصيلات قريبة',
    );
    return '$_temp0';
  }

  @override
  String get riderOffersNearYou => 'عروض قريبة منك';

  @override
  String get riderAcceptDelivery => 'قبول التوصيلة';

  @override
  String get riderMyActiveTasks => 'مهامي الجارية';

  @override
  String riderActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جارية',
      many: '$count جارية',
      few: '$count جارية',
      two: 'اثنتان جاريتان',
      one: 'واحدة جارية',
      zero: 'لا يوجد جارٍ',
    );
    return '$_temp0';
  }

  @override
  String riderOrderRef(String ref) {
    return 'طلب رقم $ref';
  }

  @override
  String riderMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'منذ $minutes دقيقة',
      many: 'منذ $minutes دقيقة',
      few: 'منذ $minutes دقائق',
      two: 'منذ دقيقتين',
      one: 'منذ دقيقة',
      zero: 'الآن',
    );
    return '$_temp0';
  }

  @override
  String riderHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'منذ $hours ساعة',
      many: 'منذ $hours ساعة',
      few: 'منذ $hours ساعات',
      two: 'منذ ساعتين',
      one: 'منذ ساعة',
      zero: 'الآن',
    );
    return '$_temp0';
  }

  @override
  String get riderNavigate => 'الاتجاهات';

  @override
  String get riderViewDetails => 'عرض التفاصيل';

  @override
  String get riderStartNavigation => 'بدء التوجيه';

  @override
  String get riderYourPayout => 'مستحقاتك';

  @override
  String get riderRouteTimeline => 'مسار الرحلة';

  @override
  String get riderPickupAddress => 'عنوان الاستلام';

  @override
  String get riderDeliveryAddress => 'عنوان التسليم';

  @override
  String get riderItemsToCollect => 'الأصناف المطلوب استلامها';

  @override
  String riderItemLine(int qty, String name) {
    return '$qty× $name';
  }

  @override
  String get riderNoItemsListed => 'لا توجد قائمة أصناف لهذا الطلب.';

  @override
  String get riderDeliveryInstructions => 'تعليمات التسليم';

  @override
  String get riderMyEarnings => 'أرباحي';

  @override
  String get riderPayout => 'صرف المستحقات';

  @override
  String get riderPeriodToday => 'اليوم';

  @override
  String get riderPeriodWeekly => 'أسبوعي';

  @override
  String get riderTotalEarnings => 'إجمالي الأرباح';

  @override
  String get riderEarningsDerived =>
      'محسوبة من رسوم التوصيل على التوصيلات التي أكملتها بنفسك.';

  @override
  String get riderHoursOnline => 'ساعات الاتصال';

  @override
  String get riderAcceptRate => 'معدل القبول';

  @override
  String get riderRating => 'التقييم';

  @override
  String get riderWeeklyOverview => 'نظرة على الأسبوع';

  @override
  String get riderTodaysDeliveries => 'توصيلات اليوم';

  @override
  String get riderThisWeeksDeliveries => 'توصيلات هذا الأسبوع';

  @override
  String get riderNothingDeliveredYet =>
      'لم تُسلَّم أي توصيلة في هذه الفترة بعد.';

  @override
  String get riderCouldNotLoadEarnings => 'تعذّر تحميل أرباحك';

  @override
  String get riderDriverSettings => 'إعدادات السائق';

  @override
  String get riderVehicleProfile => 'بيانات المركبة';

  @override
  String get riderActiveDuty => 'على رأس العمل (متصل)';

  @override
  String get riderAppLanguage => 'لغة التطبيق';

  @override
  String get riderDocuments => 'المستندات والرخص';

  @override
  String get riderBankDetails => 'بيانات الحساب البنكي';

  @override
  String get riderNotificationPreferences => 'تفضيلات الإشعارات';

  @override
  String get riderHelpAndSupport => 'المساعدة والدعم المباشر';

  @override
  String get riderErrandTry => 'جرّب';

  @override
  String get riderErrandTo => 'إلى';

  @override
  String get riderErrandCap => 'الحد الأقصى';
}
